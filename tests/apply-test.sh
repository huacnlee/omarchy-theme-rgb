#!/bin/bash
# Exercises bin/omarchy-theme-rgb-apply against a mock openrgb that records
# the arguments it was called with, inside a throwaway HOME.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY="$ROOT/bin/omarchy-theme-rgb-apply"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mock_bin="$tmp/bin"
home="$tmp/home"
theme="$home/.local/state/omarchy/current/theme"
calls="$tmp/calls"
mkdir -p "$mock_bin" "$theme"

cat >"$mock_bin/openrgb" <<'SH'
#!/bin/bash
printf 'openrgb %s\n' "$*" >>"$CALL_LOG"
if [[ $* == *"--list-devices"* ]]; then
  [[ ${OPENRGB_LIST_FAIL:-0} == 1 ]] && exit 1
  printf '%s\n' "$OPENRGB_LIST_DEVICES"
  exit 0
fi
[[ ${OPENRGB_APPLY_FAIL:-0} == 1 ]] && { echo "device went away" >&2; exit 3; }
exit 0
SH
chmod +x "$mock_bin/openrgb"

failures=0
pass() { echo "ok - $1"; }
fail() {
  echo "not ok - $1"
  [[ -n ${2:-} ]] && printf '  %s\n' "$2"
  failures=$((failures + 1))
}

run_apply() {
  : >"$calls"
  HOME="$home" CALL_LOG="$calls" \
    OPENRGB_LIST_DEVICES="${OPENRGB_LIST_DEVICES:-}" OPENRGB_LIST_FAIL="${OPENRGB_LIST_FAIL:-0}" OPENRGB_APPLY_FAIL="${OPENRGB_APPLY_FAIL:-0}" \
    PATH="$mock_bin:$PATH" "$APPLY"
}

called() { grep -Fqx "$1" "$calls"; }
call_count() { grep -c '^openrgb' "$calls" || true; }
set_config() { mkdir -p "$home/.config/omarchy"; printf '%s\n' "$1" >"$home/.config/omarchy/theme-rgb.json"; }
# stops prints "desk a,b,c" and "ambient a,b,c"; these pick one line.
stops() { HOME="$home" PATH="$mock_bin:$PATH" "$APPLY" stops | awk -v c="${1:-desk}" '$1 == c { print $2 }'; }
variables() { HOME="$home" "$APPLY" variables; }

# Pure colours keep expectations readable.
cat >"$theme/colors.toml" <<'TOML'
accent = "#0000ff"
background = "#001000"
foreground = "#ffffff"
red = "#ff0000"
orange = "#ff8000"
yellow = "#ffff00"
green = "#00ff00"
cyan = "#00ffff"
blue = "#0080ff"
magenta = "#ff00ff"
brown = "#8000ff"
TOML

PLAIN_DEVICES='0: Logitech G512 RGB
  Type:           Keyboard
  Modes: [Direct] Static Off Cycle Breathing
1: Razer Basilisk V3
  Type:           Mouse
  Modes: [Direct] Off Static '"'"'Spectrum Cycle'"'"' Wave'

# ==========================================================================
# single colour
# ==========================================================================
set_config '{"mode": "single"}'

# --- single mode is the accent on every device, in one static call --------
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if (( $(call_count) == 2 )) \
  && called 'openrgb -d 0 -m static -c 0000ff -b 100 -d 1 -m static -c 0000ff -b 100'; then
  pass "single mode is the accent on every device, in one static call"
else
  fail "single mode is the accent on every device, in one static call" "$(cat "$calls")"
fi

# --- gradient-capable devices prefer their gradient mode ------------------
OPENRGB_LIST_DEVICES='0: Fake Board
  Modes: Direct Static Gradient Wave
1: Other Pad
  Modes: [Direct] Off Static '"'"'Rainbow Gradient'"'"'' run_apply
if called 'openrgb -d 0 -m Gradient -c 0000ff -b 100 -d 1 -m Rainbow Gradient -c 0000ff -b 100'; then
  pass "gradient-capable devices prefer their gradient mode"
