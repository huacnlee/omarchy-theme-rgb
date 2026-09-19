# omarchy-openrgb — design

Omarchy shell plugin that retints every device managed by OpenRGB whenever the
Omarchy theme changes. Modelled on omacom/omarchy#12199, packaged as an
installable plugin instead of a change to Omarchy itself.

## Shape

- `manifest.json` — id `huacnlee.theme_rgb`, name "Theme RGB", `kinds: ["service"]`,
  `entryPoints.service = "Service.qml"`.
- `Service.qml` — runs inside omarchy-shell. Applies once when the service is
  created (shell start / plugin enable) and again whenever
  `~/.local/state/omarchy/current/theme.name` changes. `omarchy-theme-set`
  writes that file only after the new theme directory has replaced `current/
  theme`, so the colour files are already the new theme's when the watch fires.
  Runs `bash <plugin dir>/bin/omarchy-theme-rgb-apply` through a `Process`; a
  change arriving while one run is in flight sets a pending flag and re-runs
  once on exit (no concurrent OpenRGB calls). Failures are logged with
  `console.warn` and never propagate.
- `bin/omarchy-theme-rgb-apply` — plain bash, usable on its own as a `theme-set`
  hook. Exit 0 always.
  1. No `openrgb` on PATH → exit.
  2. Colour: `current/theme/keyboard.rgb` if it holds a valid 6-digit hex;
     otherwise `accent = "#rrggbb"` from `current/theme/colors.toml`; neither →
     exit.
  3. Mix 40% toward white (`BRIGHTEN_AMOUNT=0.4`), apply at `BRIGHTNESS=100`.
  4. `timeout 20 openrgb --list-devices` once. Devices whose mode list contains
     a `*[Gg]radient*` mode get that mode; all others get `static`. If the
     probe fails or lists nothing, broadcast `openrgb -m static -c <hex> -b 100`.
     Every call is `timeout 20`, output discarded.
- v1 has no user configuration; constants live at the top of the script.

## Tests

- `tests/apply-test.sh` — temporary HOME plus a mock `openrgb` that logs its
  arguments. Cases: static per device, gradient preferred, probe failure falls
  back to broadcast, accent fallback when keyboard.rgb is missing, no-op when
  both are missing, invalid colour no-op, missing openrgb no-op.
- `tests/manifest-test.sh` — manifest agrees with Service.qml and passes
  `omarchy plugin validate`.
- `make qml-check` lints Service.qml against `/usr/share/omarchy/shell`.

## Revision 2 — palette modes and a settings panel

Hardware light must read as the current theme, never as a generic rainbow, and
the user picks how many theme colours are used from a bar panel.

### Configuration

`~/.config/omarchy/theme-rgb.json`: `{"mode": "single" | "palette", "colors": 2 | 3 | 5}`.
Missing file or field → `palette`, `5`. Both `Service.qml` and the panel watch
the file; the script reads it with `jq`.

### Colour selection (bin/omarchy-theme-rgb-apply)

- `single`: as before (keyboard.rgb → accent, `-m static`).
- `palette`: candidates are `accent` plus `red orange yellow green cyan blue
  magenta brown` from `colors.toml` (no `bright_*`), deduplicated by hex and by
  hue within 10°. Each candidate is scored by hue distance from the accent;
  tier N keeps the accent plus the N−1 nearest, then orders them by signed hue
  offset from the accent so the gradient flows smoothly through it. Fewer than
  two usable colours → fall back to `single`.
- Brighten is 15% toward white for every mode (was 40%): enough to lift dim
  LEDs without shifting the colour away from what is on screen.
- Per device the `LEDs:` line gives the LED count; the stops are linearly
  interpolated to that many colours and sent as `-d N -c c1,c2,…` with no
  `-m` (verified on ENE DRAM and Razer: per-LED writes persist). Still one
  probe plus one chained call.
- `omarchy-theme-rgb-apply stops` prints the stops for the current theme and
  config, one hex per line, without touching OpenRGB. The panel preview uses
  it so the UI and the hardware share one implementation.

### Panel (bar widget)

`kinds: ["service", "bar-widget"]`, `entryPoints.barWidget = "Panel.qml"`.
A palette glyph in the bar; the popout has one row of four buttons — Single /
2 colours / 3 colours / 5 colours — a preview strip drawn from `stops`, a
"Sync now" button and a last-sync status line. Choosing a button writes
`theme-rgb.json`; the service applies it. Not placing the widget leaves the
service running on defaults.

## Revision 3 — pick the theme variables, bands not blends, brightness

The accent is often a conservative colour, so every mode lets the user say
which theme variables to light. Colours sit in clean bands on a device; they
are never blended. Light level is a setting.

### Configuration

