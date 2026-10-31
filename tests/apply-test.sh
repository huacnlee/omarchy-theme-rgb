#!/bin/bash
# Exercises bin/omarchy-theme-rgb-apply against a mock openrgb that records
# the arguments it was called with, inside a throwaway HOME.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY="$ROOT/bin/omarchy-theme-rgb-apply"

test_tmp_root="${TMPDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-theme-rgb-tests}"
mkdir -p "$test_tmp_root"
tmp=$(mktemp -d "$test_tmp_root/theme-rgb-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

mock_bin="$tmp/bin"
home="$tmp/home"
theme="$home/.local/state/omarchy/current/theme"
calls="$tmp/calls"
mkdir -p "$mock_bin" "$theme"

cat >"$mock_bin/openrgb" <<'SH'
#!/bin/bash
printf 'openrgb %s\n' "$*" >>"$CALL_LOG"
if [[ $* == *"--list-devices"* && ${OPENRGB_SIMPLE_LIST:-0} == 1 ]]; then
  printf '0: Test Keyboard\n'
  exit 0
fi
if [[ $* == *"--list-devices"* || $* == *"--list-detailed"* ]]; then
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
    OPENRGB_SIMPLE_LIST="${OPENRGB_SIMPLE_LIST:-0}" OPENRGB_LIST_DEVICES="${OPENRGB_LIST_DEVICES:-}" OPENRGB_LIST_FAIL="${OPENRGB_LIST_FAIL:-0}" OPENRGB_APPLY_FAIL="${OPENRGB_APPLY_FAIL:-0}" \
    PATH="$mock_bin:$PATH" "$APPLY" "$@"
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

# Both already in Static, so a single-colour apply checks out first time.
PLAIN_DEVICES='0: Logitech G512 RGB
  Type:           Keyboard
  Modes: Direct [Static] Off Cycle Breathing
1: Razer Basilisk V3
  Type:           Mouse
  Modes: Direct Off [Static] '"'"'Spectrum Cycle'"'"' Wave'

# ==========================================================================
# single colour
# ==========================================================================
set_config '{"mode": "single"}'

# --- single mode is the accent on every device, in one static call --------
# Three calls: detection, the apply, and the listing that checks it took.
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if (( $(call_count) == 3 )) \
  && called 'openrgb -d 0 -m static -c 0000ff -b 100 -d 1 -m static -c 0000ff -b 100'; then
  pass "single mode is the accent on every device, in one static call"
else
  fail "single mode is the accent on every device, in one static call" "$(cat "$calls")"
fi

# --- direct-only cooler does not invalidate the shared ambient sync ------
OPENRGB_LIST_DEVICES='0: NZXT RGB Controller
  Type:           LED Strip
  Modes: Direct [Static] Fading
1: Corsair Commander Core
  Type:           Cooler
  Modes: [Direct]
2: ASUS PRIME X670-P WIFI
  Type:           Motherboard
  Modes: Direct Off [Static]' run_apply
if called 'openrgb -d 0 -m static -c 0000ff -b 100 -d 1 -m direct -c 0000ff -b 100 -d 2 -m static -c 0000ff -b 100'; then
  pass "direct-only cooler uses a supported mode alongside other devices"
else
  fail "direct-only cooler uses a supported mode alongside other devices" "$(cat "$calls")"
fi

# --- opt-in case lighting follows the palette, including Direct-only AIO --
set_config '{"mode":"palette","colors":3,"all_devices":true}'
OPENRGB_LIST_DEVICES='0: GPU
  Type:           GPU
  Modes: [Direct] Static
  LEDs: a b c d
1: Corsair Commander Core
  Type:           Cooler
  Modes: [Direct]
  LEDs: a b c
2: NZXT RGB Controller
  Type:           LED Strip
  Modes: [Direct] Static
  LEDs: a b c d e f' run_apply
if [[ $(stops ambient) == 0000ff,ff0000,ff8000 ]] \
  && called 'openrgb -d 0 -m direct -c 0000ff,0000ff,ff0000,ff8000 -d 1 -m direct -c 0000ff,ff0000,ff8000 -d 2 -m direct -c 0000ff,0000ff,ff0000,ff0000,ff8000,ff8000'; then
  pass "all-devices palette reaches GPU, Direct-only cooler, and case fans"
else
  fail "all-devices palette reaches GPU, Direct-only cooler, and case fans" "$(cat "$calls")"
fi
set_config '{"mode":"single"}'

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
# Pure hues at equal vividness and no wallpaper in this HOME: the accent
# first, then the variables in their own order. Every device gets the list.

# --- 3 colours: accent, then the theme's colours; ambient gets the accent --
set_config '{"mode": "palette", "colors": 3}'
if [[ $(stops) == 0000ff,ff0000,ff8000 && $(stops ambient) == 0000ff ]]; then
  pass "3 colours: accent, then the theme's colours"
else
  fail "3 colours: accent, then the theme's colours" "$(stops) / $(stops ambient)"
fi

# --- 5 and 8 colours carry on, on every device ----------------------------
set_config '{"mode": "palette", "colors": 5}'
five=$(stops)
set_config '{"mode": "palette", "colors": 8}'
if [[ $five == 0000ff,ff0000,ff8000,ffff00,00ff00 && $(stops) == 0000ff,ff0000,ff8000,ffff00,00ff00,00ffff,0080ff,ff00ff ]]; then
  pass "5 and 8 colours carry on"
else
  fail "5 and 8 colours carry on" "$five / $(stops)"
fi

# --- missing config means 8 colours ---------------------------------------
rm "$home/.config/omarchy/theme-rgb.json"
if [[ $(stops) == 0000ff,ff0000,ff8000,ffff00,00ff00,00ffff,0080ff,ff00ff ]]; then
  pass "missing config means 8 colours"
else
  fail "missing config means 8 colours" "$(stops)"
fi

# Default placement must agree with explicit Omarchy, not only its palette.
OPENRGB_LIST_DEVICES="4: Test Keyboard
  Type: Keyboard
  LEDs: 'Key: Left Windows' 'Key: Left Control' 'Key: 1' 'Key: A' 'Key: B' 'Key: C' 'Key: D' 'Key: E'" run_apply
default_calls=$(cat "$calls")
set_config '{"layout":"omarchy"}'
OPENRGB_LIST_DEVICES="4: Test Keyboard
  Type: Keyboard
  LEDs: 'Key: Left Windows' 'Key: Left Control' 'Key: 1' 'Key: A' 'Key: B' 'Key: C' 'Key: D' 'Key: E'" run_apply
if [[ $(cat "$calls") == "$default_calls" ]]; then
  pass "missing config defaults to Omarchy layout"
else
  fail "missing config defaults to Omarchy layout" "$(cat "$calls")"
fi

# --- ANSI-only themes still provide a palette -----------------------------
# Many Omarchy themes expose terminal colours as color0..color15 rather than
# semantic red/green/etc variables. The accent remains first; ANSI colours
# fill the rest of the requested palette.
cat >"$theme/colors.toml" <<'TOML'
accent = "#ff8000"
background = "#101010"
foreground = "#f0f0f0"
color0 = "#101010"
color1 = "#ff0000"
color2 = "#00ff00"
color3 = "#ffff00"
color4 = "#0000ff"
color5 = "#ff00ff"
color6 = "#00ffff"
color7 = "#f0f0f0"
color8 = "#303030"
color9 = "#ff4040"
color10 = "#40ff40"
color11 = "#ffff40"
color12 = "#4040ff"
color13 = "#ff40ff"
color14 = "#40ffff"
color15 = "#ffffff"
TOML
set_config '{"mode": "palette", "colors": 5}'
ansi_variables='accent ff8000
background 101010
foreground f0f0f0'
if [[ $(stops) == ff8000,ff0000,00ff00,ffff00,0000ff && $(variables) == "$ansi_variables" ]]; then
  pass "ANSI-only themes still provide a palette"
else
  fail "ANSI-only themes still provide a palette" "$(stops) / $(variables)"
fi

# --- with no wallpaper colour, the vivid come before the muted -------------
# blue is full-strength, red dark but saturated, magenta pale: blue, red, magenta.
printf 'accent = "#00ff00"\nred = "#602020"\nmagenta = "#c090c0"\nblue = "#0080ff"\n' >"$theme/colors.toml"
set_config '{"mode": "palette", "colors": 5}'
if [[ $(stops) == 00ff00,0080ff,602020,c090c0,dfdf20 ]]; then
  pass "with no wallpaper colour, the vivid come before the muted"
else
  fail "with no wallpaper colour, the vivid come before the muted" "$(stops)"
fi

# --- the wallpaper's colours come first ------------------------------------
# A mock magick reports a wallpaper that is mostly red with some blue.
mkdir -p "$home/.local/state/omarchy/current" "$home/wall"
printf 'not really an image\n' >"$home/wall/bg.png"
ln -sfn "$home/wall/bg.png" "$home/.local/state/omarchy/current/background"
cat >"$mock_bin/magick" <<'SH'
#!/bin/bash
printf '   7000: (200,30,30) #C81E1E srgb(200,30,30)\n   2000: (30,30,200) #1E1EC8 srgb(30,30,200)\n   1000: (20,20,20) #141414 srgb(20,20,20)\n'
SH
chmod +x "$mock_bin/magick"
printf 'accent = "#00ff00"\nblue = "#0080ff"\nyellow = "#ffff00"\nred = "#ff4040"\n' >"$theme/colors.toml"
if [[ $(stops) == 00ff00,ff4040,0080ff,ffff00,af20df ]]; then
  pass "the wallpaper's colours come first"
else
  fail "the wallpaper's colours come first" "$(stops)"
fi
rm "$mock_bin/magick" "$home/.local/state/omarchy/current/background"

# --- greys and dark tones are left out ------------------------------------
printf 'accent = "#0000ff"\nred = "#ff0000"\ncyan = "#808080"\ngreen = "#002200"\nyellow = "#ffff00"\n' >"$theme/colors.toml"
set_config '{"mode": "palette", "colors": 5}'
if [[ $(stops) == 0000ff,ff0000,ffff00,20df80,df20df ]]; then
  pass "greys and dark tones are left out"
else
  fail "greys and dark tones are left out" "$(stops)"
fi

# --- near-duplicates collapse to one -------------------------------------
# blue and green sit on the accent; yellow sits on orange: three bands, not six.
printf 'accent = "#0000ff"\nblue = "#0010ff"\ngreen = "#1000ff"\nyellow = "#ffff00"\norange = "#fff000"\nred = "#ff0000"\n' >"$theme/colors.toml"
set_config '{"mode": "palette", "colors": 8}'
if [[ $(stops) == 0000ff,ff0000,fff000,20df80,df20df,50df20,20afdf,8020df ]]; then
  pass "near-duplicates collapse to one"
else
  fail "near-duplicates collapse to one" "$(stops)"
fi

# --- background and foreground never join a tier -------------------------
printf 'accent = "#0000ff"\nbackground = "#00ff00"\nforeground = "#ff0000"\nyellow = "#ffff00"\n' >"$theme/colors.toml"
set_config '{"mode": "palette", "colors": 5}'
if [[ $(stops) == 0000ff,ffff00,df2080,20df80,df5020 ]]; then
  pass "background and foreground never join a tier"
else
  fail "background and foreground never join a tier" "$(stops)"
fi

# --- a grey theme keeps its accent and gains derived colours ---------------------------------
printf 'accent = "#8d8d8d"\nred = "#a4a4a4"\nblue = "#9b9b9b"\n' >"$theme/colors.toml"
if [[ $(stops) == 8d8d8d,5ac0c0,8d5ac0,8dc05a,5a73c0 ]]; then
  pass "a grey theme keeps its accent and gains derived colours"
else
  fail "a grey theme keeps its accent and gains derived colours" "$(stops) / $(stops ambient)"
fi

# --- the desk gets the bands, everything else the accent, in one call -----
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
if called 'openrgb -d 0 -m static -c 0000ff -b 100 -d 1 -m direct -c 0000ff,ffff00,00ff00,ff00ff,df2020'; then
  pass "the desk gets the bands, everything else the accent, in one call"
else
  fail "the desk gets the bands, everything else the accent, in one call" "$(cat "$calls")"
fi

# --- failed detection broadcasts the colours ------------------------------
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" OPENRGB_LIST_FAIL=1 run_apply
if called 'openrgb -c 0000ff,ffff00,00ff00,ff00ff,df2020'; then
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
if [[ $(stops) == 00ffff,ff00ff,ff0000 && $(stops ambient) == 00ffff ]]; then
  pass "custom mode lights the listed variables in their order; ambient the first"
else
  fail "custom mode lights the listed variables in their order; ambient the first" "$(stops) / $(stops ambient)"
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
OPENRGB_LIST_DEVICES='0: Fake Pad
  Type:           Mousemat
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
if [[ $(stops) == d84a33,33c1d8,9d33d8 ]]; then
  pass "colours are sent exactly as the theme defines them"
else
  fail "colours are sent exactly as the theme defines them" "$(stops)"
fi

# Generated palettes are deterministic, unique, opaque and scaled only once.
set_config '{"mode":"palette","colors":8}'
full_palette=$(stops)
if [[ $(tr ',' '\n' <<<"$full_palette" | sort -u | wc -l) == 8 && $(stops) == "$full_palette" ]] &&
   [[ $full_palette =~ ^[0-9a-f]{6}(,[0-9a-f]{6}){7}$ ]]; then
  pass "HSLA completion produces eight unique deterministic RGB colours"
else
  fail "HSLA completion produces eight unique deterministic RGB colours" "$full_palette"
fi
set_config '{"mode":"palette","colors":8,"brightness":50}'
expected_scaled=$(node -e 'console.log(process.argv[1].split(",").map(c=>c.match(/../g).map(x=>Math.floor(parseInt(x,16)*.5+.5).toString(16).padStart(2,"0")).join("")).join(","))' "$full_palette")
if [[ $(stops) == "$expected_scaled" ]]; then
  pass "derived colours share the preview brightness scaling"
else
  fail "derived colours share the preview brightness scaling" "$(stops)"
fi
set_config '{"mode":"single"}'
if [[ $(stops) == d84a33 ]]; then
  pass "single colour never synthesizes extra hues"
else
  fail "single colour never synthesizes extra hues" "$(stops)"
fi

# --- bands: LEDs split evenly, remainder goes to the last colours ---------
printf 'red = "#ff0000"\ngreen = "#00ff00"\nblue = "#0000ff"\n' >"$theme/colors.toml"
set_config '{"mode": "custom", "custom": ["red", "green", "blue"]}'
OPENRGB_LIST_DEVICES='0: Fake Pad
  Type:           Mousemat
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
if called 'openrgb -d 4 -m direct -c 00ff00,ff0000,0000ff,ff0000,0000ff,ff0000'; then
  pass "rows: the six key rows split top to bottom"
else
  fail "rows: the six key rows split top to bottom" "$(cat "$calls")"
fi

# The EV63 has no function row, and Delete shares the shift row.
printf 'yellow = "#ffff00"\norange = "#ff8000"\n' >>"$theme/colors.toml"
set_config '{"mode":"custom","custom":["red","green","blue","yellow","orange"],"layout":"rows"}'
OPENRGB_LIST_DEVICES="$(cat <<'DEVICE'
4: IQUNIX EV63
  Type: Keyboard
  Modes: [Direct] Static
  Zones: Keyboard
  LEDs: 'Key: Escape' 'Key: Backspace' 'Key: ]' 'Key: \ (ANSI)' 'Key: '' 'Key: Enter' 'Key: Right Shift' 'Key: Up Arrow' 'Key: Delete' 'Key: Space'
DEVICE
)" run_apply
if called 'openrgb -d 4 -m direct -c ff0000,ff0000,00ff00,00ff00,0000ff,0000ff,ffff00,ffff00,ffff00,ff8000'; then
  pass "rows: EV63 row ends and navigation keys stay on their physical rows"
