# omarchy-openrgb — design

Omarchy shell plugin that retints every device managed by OpenRGB whenever the
Omarchy theme changes. Modelled on omacom/omarchy#12199, packaged as an
installable plugin instead of a change to Omarchy itself.

## Shape

- `manifest.json` — id `huacnlee.openrgb`, name "OpenRGB", `kinds: ["service"]`,
  `entryPoints.service = "Service.qml"`.
- `Service.qml` — runs inside omarchy-shell. Applies once when the service is
  created (shell start / plugin enable) and again whenever
  `~/.local/state/omarchy/current/theme.name` changes. `omarchy-theme-set`
  writes that file only after the new theme directory has replaced `current/
  theme`, so the colour files are already the new theme's when the watch fires.
  Runs `bash <plugin dir>/bin/omarchy-openrgb-apply` through a `Process`; a
  change arriving while one run is in flight sets a pending flag and re-runs
  once on exit (no concurrent OpenRGB calls). Failures are logged with
  `console.warn` and never propagate.
- `bin/omarchy-openrgb-apply` — plain bash, usable on its own as a `theme-set`
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
