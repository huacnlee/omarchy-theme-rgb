#!/bin/bash
# Exercises bin/omarchy-theme-rgb-detector against OpenRGB.json files in a
# throwaway config directory.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DETECTOR="$ROOT/bin/omarchy-theme-rgb-detector"

test_tmp_root="${TMPDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-theme-rgb-tests}"
mkdir -p "$test_tmp_root"
tmp=$(mktemp -d "$test_tmp_root/theme-rgb-detector.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

config="$tmp/OpenRGB/OpenRGB.json"
failures=0
pass() { echo "ok - $1"; }
fail() { echo "not ok - $1"; [[ -n ${2:-} ]] && printf '  %s\n' "$2"; failures=$((failures + 1)); }
run() { XDG_CONFIG_HOME="$tmp" bash "$DETECTOR" "$@"; }
flag() { jq -c --arg n "$1" '.Detectors.detectors[$n]' "$config"; }

mkdir -p "$(dirname "$config")"
cat >"$config" <<'JSON'
{
  "Detectors": { "detectors": { "SteelSeries Rival 710": true, "SteelSeries Apex Pro": true } },
  "Server": { "port": 6742 }
}
JSON

run disable "SteelSeries Rival 710"
if [[ $(flag "SteelSeries Rival 710") == false && $(flag "SteelSeries Apex Pro") == true \
      && $(jq -c .Server "$config") == '{"port":6742}' ]]; then
  pass "disable turns off one detector and keeps the rest of the file"
else
  fail "disable" "$(cat "$config")"
fi

run enable "SteelSeries Rival 710"
if [[ $(flag "SteelSeries Rival 710") == true ]]; then
  pass "enable turns the detector back on"
else
  fail "enable" "$(cat "$config")"
fi

rm -f "$config"
run disable "SteelSeries Rival 710"
if [[ $(flag "SteelSeries Rival 710") == false ]]; then
  pass "disable writes a config OpenRGB has not created yet"
else
  fail "disable without a config" "$(cat "$config" 2>&1)"
fi

printf 'not json' >"$config"
if ! run disable "SteelSeries Rival 710" 2>/dev/null && [[ $(cat "$config") == 'not json' ]]; then
  pass "an unreadable config is left untouched"
else
  fail "unreadable config" "$(cat "$config")"
fi

if ! run frobnicate "x" 2>/dev/null && ! run disable "" 2>/dev/null; then
  pass "bad arguments are refused"
else
  fail "bad arguments"
fi

echo
if (( failures > 0 )); then
  echo "$failures failing"
  exit 1
fi
echo "all passing"