else
  fail "rows: EV63 row ends and navigation keys stay on their physical rows" "$(cat "$calls")"
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

cp "$theme/colors.toml" "$tmp/layout-colors.bak"
printf 'red = "#ff0000"\ngreen = "#00ff00"\nblue = "#0000ff"\nyellow = "#ffff00"\nmagenta = "#ff00ff"\n' >"$theme/colors.toml"
# Semantic layouts: same deliberately shuffled LED list for every preset.
# Five colours make every accent group independently observable.
while read -r preset expected; do
  set_config "{\"mode\":\"custom\",\"custom\":[\"red\",\"green\",\"blue\",\"yellow\",\"magenta\"],\"layout\":\"$preset\"}"
  OPENRGB_LIST_DEVICES="4: Test Keyboard
  Type: Keyboard
  LEDs: 'Key: W' 'Key: Escape' 'Key: Space' 'Key: F1' 'Key: F5' 'Key: F12' 'Key: Left Control' 'Key: Left Arrow' 'Key: Home' 'Key: C' 'Key: H' 'Key: I' 'Key: B'" run_apply
  if called "openrgb -d 4 -m static -c $expected"; then
    pass "key accents: $preset"
  else
    fail "key accents: $preset" "$(cat "$calls")"
  fi
done <<'CASES'
gaming 1ff91f,590000,f9f91f,f58d24,24f5f5,f91ff9,f9f91f,1ff91f,f91ff9,1f1ff9,8df524,1f1ff9,1f1ff9
outline ff00ff,00ff00,ffff00,00ff00,00ff00,ff00ff,ffff00,0000ff,ff0000,ffff00,ffff00,ff00ff,ffff00
lazyvim ff00ff,ffff00,ffff00,ff0000,ff0000,ff0000,0000ff,0000ff,ff00ff,0000ff,00ff00,0000ff,0000ff
omarchy ff0000,ff00ff,0000ff,ff0000,ff0000,ff0000,ff00ff,00ff00,ff0000,ffff00,ffff00,ffff00,ffff00
CASES
set_config '{"mode":"custom","custom":["red","green"],"layout":"omarchy"}'
OPENRGB_LIST_DEVICES="4: Test Keyboard
  Type: Keyboard
  LEDs: 'Key: Left Windows' 'Key: Right Windows' 'Key: Left Shift' 'Key: 1' 'Key: Space' 'Key: B'" run_apply