else
  fail "gradient-capable devices prefer their gradient mode" "$(cat "$calls")"
fi

# --- failed detection falls back to a static broadcast --------------------
if OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" OPENRGB_LIST_FAIL=1 run_apply \
  && called 'openrgb -m static -c 0000ff -b 100'; then
  pass "failed detection falls back to a static broadcast"
else
  fail "failed detection falls back to a static broadcast" "$(cat "$calls")"
fi

# --- single mode lights the chosen variable --------------------------------
set_config '{"mode": "single", "single": "magenta"}'
if [[ $(stops) == ff00ff && $(stops ambient) == ff00ff ]]; then
  pass "single mode lights the chosen variable"
else
  fail "single mode lights the chosen variable" "$(stops) $(stops ambient)"
fi

# --- no colour source at all makes no OpenRGB calls -----------------------
mv "$theme/colors.toml" "$tmp/colors.toml.bak"
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if [[ ! -s $calls ]]; then
  pass "no colour source at all makes no OpenRGB calls"
else
  fail "no colour source at all makes no OpenRGB calls" "$(cat "$calls")"
fi

# --- an invalid colour makes no OpenRGB calls -----------------------------
printf 'accent = "purple"\n' >"$theme/colors.toml"
set_config '{"mode": "single"}'
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if [[ ! -s $calls ]]; then
  pass "an invalid colour makes no OpenRGB calls"
else
  fail "an invalid colour makes no OpenRGB calls" "$(cat "$calls")"
fi
mv "$tmp/colors.toml.bak" "$theme/colors.toml"

# --- a missing openrgb binary is a silent no-op ---------------------------
no_openrgb="$tmp/no-openrgb"
mkdir -p "$no_openrgb"
: >"$calls"
if HOME="$home" CALL_LOG="$calls" PATH="$no_openrgb" /bin/bash "$APPLY" && [[ ! -s $calls ]]; then
  pass "a missing openrgb binary is a silent no-op"
else
  fail "a missing openrgb binary is a silent no-op" "$(cat "$calls")"
fi

# --- stops prints the colours without touching openrgb --------------------
: >"$calls"
if [[ $(stops) == 0000ff && ! -s $calls ]]; then
  pass "stops prints the colours without touching openrgb"
else
  fail "stops prints the colours without touching openrgb" "$(stops; cat "$calls")"
fi

# ==========================================================================
# three, five and eight colours: the theme's own, ordered for contrast
# ==========================================================================
# Pure hues: accent 240°, red 0, orange 30, yellow 60, green 120, cyan 180,
# blue 210, magenta 300, brown 270. Accent first, then always the hue
# farthest from the previous: yellow, blue, orange, cyan, red, green,
# magenta, brown. Every device gets the same list.

# --- 3 colours: the accent, then the two most contrasting -----------------
set_config '{"mode": "palette", "colors": 3}'
if [[ $(stops) == 0000ff,ffff00,0080ff && $(stops ambient) == 0000ff,ffff00,0080ff ]]; then
  pass "3 colours: the accent, then the two most contrasting"
else
  fail "3 colours: the accent, then the two most contrasting" "$(stops) / $(stops ambient)"
fi

# --- 5 colours carry on the same order, on every device -------------------
set_config '{"mode": "palette", "colors": 5}'
if [[ $(stops) == 0000ff,ffff00,0080ff,ff8000,00ffff && $(stops ambient) == 0000ff,ffff00,0080ff,ff8000,00ffff ]]; then
  pass "5 colours carry on the same order, on every device"
else
  fail "5 colours carry on the same order, on every device" "$(stops) / $(stops ambient)"
fi

# --- 8 colours ------------------------------------------------------------
set_config '{"mode": "palette", "colors": 8}'
if [[ $(stops) == 0000ff,ffff00,0080ff,ff8000,00ffff,ff0000,00ff00,ff00ff ]]; then
  pass "8 colours"
else
  fail "8 colours" "$(stops)"
fi

