# omarchy-openrgb — design

Omarchy shell plugin that retints every device managed by OpenRGB whenever the
Omarchy theme changes. Modelled on omacom/omarchy#12199, packaged as an
installable plugin instead of a change to Omarchy itself.

## Shape

- `manifest.json` — id `huacnlee.theme-rgb`, name "Theme RGB", `kinds: ["service"]`,
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