if called 'openrgb -d 4 -m static -c 00ff00,00ff00,ff0000,ff0000,ff0000,ff0000'; then
  pass "Omarchy: Super, modifiers and workspaces accented; Space stays in base"
else
  fail "Omarchy: Super, modifiers and workspaces accented; Space stays in base" "$(cat "$calls")"
fi

# Each layout must use every palette colour on the full keyboard reference.
# No hardware discovery or writes are allowed for the reference probe.
for preset in flow rows columns zones gaming outline lazyvim omarchy; do
  for amount in 1 3 5 8; do
    if [[ $amount == 1 ]]; then
      set_config "{\"mode\":\"single\",\"layout\":\"$preset\"}"
    else
      set_config "{\"mode\":\"palette\",\"colors\":$amount,\"layout\":\"$preset\"}"
    fi
    rm -f "$home/.local/state/omarchy/theme-rgb/keyboard-leds"
    : >"$calls"
    reference=$(HOME="$home" CALL_LOG="$calls" PATH="$mock_bin:$PATH" "$APPLY" preview)
    actual=$(cut -f3 <<<"$reference" | sort -u | paste -sd,)
    expected=$(stops layout | tr ',' '\n' | sort -u | paste -sd,)
    expected_amount=$amount
    if [[ $preset == gaming && $amount != 1 ]]; then expected_amount=8; fi
    if [[ $actual == "$expected" && $(cut -f3 <<<"$reference" | sort -u | wc -l) == "$expected_amount" && ! -s $calls ]]; then
      pass "$preset uses all $amount colours in the hardware-free reference"
    else
      fail "$preset uses all $amount colours in the hardware-free reference" "$actual / $expected"
    fi
    # Verify the actual OpenRGB argument list too, with discovery in a
    # different LED order and without ANSI quote-key token ambiguity.
    fixture=$(awk -F '\t' '$4 != sprintf("%c",39) {print $4}' <<<"$reference" | tac | awk '{printf "%cKey: %s%c ",39,$0,39}')
    OPENRGB_LIST_DEVICES="4: Test Keyboard
  Type: Keyboard
  LEDs: $fixture" run_apply
    hardware_colours=$(awk '{for(i=1;i<=NF;i++) if($i=="-c") {print $(i+1); exit}}' "$calls" | tr ',' '\n' | sort -u | paste -sd,)
    if [[ $hardware_colours == "$expected" ]]; then
      pass "$preset sends all $amount colours to OpenRGB in reversed LED order"
    else
      fail "$preset sends all $amount colours to OpenRGB in reversed LED order" "$hardware_colours / $expected"
    fi
  done