# --- missing config means 5 colours ---------------------------------------
rm "$home/.config/omarchy/theme-rgb.json"
if [[ $(stops) == 0000ff,ffff00,0080ff,ff8000,00ffff ]]; then
  pass "missing config means 5 colours"
else
  fail "missing config means 5 colours" "$(stops)"
fi

# --- greys and dark tones are left out ------------------------------------
printf 'accent = "#0000ff"\nred = "#ff0000"\ncyan = "#808080"\ngreen = "#002200"\nyellow = "#ffff00"\n' >"$theme/colors.toml"
set_config '{"mode": "palette", "colors": 5}'
if [[ $(stops) == 0000ff,ffff00,ff0000 ]]; then
  pass "greys and dark tones are left out"
else
  fail "greys and dark tones are left out" "$(stops)"
fi

# --- near-duplicates collapse to one, the accent winning ------------------
# blue and green sit on the accent; orange sits on yellow: three bands, not six.
printf 'accent = "#0000ff"\nblue = "#0010ff"\ngreen = "#1000ff"\nyellow = "#ffff00"\norange = "#fff000"\nred = "#ff0000"\n' >"$theme/colors.toml"
set_config '{"mode": "palette", "colors": 8}'
if [[ $(stops) == 0000ff,fff000,ff0000 ]]; then
  pass "near-duplicates collapse to one, the accent winning"
else
  fail "near-duplicates collapse to one, the accent winning" "$(stops)"
fi

# --- background and foreground never join a tier -------------------------
printf 'accent = "#0000ff"\nbackground = "#00ff00"\nforeground = "#ff0000"\nyellow = "#ffff00"\n' >"$theme/colors.toml"
set_config '{"mode": "palette", "colors": 5}'
if [[ $(stops) == 0000ff,ffff00 ]]; then
  pass "background and foreground never join a tier"
else
  fail "background and foreground never join a tier" "$(stops)"
fi

# --- a grey theme lights the accent alone ---------------------------------
printf 'accent = "#8d8d8d"\nred = "#a4a4a4"\nblue = "#9b9b9b"\n' >"$theme/colors.toml"
if [[ $(stops) == 8d8d8d && $(stops ambient) == 8d8d8d ]]; then
  pass "a grey theme lights the accent alone"
else
  fail "a grey theme lights the accent alone" "$(stops) / $(stops ambient)"
fi

# --- every device gets the same colours in the one call --------------------
cat >"$theme/colors.toml" <<'TOML'
accent = "#0000ff"
background = "#001000"
foreground = "#ffffff"
yellow = "#ffff00"
blue = "#00ff00"
magenta = "#ff00ff"
TOML
set_config '{"mode": "palette", "colors": 5}'
OPENRGB_LIST_DEVICES='0: ENE DRAM
  Type:           DRAM
  Modes: Direct Static
  LEDs: a b c d e
1: Razer Blackwidow V3
  Type:           Keyboard
  Modes: [Direct] Static
  LEDs: a b c d e ' run_apply
if called 'openrgb -d 0 -m direct -c 0000ff,0000ff,ffff00,ff00ff,00ff00 -d 1 -m direct -c 0000ff,0000ff,ffff00,ff00ff,00ff00'; then
  pass "every device gets the same colours in the one call"
else
  fail "every device gets the same colours in the one call" "$(cat "$calls")"
fi

# --- failed detection broadcasts the colours ------------------------------
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" OPENRGB_LIST_FAIL=1 run_apply
if called 'openrgb -c 0000ff,ffff00,ff00ff,00ff00'; then
  pass "failed detection broadcasts the colours"
else
  fail "failed detection broadcasts the colours" "$(cat "$calls")"
fi

# ==========================================================================
# custom lists, brightness, exact values
# ==========================================================================
cat >"$theme/colors.toml" <<'TOML'
accent = "#0000ff"
background = "#11111b"
red = "#ff0000"
orange = "#ff8000"
yellow = "#ffff00"
green = "#00ff00"
cyan = "#00ffff"
blue = "#0000ff"
magenta = "#ff00ff"
brown = "#8000ff"
foreground = "#cdd6f4"
TOML

