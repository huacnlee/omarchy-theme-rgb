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
grep -q 'function setChoice' Service.qml || fail "Service.qml must expose setChoice"
grep -q 'moduleName: "huacnlee.theme_rgb"' Panel.qml || fail "Panel.qml must declare moduleName huacnlee.theme_rgb"
grep -q 'serviceFor(moduleName)' Panel.qml || fail "Panel.qml must look up its own service"
grep -q 'service.setChoice' Panel.qml || fail "Panel.qml must forward choices to the service"
! grep -q 'omarchy-theme-rgb-apply' Panel.qml || fail "Panel.qml must not run the script itself"

# Never escalate or touch the package manager from inside the shell.
! grep -Eq '\b(sudo|pkexec|pacman|yay)\b' Service.qml Panel.qml bin/omarchy-theme-rgb-apply \
  || fail "plugin code must not escalate privileges or manage packages"

if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy-plugin-validate . || fail "omarchy plugin validate rejected the folder"
fi

echo "ok - manifest agrees with Service.qml"