done
# Real compact keyboard discovery drives the preview; absent keys never
# appear or consume a row. Both compact sizes must still use the full palette.
rm -f "$home/.local/state/omarchy/theme-rgb/keyboard-leds"
set_config '{"mode":"palette","colors":8,"layout":"omarchy"}'
full_reference=$(HOME="$home" PATH="$mock_bin:$PATH" "$APPLY" preview)
for shape in compact60 compact75; do
  compact_names=$(awk -F '\t' -v shape="$shape" '$2 < (shape == "compact60" ? 15 : 18) && $4 != sprintf("%c",39) && (shape != "compact60" || $4 !~ /^F[0-9]+$/) {print $4}' <<<"$full_reference")
  fixture=$(awk '{printf "%cKey: %s%c ",39,$0,39}' <<<"$compact_names")
  for preset in flow rows columns zones gaming outline lazyvim omarchy; do
    set_config "{\"mode\":\"palette\",\"colors\":8,\"layout\":\"$preset\"}"
    OPENRGB_LIST_DEVICES="4: Test $shape
  Type: Keyboard
  LEDs: $fixture" run_apply
    detected=$(HOME="$home" PATH="$mock_bin:$PATH" "$APPLY" preview)
    actual=$(cut -f3 <<<"$detected" | sort -u | paste -sd,)
    expected=$(stops layout | tr ',' '\n' | sort -u | paste -sd,)
    expected_keys=$(sort <<<"$compact_names")
    actual_keys=$(cut -f4 <<<"$detected" | sort)
    if [[ $actual == "$expected" && $actual_keys == "$expected_keys" ]] &&
       [[ $(cut -f6 <<<"$detected" | sort -u) == detected ]]; then
      pass "$shape $preset: all eight colours, only detected keys"
    else
      fail "$shape $preset: all eight colours, only detected keys" "$actual / $expected"
    fi
    if [[ $preset == omarchy ]]; then
      super=$(awk -F '\t' '$4=="Left Windows" {print $3}' <<<"$detected")
      if [[ -n $super ]] && awk -F '\t' -v colour="$super" '$3==colour && $4!="Left Windows" && $4!="Right Windows" {bad=1} END {exit bad}' <<<"$detected"; then
        pass "$shape: Super colour is exclusive to Super keys"
      else
        fail "$shape: Super colour is exclusive to Super keys" "$super"
      fi
    fi
  done