# --- variables lists every theme colour the panel may pick ----------------
expected='accent 0000ff
background 11111b
red ff0000
orange ff8000
yellow ffff00
green 00ff00
cyan 00ffff
blue 0000ff
magenta ff00ff
brown 8000ff
foreground cdd6f4'
if [[ $(variables) == "$expected" ]]; then
  pass "variables lists every theme colour the panel may pick"
else
  fail "variables lists every theme colour the panel may pick" "$(variables)"
fi

# --- custom mode lights the listed variables in their order, everywhere ---
set_config '{"mode": "custom", "custom": ["cyan", "magenta", "red"]}'
if [[ $(stops) == 00ffff,ff00ff,ff0000 && $(stops ambient) == 00ffff,ff00ff,ff0000 ]]; then
  pass "custom mode lights the listed variables in their order, everywhere"
else
  fail "custom mode lights the listed variables in their order, everywhere" "$(stops) / $(stops ambient)"
fi

# --- unknown custom variables are skipped, one left means that colour -----
set_config '{"mode": "custom", "custom": ["nope", "green"]}'
if [[ $(stops) == 00ff00 ]]; then
  pass "unknown custom variables are skipped, one left means that colour"
else
  fail "unknown custom variables are skipped, one left means that colour" "$(stops)"
fi

# --- an empty custom list means the accent --------------------------------
set_config '{"mode": "custom", "custom": []}'
if [[ $(stops) == 0000ff ]]; then
  pass "an empty custom list means the accent"
else
  fail "an empty custom list means the accent" "$(stops)"
fi

# --- brightness scales every colour, in the preview and on the wire -------
set_config '{"mode": "custom", "custom": ["cyan", "magenta"], "brightness": 50}'
OPENRGB_LIST_DEVICES='0: Fake Strip
  Modes: Direct Static
  LEDs: '"'"'LED 1'"'"' '"'"'LED 2'"'"'' run_apply
if [[ $(stops) == 008080,800080 ]] && called 'openrgb -d 0 -m direct -c 008080,800080'; then
  pass "brightness scales every colour, in the preview and on the wire"
else
  fail "brightness scales every colour, in the preview and on the wire" "$(stops); $(cat "$calls")"
fi

# --- single mode at low brightness still goes through static --------------
set_config '{"mode": "single", "single": "red", "brightness": 25}'
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if called 'openrgb -d 0 -m static -c 400000 -b 100 -d 1 -m static -c 400000 -b 100'; then
  pass "single mode at low brightness still goes through static"
else
  fail "single mode at low brightness still goes through static" "$(cat "$calls")"
fi

# --- colours are sent exactly as the theme defines them --------------------
# No gamma, no normalising: what colors.toml says is what the LED gets, so
# a dark background is a dark glow, not a computed bright hue.
printf 'accent = "#d84a33"\nbackground = "#11111b"\n' >"$theme/colors.toml"
set_config '{"mode": "palette", "colors": 3}'
if [[ $(stops) == d84a33 ]]; then
  pass "colours are sent exactly as the theme defines them"
else
  fail "colours are sent exactly as the theme defines them" "$(stops)"
fi

# --- bands: LEDs split evenly, remainder goes to the last colours ---------
printf 'red = "#ff0000"\ngreen = "#00ff00"\nblue = "#0000ff"\n' >"$theme/colors.toml"
set_config '{"mode": "custom", "custom": ["red", "green", "blue"]}'
OPENRGB_LIST_DEVICES='0: Fake Strip
  Modes: Direct
  LEDs: a b c d e f g' run_apply
if called 'openrgb -d 0 -m direct -c ff0000,ff0000,ff0000,00ff00,00ff00,0000ff,0000ff'; then
  pass "bands: LEDs split evenly, remainder goes to the last colours"
else
  fail "bands: LEDs split evenly, remainder goes to the last colours" "$(cat "$calls")"
fi

