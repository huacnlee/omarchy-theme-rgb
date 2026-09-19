#!/bin/bash
# The manifest is the contract with the shell: the id, kind and entry point
# have to agree with what Service.qml does, and the folder has to pass the
# same validation `omarchy plugin add` runs.

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

fail() { echo "not ok - $*" >&2; exit 1; }

[[ $(jq -r '.schemaVersion' manifest.json) == 1 ]] || fail "schemaVersion must be 1"
[[ $(jq -r '.id' manifest.json) == huacnlee.theme_rgb ]] || fail "id must be huacnlee.theme_rgb"
[[ $(jq -r '.name' manifest.json) == "Theme RGB" ]] || fail "name must be Theme RGB"
[[ $(jq -c '.kinds' manifest.json) == '["service","bar-widget"]' ]] || fail "kinds must be [service, bar-widget]"
[[ $(jq -r '.entryPoints.service' manifest.json) == Service.qml ]] || fail "service entry point must be Service.qml"
[[ $(jq -r '.entryPoints.barWidget' manifest.json) == Panel.qml ]] || fail "bar widget entry point must be Panel.qml"
[[ $(jq -r '.barWidget.allowMultiple' manifest.json) == false ]] || fail "barWidget.allowMultiple must be false"
[[ $(jq -r '.barWidget.defaultSection' manifest.json) == right ]] || fail "barWidget.defaultSection must be right"
[[ -f Service.qml ]] || fail "Service.qml is missing"
[[ -f Panel.qml ]] || fail "Panel.qml is missing"
[[ -x bin/omarchy-theme-rgb-apply ]] || fail "bin/omarchy-theme-rgb-apply must be executable"

# The service runs the bundled script and re-runs it when the theme changes.
grep -q 'bin/omarchy-theme-rgb-apply' Service.qml || fail "Service.qml must run bin/omarchy-theme-rgb-apply"
grep -q 'omarchy/current/theme.name' Service.qml || fail "Service.qml must watch current/theme.name"
grep -q 'watchChanges: true' Service.qml || fail "Service.qml must watch the theme name file for changes"
grep -q 'omarchy/theme-rgb.json' Service.qml || fail "Service.qml must watch theme-rgb.json"

# The service owns the state: it writes theme-rgb.json and previews through
# the script's own `stops` output so the UI never drifts from the hardware.
# The panel only shows that state and forwards the user's choice.
grep -q '"stops"' Service.qml || fail "Service.qml must preview via the stops subcommand"
grep -q '"variables"' Service.qml || fail "Service.qml must read the theme variables from the script"
grep -q 'theme-rgb/devices' Service.qml || fail "Service.qml must read the device list the script records"
for fn in setMode setSingle setAnchor setColors setPalette toggleCustom setBrightness setLayout; do
  grep -q "function $fn" Service.qml || fail "Service.qml must expose $fn"
done
# Without a server every openrgb call re-probes the hardware for seconds; the
# service keeps a headless one for the life of the shell.
grep -q '"openrgb", "--server", "--noautoconnect"' Service.qml || fail "Service.qml must keep a headless OpenRGB server"
grep -q 'moduleName: "huacnlee.theme_rgb"' Panel.qml || fail "Panel.qml must declare moduleName huacnlee.theme_rgb"
grep -q 'serviceFor(moduleName)' Panel.qml || fail "Panel.qml must look up its own service"
for fn in setMode setSingle setAnchor setPalette toggleCustom setBrightness setLayout; do
  grep -q "service.$fn" Panel.qml || fail "Panel.qml must forward $fn to the service"
done
grep -q '"DEVICES"' Panel.qml || fail "Panel.qml must list the devices"
grep -q '"LAYOUT"' Panel.qml || fail "Panel.qml must offer the layout choice"
grep -q 'service.setLayout' Panel.qml || fail "Panel.qml must forward setLayout to the service"
grep -q 'Your theme, on every light.' Panel.qml || fail "Panel.qml must carry the slogan"
grep -q 'Install OpenRGB' Panel.qml || fail "Panel.qml must offer the install from its welcome page"
! grep -q 'shellQuote' Panel.qml || fail "the bar API has no shellQuote"
! grep -q 'omarchy-theme-rgb-apply' Panel.qml || fail "Panel.qml must not run the script itself"

# The header menu: sync, an install that goes through Omarchy's own package
# helper in a terminal the user can see (then re-probed by the service), and
# the project link.
[[ -f components/PanelMenu.qml ]] || fail "components/PanelMenu.qml is missing"
grep -q 'PanelMenu {' Panel.qml || fail "Panel.qml must show the header menu"
grep -q 'https://github.com/huacnlee/omarchy-theme-rgb' Panel.qml || fail "Panel.qml must link to the GitHub repository"
grep -q 'service.installOpenrgb()' Panel.qml || fail "Panel.qml must ask the service to install OpenRGB"
grep -q 'function installOpenrgb' Service.qml || fail "Service.qml must expose installOpenrgb"
grep -q 'function recheckOpenrgb' Service.qml || fail "Service.qml must expose recheckOpenrgb"
grep -q 'omarchy-launch-floating-terminal-with-presentation omarchy-pkg-add openrgb' Service.qml \
  || fail "Service.qml must install openrgb through omarchy-pkg-add in a floating terminal"

# Never escalate or touch the package manager from inside the shell.
! grep -Eq '\b(sudo|pkexec|pacman|yay)\b' Service.qml Panel.qml bin/omarchy-theme-rgb-apply \
  || fail "plugin code must not escalate privileges or manage packages"

if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy-plugin-validate . || fail "omarchy plugin validate rejected the folder"
fi

echo "ok - manifest agrees with Service.qml"