done
# A blue Super next to teal modifiers is intentionally hard to distinguish.
# The optimizer must improve that boundary using the existing palette.
cp "$theme/colors.toml" "$tmp/contrast-colors.bak"
printf 'accent = "#5da602"\nblue = "#417ab3"\ncyan = "#41b3a9"\nyellow = "#eebb6e"\nmagenta = "#882252"\n' >"$theme/colors.toml"
set_config '{"mode":"custom","custom":["accent","blue","cyan","yellow","magenta"],"layout":"omarchy"}'
OPENRGB_LIST_DEVICES="4: Contrast Keyboard
  Type: Keyboard
  LEDs: $fixture" run_apply
contrast_reference=$(HOME="$home" PATH="$mock_bin:$PATH" "$APPLY" preview)
super_colour=$(awk -F '\t' '$4=="Left Windows" {print $3}' <<<"$contrast_reference")
ctrl_colour=$(awk -F '\t' '$4=="Left Control" {print $3}' <<<"$contrast_reference")
alt_colour=$(awk -F '\t' '$4=="Left Alt" {print $3}' <<<"$contrast_reference")
if node -e 'function d(a,b){return [0,2,4].reduce((s,i)=>s+(parseInt(a.slice(i,i+2),16)-parseInt(b.slice(i,i+2),16))**2,0)} const [s,c,a]=process.argv.slice(1); process.exit(s&&c&&a&&Math.min(d(s,c),d(s,a))>2*d("417ab3","41b3a9")?0:1)' "$super_colour" "$ctrl_colour" "$alt_colour"; then
  pass "Omarchy increases Super separation from both adjacent modifiers"
else
  fail "Omarchy increases Super separation from both adjacent modifiers" "$super_colour / $ctrl_colour / $alt_colour"
fi
mv "$tmp/contrast-colors.bak" "$theme/colors.toml"
# Exact user-defined Omarchy semantic groups, including the quote and
# backslash keys, must survive adaptive placement and palette permutation.
set_config '{"mode":"palette","colors":8,"layout":"omarchy"}'
OPENRGB_LIST_DEVICES="4: Group Keyboard
  Type: Keyboard
  LEDs: 'Key: A' 'Key: Left Windows' 'Key: Right Windows' 'Key: Left Control' 'Key: 1' 'Key: [' 'Key: ]' 'Key: ;' 'Key: '' 'Key: .' 'Key: /' 'Key: \ (ANSI)' 'Key: -' 'Key: =' 'Key: Escape' 'Key: Fn' 'Key: Right Fn' 'Key: Delete' 'Key: Backspace' 'Key: Enter' 'Key: Space'" run_apply
groups=$(HOME="$home" PATH="$mock_bin:$PATH" "$APPLY" preview)
if awk -F '\t' '
  $4=="[" || $4=="]" || $4==";" || $4==sprintf("%c",39) || $4=="." || $4=="/" || substr($4,1,1)==sprintf("%c",92) || $4=="-" || $4=="=" {if($5!=4)bad=1;punct++}
  $4=="Escape" || $4=="Fn" || $4=="Right Fn" {if($5!=5)bad=1;fn++}
  $4=="Delete" || $4=="Backspace" {if($5!=6)bad=1;del++}
  $4=="Enter" || $4=="Space" {if($5!=7)bad=1;action++}
  {if(($5 in colours) && colours[$5]!=$3)bad=1;colours[$5]=$3}
  END {exit bad || punct!=9 || fn!=3 || del!=2 || action!=2}
' <<<"$groups"; then
  pass "Omarchy: punctuation, Escape/Fn, Delete/Backspace, Enter/Space pairs"
else
  fail "Omarchy: punctuation, Escape/Fn, Delete/Backspace, Enter/Space pairs" "$groups"
fi

# A theme with only three real hues must keep the large majority of the
# keyboard native while still displaying all eight colours.
cp "$theme/colors.toml" "$tmp/native-colors.bak"
printf 'accent = "#5da602"\nblue = "#417ab3"\nyellow = "#eebb6e"\n' >"$theme/colors.toml"
set_config '{"mode":"palette","colors":8,"layout":"omarchy"}'
OPENRGB_LIST_DEVICES="4: Sparse Theme Keyboard
  Type: Keyboard
  LEDs: $fixture" run_apply
native_reference=$(HOME="$home" PATH="$mock_bin:$PATH" "$APPLY" preview)
if awk -F '\t' '{n++;if($7=="1")native++;seen[$3]=1} END {for(c in seen)colours++;exit !(native/n>=.75 && colours==8)}' <<<"$native_reference"; then
  pass "derived hues stay on small groups: at least 75% native keys with three theme hues"
else
  fail "derived hues stay on small groups: at least 75% native keys with three theme hues" "$native_reference"