# ==========================================================================
# layout: where each colour goes on a keyboard
# ==========================================================================
set_config '{"mode": "custom", "custom": ["red", "green", "blue"], "layout": "rows"}'

# --- rows: the six key rows split top to bottom ---------------------------
# Space is on the bottom row, Escape the top, A the home row, 1 the number
# row, Z the shift row, Q the qwerty row — nothing like their LED order.
OPENRGB_LIST_DEVICES='4: Razer Blackwidow V3
  Type:           Keyboard
  Modes: [Direct] Static
  Zones: Keyboard
  LEDs: '"'"'Key: Space'"'"' '"'"'Key: Escape'"'"' '"'"'Key: A'"'"' '"'"'Key: 1'"'"' '"'"'Key: Z'"'"' '"'"'Key: Q'"'"' ' run_apply
if called 'openrgb -d 4 -m direct -c 0000ff,ff0000,00ff00,ff0000,0000ff,00ff00'; then
  pass "rows: the six key rows split top to bottom"
else
  fail "rows: the six key rows split top to bottom" "$(cat "$calls")"
fi

# --- columns: keys split left to right by their position ------------------
# Numpad on the far right, Escape far left, Right Shift past the middle, G
# in the left third.
set_config '{"mode": "custom", "custom": ["red", "green", "blue"], "layout": "columns"}'
OPENRGB_LIST_DEVICES='4: Razer Blackwidow V3
  Type:           Keyboard
  LEDs: '"'"'Key: Number Pad .'"'"' '"'"'Key: Escape'"'"' '"'"'Key: Right Shift'"'"' '"'"'Key: G'"'"' ' run_apply
if called 'openrgb -d 4 -m static -c 0000ff,ff0000,00ff00,ff0000'; then
  pass "columns: keys split left to right by their position"
else
  fail "columns: keys split left to right by their position" "$(cat "$calls")"
fi

# --- zones: function keys, main block, modifiers, navigation, numpad, logo -
set_config '{"mode": "custom", "custom": ["red", "green", "blue"], "layout": "zones"}'
OPENRGB_LIST_DEVICES='4: Razer Blackwidow V3
  Type:           Keyboard
  LEDs: '"'"'Key: F1'"'"' '"'"'Key: A'"'"' '"'"'Key: Left Shift'"'"' '"'"'Key: Home'"'"' '"'"'Key: Number Pad 7'"'"' Logo ' run_apply
if called 'openrgb -d 4 -m static -c ff0000,00ff00,0000ff,ff0000,00ff00,0000ff'; then
  pass "zones: function keys, main block, modifiers, navigation, numpad, logo"
else
  fail "zones: function keys, main block, modifiers, navigation, numpad, logo" "$(cat "$calls")"
fi

# --- zones on another device colour its OpenRGB zones in turn -------------
OPENRGB_LIST_DEVICES='3: Razer Basilisk V3
  Type:           Mouse
  Zones: Logo '"'"'Scroll Wheel'"'"' '"'"'LED Strip'"'"'
  LEDs: Logo '"'"'Scroll Wheel'"'"' '"'"'LED Strip LED 1'"'"' '"'"'LED Strip LED 2'"'"' ' run_apply
if called 'openrgb -d 3 -m static -z 0 -c ff0000 -z 1 -c 00ff00 -z 2 -c 0000ff'; then
  pass "zones on another device colour its OpenRGB zones in turn"
else
  fail "zones on another device colour its OpenRGB zones in turn" "$(cat "$calls")"
fi

# --- rows on a strip is just the flow -------------------------------------
set_config '{"mode": "custom", "custom": ["red", "green", "blue"], "layout": "rows"}'
OPENRGB_LIST_DEVICES='0: Fake Strip
  Type:           LEDStrip
  LEDs: a b c d e f ' run_apply
if called 'openrgb -d 0 -m static -c ff0000,ff0000,00ff00,00ff00,0000ff,0000ff'; then
  pass "rows on a strip is just the flow"
else
  fail "rows on a strip is just the flow" "$(cat "$calls")"
fi

