#!/bin/bash
# Exercises bin/omarchy-theme-rgb-apply against a mock openrgb that records the
# arguments it was called with, inside a throwaway HOME.

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
fi
SH
chmod +x "$mock_bin/openrgb"

failures=0
pass() { echo "ok - $1"; }
fail() {
  echo "not ok - $1"
  [[ -n ${2:-} ]] && printf '  %s\n' "$2"
  failures=$((failures + 1))
}

# run_apply [extra PATH prefix]: runs the script with the mock on PATH.
run_apply() {
  : >"$calls"
  HOME="$home" CALL_LOG="$calls" \
    OPENRGB_LIST_DEVICES="${OPENRGB_LIST_DEVICES:-}" OPENRGB_LIST_FAIL="${OPENRGB_LIST_FAIL:-0}" \
    PATH="${1:-}${1:+:}$mock_bin:$PATH" "$APPLY"
}

called() { grep -Fqx "$1" "$calls"; }
set_config() { mkdir -p "$home/.config/omarchy"; printf '%s\n' "$1" >"$home/.config/omarchy/theme-rgb.json"; }
stops() { HOME="$home" PATH="$mock_bin:$PATH" "$APPLY" stops; }
call_count() { grep -c '^openrgb' "$calls" || true; }

PLAIN_DEVICES='0: Logitech G512 RGB
  Modes: [Direct] Static Off Cycle Breathing
1: Razer Basilisk V3
  Modes: [Direct] Off Static '"'"'Spectrum Cycle'"'"' Wave'

set_config '{"mode": "single"}'

# --- static accent reaches every detected device --------------------------
printf '#7aa2f7\n' >"$theme/keyboard.rgb"
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
# Without an OpenRGB server every CLI call re-probes the hardware (seconds
# each), so all devices go out in one invocation after the one detection.
if (( $(call_count) == 2 )) \
  && called 'openrgb -d 0 -m static -c 7aa2f7 -b 100 -d 1 -m static -c 7aa2f7 -b 100'; then
  pass "static accent reaches every detected device in one call"
else
  fail "static accent reaches every detected device in one call" "$(cat "$calls")"
fi

# --- gradient-capable devices prefer their gradient mode ------------------
OPENRGB_LIST_DEVICES='0: Fake Board
  Modes: Direct Static Gradient Wave
1: Other Pad
  Modes: [Direct] Off Static '"'"'Rainbow Gradient'"'"'' run_apply
if called 'openrgb -d 0 -m Gradient -c 7aa2f7 -b 100 -d 1 -m Rainbow Gradient -c 7aa2f7 -b 100'; then
  pass "gradient-capable devices prefer their gradient mode"
else
  fail "gradient-capable devices prefer their gradient mode" "$(cat "$calls")"
fi

# --- failed detection falls back to a static broadcast --------------------
if OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" OPENRGB_LIST_FAIL=1 run_apply \
  && called 'openrgb -m static -c 7aa2f7 -b 100'; then
  pass "failed detection falls back to a static broadcast"
else
  fail "failed detection falls back to a static broadcast" "$(cat "$calls")"
fi

# --- missing keyboard.rgb falls back to the colors.toml accent -------------
rm "$theme/keyboard.rgb"
printf 'mode = "dark"\n\naccent = "#cba6f7"\nselection = "#313244"\n' >"$theme/colors.toml"
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if called 'openrgb -d 0 -m static -c cba6f7 -b 100 -d 1 -m static -c cba6f7 -b 100'; then
  pass "missing keyboard.rgb falls back to the colors.toml accent"
else
  fail "missing keyboard.rgb falls back to the colors.toml accent" "$(cat "$calls")"
fi

# --- keyboard.rgb wins over the accent when both exist --------------------
printf '#7aa2f7\n' >"$theme/keyboard.rgb"
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if called 'openrgb -d 0 -m static -c 7aa2f7 -b 100 -d 1 -m static -c 7aa2f7 -b 100'; then
  pass "keyboard.rgb wins over the accent when both exist"
else
  fail "keyboard.rgb wins over the accent when both exist" "$(cat "$calls")"
fi

# --- no colour source at all makes no OpenRGB calls -----------------------
rm "$theme/keyboard.rgb" "$theme/colors.toml"
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if [[ ! -s $calls ]]; then
  pass "no colour source at all makes no OpenRGB calls"
else
  fail "no colour source at all makes no OpenRGB calls" "$(cat "$calls")"
fi

# --- an invalid keyboard.rgb is skipped in favour of the accent -----------
printf 'not-a-color\n' >"$theme/keyboard.rgb"
printf 'accent = "#cba6f7"\n' >"$theme/colors.toml"
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if called 'openrgb -d 0 -m static -c cba6f7 -b 100 -d 1 -m static -c cba6f7 -b 100'; then
  pass "an invalid keyboard.rgb is skipped in favour of the accent"
else
  fail "an invalid keyboard.rgb is skipped in favour of the accent" "$(cat "$calls")"
fi

