#!/bin/bash
# The manifest is the contract with the shell: the id, kind and entry point
# have to agree with what Service.qml does, and the folder has to pass the
# same validation `omarchy plugin add` runs.

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

fail() { echo "not ok - $*" >&2; exit 1; }

[[ $(jq -r '.schemaVersion' manifest.json) == 1 ]] || fail "schemaVersion must be 1"
[[ $(jq -r '.id' manifest.json) == huacnlee.openrgb ]] || fail "id must be huacnlee.openrgb"
[[ $(jq -r '.name' manifest.json) == OpenRGB ]] || fail "name must be OpenRGB"
[[ $(jq -c '.kinds' manifest.json) == '["service"]' ]] || fail "kinds must be exactly [service]"
[[ $(jq -r '.entryPoints.service' manifest.json) == Service.qml ]] || fail "service entry point must be Service.qml"
[[ -f Service.qml ]] || fail "Service.qml is missing"
[[ -x bin/omarchy-openrgb-apply ]] || fail "bin/omarchy-openrgb-apply must be executable"

# The service runs the bundled script and re-runs it when the theme changes.
grep -q 'bin/omarchy-openrgb-apply' Service.qml || fail "Service.qml must run bin/omarchy-openrgb-apply"
grep -q 'omarchy/current/theme.name' Service.qml || fail "Service.qml must watch current/theme.name"
grep -q 'watchChanges: true' Service.qml || fail "Service.qml must watch the theme name file for changes"

# Never escalate or touch the package manager from inside the shell.
! grep -Eq '\b(sudo|pkexec|pacman|yay)\b' Service.qml bin/omarchy-openrgb-apply \
  || fail "plugin code must not escalate privileges or manage packages"

if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy-plugin-validate . || fail "omarchy plugin validate rejected the folder"
fi

echo "ok - manifest agrees with Service.qml"