fi
mv "$tmp/native-colors.bak" "$theme/colors.toml"

# Gaming skills must stay pairwise distinct and separate from Escape,
# including short automatic/custom palettes and low brightness.
for settings in '"mode":"palette","colors":3' '"mode":"palette","colors":5' '"mode":"palette","colors":8' '"mode":"custom","custom":["red","green"]' '"mode":"palette","colors":3,"brightness":10'; do
  set_config "{$settings,\"layout\":\"gaming\"}"
  OPENRGB_LIST_DEVICES="4: Test Keyboard
  Type: Keyboard
  LEDs: 'Key: Escape' 'Key: 1' 'Key: 2' 'Key: 3' 'Key: 4' 'Key: 5' 'Key: W' 'Key: Space'" run_apply
  skill_colours=$(awk '{for(i=1;i<=NF;i++) if($i=="-c") {print $(i+1); exit}}' "$calls")
  unique=$(tr ',' '\n' <<<"$skill_colours" | head -6 | sort -u | wc -l)
  if [[ $unique == 6 ]]; then
    pass "Gaming: 1–5 and Escape are six distinct colours ($settings)"
  else
    fail "Gaming: 1–5 and Escape are six distinct colours ($settings)" "$skill_colours"
  fi
done
# Cover every named FPS/ARPG group while all eight colours are present,
# so palette completion must not alter the emphasis groups.
set_config '{"mode":"palette","colors":8,"layout":"gaming"}'
IFS=, read -r -a palette <<<"$(stops)"
OPENRGB_LIST_DEVICES="4: Test Keyboard
  Type: Keyboard
  LEDs: 'Key: Escape' 'Key: 1' 'Key: 2' 'Key: 3' 'Key: 4' 'Key: 5' 'Key: W' 'Key: Space' 'Key: I' 'Key: B' 'Key: C' 'Key: Enter' 'Key: Backspace' 'Key: Up Arrow' 'Key: Down Arrow' 'Key: Left Arrow' 'Key: Right Arrow' 'Key: Q' 'Key: E' 'Key: R' 'Key: F' 'Key: T' 'Key: G' 'Key: Tab'" run_apply
actual_groups=$(awk '{for(i=1;i<=NF;i++) if($i=="-c") {print $(i+1); exit}}' "$calls")
IFS=, read -r -a observed <<<"$actual_groups"
# First eight keys anchor eight distinct semantic groups; remaining keys
# must share their intended group, regardless of contrast-driven permutation.
palette=("${observed[0]}" "${observed[6]}" "${observed[7]}" "${observed[1]}" "${observed[2]}" "${observed[3]}" "${observed[4]}" "${observed[5]}")
expected_groups=()
for slot in 0 3 4 5 6 7 1 2 7 7 7 6 6 1 1 1 1 3 4 5 6 7 6 7; do
  expected_groups+=("${palette[slot]}")
done
expected_groups_csv=$(IFS=,; echo "${expected_groups[*]}")
if called "openrgb -d 4 -m static -c $expected_groups_csv"; then
  pass "Gaming: movement, five skills, inventory/character, actions and chat groups"
else
  fail "Gaming: movement, five skills, inventory/character, actions and chat groups" "$(cat "$calls")"
fi
set_config '{"mode":"custom","custom":["red","green"],"layout":"gaming"}'
vivid_palette=$(stops layout)
if node -e 'const c=process.argv[1].split(",");function vivid(hex){const v=hex.match(/../g).map(x=>parseInt(x,16)/255),mx=Math.max(...v),mn=Math.min(...v),l=(mx+mn)/2,s=(mx-mn)/(1-Math.abs(mx+mn-1));return s>=.79&&l>=.475&&l<=.625}process.exit(c[0]==="590000"&&c.slice(1).every(vivid)?0:1)' "$vivid_palette"; then
  pass "Gaming dims the native base and keeps all emphasis colours vivid"
else
  fail "Gaming dims the native base and keeps all emphasis colours vivid" "$vivid_palette"
fi
# The numbered colours stay the theme's: gaming only changes what a device
# set to all colours lays out.
if [[ $(stops) == ff0000,00ff00 ]]; then
  pass "Gaming leaves the numbered colours, and so single-colour devices, alone"
else
  fail "Gaming leaves the numbered colours, and so single-colour devices, alone" "$(stops)"
fi
mv "$tmp/layout-colors.bak" "$theme/colors.toml"

# --- rows on a pad is just the flow ---------------------------------------
set_config '{"mode": "custom", "custom": ["red", "green", "blue"], "layout": "rows"}'
OPENRGB_LIST_DEVICES='0: Fake Pad
  Type:           Mousemat
  LEDs: a b c d e f ' run_apply
if called 'openrgb -d 0 -m static -c ff0000,ff0000,00ff00,00ff00,0000ff,0000ff'; then
  pass "rows on a pad is just the flow"
else
  fail "rows on a pad is just the flow" "$(cat "$calls")"
fi

# --- a strip is ambient: the first colour alone, whatever the tier ---------
OPENRGB_LIST_DEVICES='0: Fake Strip
  Type:           LEDStrip
  Modes: Direct Static
  LEDs: a b c d e f ' run_apply
if called 'openrgb -d 0 -m static -c ff0000 -b 100'; then
  pass "a strip is ambient: the first colour alone, whatever the tier"
else
  fail "a strip is ambient: the first colour alone, whatever the tier" "$(cat "$calls")"
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
if called 'openrgb -d 4 -m static -c ff0000,0000ff,00ff00'; then
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