# --- an invalid colour everywhere makes no OpenRGB calls ------------------
printf 'accent = "purple"\n' >"$theme/colors.toml"
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if [[ ! -s $calls ]]; then
  pass "an invalid colour everywhere makes no OpenRGB calls"
else
  fail "an invalid colour everywhere makes no OpenRGB calls" "$(cat "$calls")"
fi
rm "$theme/keyboard.rgb"
printf '#7aa2f7\n' >"$theme/keyboard.rgb"

# --- a missing openrgb binary is a silent no-op ---------------------------
no_openrgb="$tmp/no-openrgb"
mkdir -p "$no_openrgb"
: >"$calls"
if HOME="$home" CALL_LOG="$calls" PATH="$no_openrgb" /bin/bash "$APPLY" && [[ ! -s $calls ]]; then
  pass "a missing openrgb binary is a silent no-op"
else
  fail "a missing openrgb binary is a silent no-op" "$(cat "$calls")"
fi

# --- stops prints the single colour without touching openrgb --------------
: >"$calls"
if [[ $(stops) == 7aa2f7 && ! -s $calls ]]; then
  pass "stops prints the single colour without touching openrgb"
else
  fail "stops prints the single colour without touching openrgb" "$(stops; cat "$calls")"
fi

# ==========================================================================
# palette mode: theme colours nearest in hue to the accent, never a rainbow
# ==========================================================================
# Synthetic palette with easy hues: accent blue (240°); brown 270°, cyan 180°
# and magenta 300° are the neighbours; red/green (120° away) come next; the
# blue key duplicates the accent and yellow is opposite.
rm -f "$theme/keyboard.rgb"
cat >"$theme/colors.toml" <<'TOML'
accent = "#0000ff"
red = "#ff0000"
orange = "#ff8000"
yellow = "#ffff00"
green = "#00ff00"
cyan = "#00ffff"
blue = "#0000ff"
magenta = "#ff00ff"
brown = "#8000ff"
bright_red = "#ff0000"
TOML

# --- 3 colours: ordered by hue so the gradient flows through the accent ---
set_config '{"mode": "palette", "colors": 3}'
if [[ $(stops | paste -sd,) == 00ffff,0000ff,8000ff ]]; then
  pass "3 colours: ordered by hue so the gradient flows through the accent"
else
  fail "3 colours: ordered by hue so the gradient flows through the accent" "$(stops | paste -sd,)"
fi

# --- 5 colours: only hues within 90 degrees join, so four here -------------
set_config '{"mode": "palette", "colors": 5}'
if [[ $(stops | paste -sd,) == 00ffff,0000ff,8000ff,ff00ff ]]; then
  pass "5 colours: only hues within 90 degrees join, so four here"
else
  fail "5 colours: only hues within 90 degrees join, so four here" "$(stops | paste -sd,)"
fi

# --- missing config defaults to 5 palette colours -------------------------
rm "$home/.config/omarchy/theme-rgb.json"
if [[ $(stops | paste -sd,) == 00ffff,0000ff,8000ff,ff00ff ]]; then
  pass "missing config defaults to 5 palette colours"
else
  fail "missing config defaults to 5 palette colours" "$(stops | paste -sd,)"
fi
# --- several colours fill each device's LEDs in clean bands ---------------
# --- palette colours are interpolated across each device's LEDs ----------
set_config '{"mode": "custom", "custom": ["accent", "brown"]}'
OPENRGB_LIST_DEVICES='0: Fake Strip
  Modes: Direct Static
  LEDs: '"'"'LED 1'"'"' '"'"'LED 2'"'"' '"'"'LED 3'"'"'
1: Fake Logo
  Modes: [Direct] Static
  LEDs: Logo' run_apply
if (( $(call_count) == 2 )) && called 'openrgb -d 0 -c 0000ff,0000ff,8000ff -d 1 -c 0000ff'; then
  pass "palette colours fill each device's LEDs in clean bands"
else
  fail "palette colours fill each device's LEDs in clean bands" "$(cat "$calls")"
fi

# --- failed detection broadcasts the palette stops -------------------------
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" OPENRGB_LIST_FAIL=1 run_apply
if called 'openrgb -c 0000ff,8000ff'; then
  pass "failed detection broadcasts the palette stops"
else
  fail "failed detection broadcasts the palette stops" "$(cat "$calls")"
fi

# --- a theme with too few colours falls back to single --------------------
printf 'accent = "#0000ff"\nblue = "#0000ff"\n' >"$theme/colors.toml"
if [[ $(stops | paste -sd,) == 0000ff ]]; then
  pass "a theme with too few colours falls back to single"
else
  fail "a theme with too few colours falls back to single" "$(stops | paste -sd,)"
fi

# --- a grey accent has no hue to follow, so single wins -------------------
printf 'accent = "#cacccc"\nred = "#ff0000"\nblue = "#0000ff"\n' >"$theme/colors.toml"
if [[ $(stops | paste -sd,) == cacccc ]]; then
  pass "a grey accent has no hue to follow, so single wins"
else
  fail "a grey accent has no hue to follow, so single wins" "$(stops | paste -sd,)"
fi