# --- empty matrix cells and the quote key keep their LED index ------------
# Index 0 and 2 are blank cells (they take the flow colour for their index),
# Space at 1 is the bottom row, the quote key at 3 the home row, Escape at 4
# the top row.
OPENRGB_LIST_DEVICES='4: Razer Blackwidow V3
  Type:           Keyboard
  LEDs:  '"'"'Key: Space'"'"'  '"'"'Key: '"'"''"'"' '"'"'Key: Escape'"'"' ' run_apply
if called 'openrgb -d 4 -m static -c ff0000,0000ff,00ff00,00ff00,ff0000'; then
  pass "empty matrix cells and the quote key keep their LED index"
else
  fail "empty matrix cells and the quote key keep their LED index" "$(cat "$calls")"
fi

# --- an unknown key name falls back to its flow position ------------------
OPENRGB_LIST_DEVICES='4: Some Keyboard
  Type:           Keyboard
  LEDs: '"'"'Key: Escape'"'"' '"'"'Key: Mystery'"'"' '"'"'Key: Space'"'"' ' run_apply
if called 'openrgb -d 4 -m static -c ff0000,00ff00,0000ff'; then
  pass "an unknown key name falls back to its flow position"
else
  fail "an unknown key name falls back to its flow position" "$(cat "$calls")"
fi

# ==========================================================================
# reporting
# ==========================================================================
set_config '{"mode": "custom", "custom": ["red", "green", "blue"]}'

# --- a failing openrgb call is reported, not swallowed ---------------------
log_file="$home/.local/state/omarchy/theme-rgb/last-apply.log"
if OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" OPENRGB_APPLY_FAIL=1 run_apply; then
  fail "a failing openrgb call is reported, not swallowed" "exit 0"
elif grep -q 'device went away' "$log_file" 2>/dev/null; then
  pass "a failing openrgb call is reported, not swallowed"
else
  fail "a failing openrgb call is reported, not swallowed" "$(cat "$log_file" 2>&1)"
fi

# --- every apply records the devices it found, desk peripherals first ------
devices_file="$home/.local/state/omarchy/theme-rgb/devices"
OPENRGB_LIST_DEVICES='0: ENE DRAM
  Type:           DRAM
  Modes: Direct Static
  LEDs: a b c d
1: ASUS TUF GAMING B760M-PLUS
  Type:           Motherboard
  Modes: [Direct] Static
  LEDs: '"'"'Aura Mainboard, LED 1'"'"'
2: Razer Basilisk V3
  Type:           Mouse
  Modes: [Direct] Off Static
  LEDs: Logo '"'"'Scroll Wheel'"'"'
3: LG 27GN950-B Monitor
  Type:           Monitor
  Modes: [Direct] Static
  LEDs: a b
4: Razer Blackwidow V3
  Type:           Keyboard
  Modes: [Direct] Static
  LEDs: '"'"'Key: Escape'"'"' '"'"'Key: F1'"'"' '"'"'Key: F2'"'"'
5: Mystery Thing
  Modes: Direct
  LEDs: a' run_apply
expected='4|Razer Blackwidow V3|3|Keyboard
2|Razer Basilisk V3|2|Mouse
3|LG 27GN950-B Monitor|2|Monitor
1|ASUS TUF GAMING B760M-PLUS|1|Motherboard
0|ENE DRAM|4|DRAM
5|Mystery Thing|1|'
if [[ -f $devices_file && $(cat "$devices_file") == "$expected" ]]; then
  pass "every apply records the devices it found, desk peripherals first"
else
  fail "every apply records the devices it found, desk peripherals first" "$(cat "$devices_file" 2>&1)"
fi

# --- failed detection leaves the device list empty ------------------------
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" OPENRGB_LIST_FAIL=1 run_apply || true
if [[ -f $devices_file && ! -s $devices_file ]]; then
  pass "failed detection leaves the device list empty"
else
  fail "failed detection leaves the device list empty" "$(cat "$devices_file" 2>&1)"
fi

echo
if (( failures > 0 )); then
  echo "$failures failing"
  exit 1
fi
echo "all passing"