# --- a device that did not take its mode is sent again on its own ---------
# The mock reports device 1 still in Static after the apply; the script
# checks and re-sends that device alone, then reports success.
cat >"$mock_bin/openrgb" <<'SH'
#!/bin/bash
printf 'openrgb %s\n' "$*" >>"$CALL_LOG"
if [[ $* == *"--list-devices"* && ${OPENRGB_SIMPLE_LIST:-0} == 1 ]]; then
  printf '0: Test Keyboard\n'
  exit 0
fi
if [[ $* == *"--list-devices"* || $* == *"--list-detailed"* ]]; then
  [[ ${OPENRGB_LIST_FAIL:-0} == 1 ]] && exit 1
  n=$(grep -c -- '--list-devices' "$CALL_LOG")
  # the first listing is detection; the second, the check after the apply
  if (( n >= 2 )) && [[ -n ${OPENRGB_AFTER:-} ]]; then printf '%s\n' "$OPENRGB_AFTER"; else printf '%s\n' "$OPENRGB_LIST_DEVICES"; fi
  exit 0
fi
[[ ${OPENRGB_APPLY_FAIL:-0} == 1 ]] && { echo "device went away" >&2; exit 3; }
exit 0
SH
set_config '{"mode": "custom", "custom": ["red", "green", "blue"]}'
KB='0: Razer Blackwidow V3
  Type:           Keyboard
  Modes: [Direct] Static
  LEDs: a b c
1: Razer Basilisk V3
  Type:           Mouse
  Modes: Direct [Static]
  LEDs: a b c'
export OPENRGB_AFTER='0: Razer Blackwidow V3
  Type:           Keyboard
  Modes: [Direct] Static
  LEDs: a b c
1: Razer Basilisk V3
  Type:           Mouse
  Modes: Direct [Static]
  LEDs: a b c'
if OPENRGB_LIST_DEVICES="$KB" run_apply \
  && called 'openrgb -d 0 -m direct -c ff0000,00ff00,0000ff -d 1 -m direct -c ff0000,00ff00,0000ff' \
  && called 'openrgb -d 1 -m direct -c ff0000,00ff00,0000ff' \
  && (( $(grep -c -- '-d 0 -m direct' "$calls") == 1 )); then
  pass "a device that did not take its mode is sent again on its own"
else
  fail "a device that did not take its mode is sent again on its own" "$(cat "$calls")"
fi
unset OPENRGB_AFTER

# --- a device that took its mode is not sent twice ------------------------
OPENRGB_LIST_DEVICES='0: Razer Blackwidow V3
  Type:           Keyboard
  Modes: [Direct] Static
  LEDs: a b c' run_apply
if (( $(grep -c -- '-d 0 -m direct' "$calls") == 1 )) && (( $(call_count) == 3 )); then
  pass "a device that took its mode is not sent twice"
else
  fail "a device that took its mode is not sent twice" "$(cat "$calls")"
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

OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" OPENRGB_SIMPLE_LIST=1 run_apply
if called "openrgb --list-detailed" && grep -q 'Logitech G512 RGB' "$devices_file"; then
  pass "OpenRGB 1.1 uses detailed listing for discovery and verification"
else
  fail "OpenRGB 1.1 detailed listing" "$(cat "$calls")"
fi

# ==========================================================================
# where each colour goes: the "assign" setting
# ==========================================================================

# The palette at this point; colour n is field n.
set_config '{"mode":"palette","colors":3}'
palette=$(stops)
colour() { cut -d, -f"$1" <<<"$palette"; }

# --- a device set to one colour number lights that colour; "off" is skipped -
set_config '{"mode":"palette","colors":3,"assign":{"openrgb:Logitech G512 RGB":2,"openrgb:Razer Basilisk V3":"off"}}'
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if called "openrgb -d 0 -m static -c $(colour 2) -b 100" && ! grep -q -- '-d 1' "$calls"; then
  pass "a device set to colour 2 lights colour 2, and one set to off is left alone"
else
  fail "a device set to colour 2 lights colour 2, and one set to off is left alone" "$(cat "$calls")"
fi

# --- a colour number past the palette wraps around -------------------------
set_config '{"mode":"palette","colors":3,"assign":{"openrgb:Logitech G512 RGB":5,"openrgb:Razer Basilisk V3":"off"}}'
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if called "openrgb -d 0 -m static -c $(colour 2) -b 100"; then
  pass "colour 5 of a three-colour palette is colour 2"
else
  fail "colour 5 of a three-colour palette is colour 2" "$(cat "$calls")"
fi

# --- every device off makes no apply call ----------------------------------
set_config '{"mode":"palette","colors":3,"assign":{"openrgb:Logitech G512 RGB":"off","openrgb:Razer Basilisk V3":"off"}}'
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if (( $(call_count) == 1 )); then
  pass "with every device left alone only the detection runs"
else
  fail "with every device left alone only the detection runs" "$(cat "$calls")"
fi

# --- plan lists what each device gets, Home Assistant lights included ------
plan() { HOME="$home" PATH="$mock_bin:$PATH" "$APPLY" plan; }
hass_lights="$home/.local/state/omarchy/theme-rgb/hass-lights"
mkdir -p "$(dirname "$hass_lights")"
set_config '{"mode":"palette","colors":3,"brightness":50,"assign":{"openrgb:Razer Basilisk V3":3,"hass:light.desk":2}}'
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
dim=$(stops)
printf 'light.desk\tDesk lamp\ton\nlight.shelf\tShelf\toff\n' >"$hass_lights"
expected_plan=$(printf '%s\n' \
  "openrgb"$'\t'"Logitech G512 RGB"$'\t'"Logitech G512 RGB"$'\t'"Keyboard"$'\t'"all"$'\t'"$dim" \
  "openrgb"$'\t'"Razer Basilisk V3"$'\t'"Razer Basilisk V3"$'\t'"Mouse"$'\t'"3"$'\t'"$(cut -d, -f3 <<<"$dim")" \
  "hass"$'\t'"light.desk"$'\t'"Desk lamp"$'\t'"on"$'\t'"2"$'\t'"$(colour 2)" \
  $'hass\tlight.shelf\tShelf\toff\toff\t' end)