# --- close hues are distinct colours, only identical hex is a duplicate ---
printf 'accent = "#0000ff"\nblue = "#0000ff"\nbrown = "#1010ff"\ncyan = "#00ffff"\n' >"$theme/colors.toml"
set_config '{"mode": "palette", "colors": 3}'
if [[ $(stops | paste -sd,) == 00ffff,0000ff,1010ff ]]; then
  pass "close hues are distinct colours, only identical hex is a duplicate"
else
  fail "close hues are distinct colours, only identical hex is a duplicate" "$(stops | paste -sd,)"
fi

# ==========================================================================
# choosing variables, custom lists and brightness
# ==========================================================================
cat >"$theme/colors.toml" <<'TOML'
accent = "#0000ff"
red = "#ff0000"
orange = "#ff8000"
yellow = "#ffff00"
green = "#00ff00"
cyan = "#00ffff"
blue = "#0000ff"
magenta = "#ff00ff"
brown = "#8000ff"
foreground = "#cdd6f4"
background = "#11111b"
TOML
rm -f "$theme/keyboard.rgb"

# --- variables lists every theme colour the panel may pick ----------------
expected='accent 0000ff
red ff0000
orange ff8000
yellow ffff00
green 00ff00
cyan 00ffff
blue 0000ff
magenta ff00ff
brown 8000ff
foreground cdd6f4'
if [[ $(HOME="$home" "$APPLY" variables) == "$expected" ]]; then
  pass "variables lists every theme colour the panel may pick"
else
  fail "variables lists every theme colour the panel may pick" "$(HOME="$home" "$APPLY" variables)"
fi

# --- single mode lights the chosen variable --------------------------------
set_config '{"mode": "single", "single": "magenta"}'
if [[ $(stops) == ff00ff ]]; then
  pass "single mode lights the chosen variable"
else
  fail "single mode lights the chosen variable" "$(stops)"
fi

# --- a chosen variable beats keyboard.rgb ---------------------------------
printf '#7aa2f7\n' >"$theme/keyboard.rgb"
if [[ $(stops) == ff00ff ]]; then
  pass "a chosen variable beats keyboard.rgb"
else
  fail "a chosen variable beats keyboard.rgb" "$(stops)"
fi
rm "$theme/keyboard.rgb"

# --- palette tiers revolve around the chosen anchor -----------------------
set_config '{"mode": "palette", "colors": 3, "anchor": "red"}'
if [[ $(stops | paste -sd,) == ff0000,ff8000,ffff00 ]]; then
  pass "palette tiers revolve around the chosen anchor"
else
  fail "palette tiers revolve around the chosen anchor" "$(stops | paste -sd,)"
fi

# --- custom mode lights the listed variables in their order ---------------
set_config '{"mode": "custom", "custom": ["cyan", "magenta", "foreground"]}'
if [[ $(stops | paste -sd,) == 00ffff,ff00ff,cdd6f4 ]]; then
  pass "custom mode lights the listed variables in their order"
else
  fail "custom mode lights the listed variables in their order" "$(stops | paste -sd,)"
fi

# --- unknown custom variables are skipped, one left means single ----------
set_config '{"mode": "custom", "custom": ["nope", "green"]}'
if [[ $(stops | paste -sd,) == 00ff00 ]]; then
  pass "unknown custom variables are skipped, one left means single"
else
  fail "unknown custom variables are skipped, one left means single" "$(stops | paste -sd,)"
fi

# --- brightness scales every colour, in the preview and on the wire -------
set_config '{"mode": "custom", "custom": ["cyan", "magenta"], "brightness": 50}'
OPENRGB_LIST_DEVICES='0: Fake Strip
  Modes: Direct Static
  LEDs: '"'"'LED 1'"'"' '"'"'LED 2'"'"'' run_apply
if [[ $(stops | paste -sd,) == 008080,800080 ]] && called 'openrgb -d 0 -c 008080,800080'; then
  pass "brightness scales every colour, in the preview and on the wire"
else
  fail "brightness scales every colour, in the preview and on the wire" "$(stops | paste -sd,); $(cat "$calls")"
fi

# --- single mode at low brightness still goes through static --------------
set_config '{"mode": "single", "single": "red", "brightness": 25}'
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if called 'openrgb -d 0 -m static -c 400000 -b 100 -d 1 -m static -c 400000 -b 100'; then
  pass "single mode at low brightness still goes through static"
else
  fail "single mode at low brightness still goes through static" "$(cat "$calls")"
fi

# --- bands: LEDs split evenly, remainder goes to the last colours ---------
set_config '{"mode": "custom", "custom": ["red", "green", "blue"]}'
OPENRGB_LIST_DEVICES='0: Fake Strip
  Modes: Direct
  LEDs: a b c d e f g' run_apply
if called 'openrgb -d 0 -c ff0000,ff0000,ff0000,00ff00,00ff00,0000ff,0000ff'; then
  pass "bands: LEDs split evenly, remainder goes to the last colours"
else
  fail "bands: LEDs split evenly, remainder goes to the last colours" "$(cat "$calls")"
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
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" OPENRGB_LIST_FAIL=1 run_apply
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