```json
{
  "mode": "single" | "palette" | "custom",
  "single": "accent",
  "anchor": "accent",
  "colors": 5,
  "custom": ["blue", "magenta"],
  "brightness": 100
}
```

Variables: `accent red orange yellow green cyan blue magenta brown foreground`
from `colors.toml`. Defaults: `palette`, `accent`, `5`, `[]`, `100`. With no
`single` key, single mode uses the theme's `keyboard.rgb` if it ships one,
else the accent; a chosen variable always wins.

### Script

- `variables` subcommand: `name hex` per line for every variable the current
  theme defines, raw. The panel draws its swatches from this.
- `stops`: single → the chosen variable; palette → anchor plus the N−1 theme
  colours nearest its hue (as before, around the anchor instead of always the
  accent); custom → the listed variables in the listed order. Every stop is
  then scaled by `brightness/100`. No mixing toward white any more: what the
  theme says is what lights.
- Apply: single goes through `static` (or the device's gradient mode) at
  `-b 100` with the scaled colour; palette and custom write per LED with no
  mode, LED *i* of *N* taking stop `floor(i·k/N)` — *k* contiguous bands.
  Unknown LED count sends the stops as they are.

### Panel

Sections: COLOURS (Single / 2 / 3 / 5 / Custom), THEME COLOUR (ten swatches
from `variables`; single-select for Single and as the anchor for 2/3/5,
multi-select in click order for Custom), BRIGHTNESS (slider 10–100), and the
preview strip drawn as bands. Keyboard: ←/→ within a row, ↑/↓ between rows,
Enter selects, `1`–`5` pick a mode, `r` syncs.

## Revision 4 — layouts, tiers, device order, menu

- Tiers are `3` and `5` (the 2-colour tier is gone). Palette candidates are
  deduplicated by exact hex only and must lie within 90° of the anchor's hue;
  a theme short of nearby hues lights fewer colours rather than its opposite
  ones. The hero's meta line reports how many are actually lit.
- `layout` in theme-rgb.json: `flow` (default, by LED order), `rows`,
  `columns`, `zones`. On keyboards (LED names `Key: …`) a built-in map of the
  full-size ANSI board gives each key a row 0–5, a column in key units and a
  zone (`fn main mod nav numpad logo`); rows and columns split into k bands
  by position, zones give each zone the next stop in turn. Unknown keys and
  blank matrix cells keep their flow colour. Other devices: rows/columns are
  the flow; zones colours each OpenRGB zone in turn with `-z`.
- LED lines are tokenised exactly as openrgb prints them (quoted names, blank
  cells, the quote key), so `-c` indexes line up with the hardware.
- The device list records `Type:` and sorts desk peripherals first (keyboard,
  mouse, …), then monitor and lights, then what is inside the case.
- The panel header drops the sync timestamp; status only replaces the meta
  line when something needs attention. Swatches are compact content-sized
  chips in a flow, quiet at rest. A header menu offers Sync now, Install
  OpenRGB (when missing) and GitHub.
- Service saves are serialised (a save while one is in flight is queued and
  the latest payload wins) and the stops probe re-runs after finishing rather
  than being killed mid-way, so rapid switching between modes cannot leave the
  file, the preview and the hardware disagreeing.

## Revision 5 — roles by device class, no hue maths

Which theme colours light is decided by what the theme's roles are and what
each device is for, not by computing hues.

- Single: the accent, unless a variable was picked. keyboard.rgb is no longer
  consulted.
- 3: accent, background, foreground on every device.
- 5 and 8: the class's role list, first N. Desk (Keyboard, Mouse, Mousemat,
  Headset, HeadsetStand, Gamepad): `accent background foreground blue yellow
  red green magenta cyan orange brown`. Ambient (everything else — screen,
  strips, DRAM, motherboard, case): `accent background foreground blue
  magenta cyan red green yellow orange brown`. Variables the theme lacks and
  repeated hexes are skipped. `roles.desk` / `roles.ambient` in
  theme-rgb.json override the order; the panel's swatches for 3/5/8 are two
  rows in class order, and a click puts a variable first for that class.
- `stops` prints `desk a,b,c` and `ambient a,b,c`; the panel previews both.
- LED gamma: each channel goes through (c/max)^2.2 and the brightest channel
  lights fully, so colours keep the hue and saturation seen on screen and a
  dark background lights as its hue at full strength. Brightness scales the
  result.
- Several colours are always written in Direct mode (static keeps one colour
  and drops the rest); openrgb's output goes to last-apply.log, a non-zero
  exit is reported and retried once.

## Revision 6 — exact theme values

No LED gamma or normalisation: the LEDs receive the variable's hex exactly as
colors.toml defines it, scaled only by the brightness setting, so a theme
controls the colours precisely. The mode chips read 1 / 3 / Default / 8 /
Custom.