if [[ $(plan) == "$expected_plan" ]]; then
  pass "plan names every device's colours; Home Assistant gets them before brightness"
else
  fail "plan names every device's colours; Home Assistant gets them before brightness" "$(plan)"
fi
rm -f "$hass_lights"

# --- Home Assistant lights with a colour are sent it, through the hass script
cat >"$mock_bin/secret-tool" <<'SH'
#!/bin/bash
[[ $* == "lookup service theme-rgb-hass origin https://ha.test:443" ]] && printf 'test-token'
exit 0
SH
cat >"$mock_bin/curl" <<'SH'
#!/bin/bash
config=$(cat)
method=GET url=""
while (( $# )); do
  case $1 in -X) method=$2; shift ;; -m|-K|-w) shift ;; http*) url=$1 ;; esac
  shift
done
data=$(sed -n 's/^data = "\(.*\)"$/\1/p' <<<"$config" | sed 's/\\"/"/g')
printf 'curl %s %s %s\n' "$method" "$url" "$data" >>"$CALL_LOG"
[[ $config == *"Bearer test-token"* ]] || { printf '\n401'; exit 0; }
states='[{"entity_id":"light.desk","state":"on","attributes":{"friendly_name":"Desk lamp","supported_color_modes":["hs","color_temp"]}},{"entity_id":"light.shelf","state":"off","attributes":{"friendly_name":"Shelf","supported_color_modes":["rgb"]}},{"entity_id":"light.hall","state":"on","attributes":{"supported_color_modes":["color_temp"]}}]'
if [[ $method == GET && $url == */api/states ]]; then
  printf '%s\n200' "$states"
elif [[ $method == GET ]]; then
  one=$(jq -c --arg e "${url##*/}" '.[] | select(.entity_id == $e)' <<<"$states")
  if [[ -n $one ]]; then printf '%s\n200' "$one"; else printf '{}\n404'; fi
else
  printf '[]\n200'
fi
SH
chmod +x "$mock_bin/secret-tool" "$mock_bin/curl"
rgb() { printf '%d,%d,%d' "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }
set_config '{"mode":"palette","colors":3,"brightness":50,"home_assistant":{"url":"https://ha.test"},"assign":{"hass:light.desk":2,"hass:light.shelf":1}}'
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if called 'curl GET https://ha.test/api/states/light.desk ' \
  && ! grep -q 'api/states ' "$calls" \
  && called 'curl POST https://ha.test/api/services/light/turn_on {"entity_id":"light.desk","rgb_color":['"$(rgb "$(colour 2)")"']}' \
  && ! grep -q 'light.shelf' <(grep '^curl POST' "$calls"); then
  pass "a lit Home Assistant light gets its colour; one that is off stays off"
else
  fail "a lit Home Assistant light gets its colour; one that is off stays off" "$(cat "$calls")"
fi

# --- "hass" colours only the Home Assistant lights -------------------------
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply hass
if ! grep -q '^openrgb' "$calls" \
  && called 'curl POST https://ha.test/api/services/light/turn_on {"entity_id":"light.desk","rgb_color":['"$(rgb "$(colour 2)")"']}'; then
  pass "hass colours the Home Assistant lights without touching OpenRGB"
else
  fail "hass colours the Home Assistant lights without touching OpenRGB" "$(cat "$calls")"
fi

# --- "openrgb" leaves Home Assistant to the shell; "hass <entity>" one light
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply openrgb
if grep -q '^openrgb' "$calls" && ! grep -q '^curl' "$calls"; then
  pass "openrgb colours the computer without waiting on Home Assistant"
else
  fail "openrgb colours the computer without waiting on Home Assistant" "$(cat "$calls")"
fi
set_config '{"mode":"palette","colors":3,"home_assistant":{"url":"https://ha.test"},"assign":{"hass:light.desk":2,"hass:light.shelf":1}}'
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply hass light.shelf
if ! grep -q 'light.desk' "$calls" && called 'curl GET https://ha.test/api/states/light.shelf '; then
  pass "hass with a light names only that light, the others keep what they have"
else
  fail "hass with a light names only that light, the others keep what they have" "$(cat "$calls")"
fi

# --- with Home Assistant switched off, its lights are neither set nor listed
set_config '{"mode":"palette","colors":3,"home_assistant":{"enabled":false,"url":"https://ha.test"},"assign":{"hass:light.desk":2}}'
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if ! grep -q '^curl' "$calls" && ! plan | grep -q '^hass'; then
  pass "Home Assistant switched off: no call, no lights in the plan"
else
  fail "Home Assistant switched off: no call, no lights in the plan" "$(cat "$calls")"
fi
set_config '{"mode":"palette","colors":3,"home_assistant":{"url":"https://ha.test"}}'
OPENRGB_LIST_DEVICES="$PLAIN_DEVICES" run_apply
if ! grep -q '^curl' "$calls" && ! plan | grep -q '^hass'; then
  pass "Home Assistant stays off until switched on, an address alone is not enough"
else
  fail "Home Assistant stays off until switched on, an address alone is not enough" "$(cat "$calls")"
fi
rm -f "$mock_bin/secret-tool" "$mock_bin/curl" "$hass_lights"
set_config '{"mode":"single"}'

echo
if (( failures > 0 )); then
  echo "$failures failing"
  exit 1
fi
echo "all passing"
