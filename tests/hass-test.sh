#!/bin/bash
# Exercises bin/omarchy-theme-rgb-hass against a mock curl and keyring inside
# a throwaway HOME: where the address and token come from, and what the panel
# is told when Home Assistant cannot be used.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HASS="$ROOT/bin/omarchy-theme-rgb-hass"

test_tmp_root="${TMPDIR:-${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-theme-rgb-tests}"
mkdir -p "$test_tmp_root"
tmp=$(mktemp -d "$test_tmp_root/theme-rgb-hass.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

home="$tmp/home"
mock_bin="$tmp/bin"
calls="$tmp/calls"
status_file="$home/.local/state/omarchy/theme-rgb/hass-status"
mkdir -p "$home/.config/omarchy" "$mock_bin"

# The keyring answers for the origins listed in KEYRING ("service origin" per
# line); a store is written to STORE_LOG as its arguments, then the secret.
cat >"$mock_bin/secret-tool" <<'SH'
#!/bin/bash
if [[ $1 == store ]]; then
  { echo "$*"; cat; } >"$STORE_LOG"
  exit 0
fi
while read -r service origin; do
  [[ $* == "lookup service $service origin $origin" ]] && { printf 'token-%s' "$service"; exit 0; }
done <<<"${KEYRING:-}"
exit 1
SH
cat >"$mock_bin/curl" <<'SH'
#!/bin/bash
config=$(cat)
url=""
for arg; do [[ $arg == http* ]] && url=$arg; done
printf '%s %s\n' "$url" "$(grep -o 'Bearer [^"]*' <<<"$config")" >>"$CALL_LOG"
case ${CURL_ANSWER:-200} in
  200) printf '%s\n200' '[{"entity_id":"light.a","state":"on","attributes":{"friendly_name":"A","supported_color_modes":["xy"]}}]' ;;
  *) printf '\n%s' "$CURL_ANSWER" ;;
esac
SH
chmod +x "$mock_bin/secret-tool" "$mock_bin/curl"

failures=0
pass() { echo "ok - $1"; }
fail() { echo "not ok - $1"; [[ -n ${2:-} ]] && printf '  %s\n' "$2"; failures=$((failures + 1)); }
stored="$tmp/stored"
run() { : >"$calls"; HOME="$home" CALL_LOG="$calls" STORE_LOG="$stored" PATH="$mock_bin:$PATH" bash "$HASS" "$@" >/dev/null 2>&1; }
state() { cat "$status_file"; }

# --- no address anywhere ----------------------------------------------------
if ! run lights && [[ $(state) == no-address && ! -s $calls ]]; then
  pass "without an address nothing is called and the panel is told"
else
  fail "without an address nothing is called and the panel is told" "$(state)"
fi

# --- the hass plugin's address and token are used when Theme RGB has none ---
mkdir -p "$home/.config/omarchy/hass"
printf '{"baseUrl":"https://ha.home/"}\n' >"$home/.config/omarchy/hass/config.json"
if KEYRING="hass https://ha.home:443" run lights \
  && [[ $(state) == ok && $(cat "$calls") == "https://ha.home/api/states Bearer token-hass" ]]; then
  pass "the Home Assistant plugin's address and token are reused"
else
  fail "the Home Assistant plugin's address and token are reused" "$(state) $(cat "$calls")"
fi

# --- Theme RGB's own address and token come first ---------------------------
printf '{"home_assistant":{"url":"http://10.0.0.2:8123"}}\n' >"$home/.config/omarchy/theme-rgb.json"
if KEYRING=$'hass http://10.0.0.2:8123\ntheme-rgb-hass http://10.0.0.2:8123' run lights \
  && [[ $(cat "$calls") == "http://10.0.0.2:8123/api/states Bearer token-theme-rgb-hass" ]]; then
  pass "Theme RGB's own address and token win"
else
  fail "Theme RGB's own address and token win" "$(cat "$calls")"
fi

# --- no token ----------------------------------------------------------------
if ! KEYRING="" run lights && [[ $(state) == no-token && ! -s $calls ]]; then
  pass "without a token nothing is called and the panel is told"
else
  fail "without a token nothing is called and the panel is told" "$(state)"
fi

# --- a refused token and an unreachable server ------------------------------
if ! KEYRING="hass http://10.0.0.2:8123" CURL_ANSWER=401 run lights && [[ $(state) == unauthorized ]]; then
  pass "a refused token reads as unauthorized"
else
  fail "a refused token reads as unauthorized" "$(state)"
fi
if ! KEYRING="hass http://10.0.0.2:8123" CURL_ANSWER=000 run lights && [[ $(state) == unreachable ]]; then
  pass "no answer reads as unreachable"
else
  fail "no answer reads as unreachable" "$(state)"
fi

# --- Connect: the address typed in the panel, and a new token kept ----------
rm -f "$stored"
if KEYRING="" run connect https://typed.example <<<"  new-token " \
  && [[ $(cat "$calls") == "https://typed.example/api/states Bearer new-token" ]] \
  && [[ $(cat "$stored") == $'store --label=Theme RGB Home Assistant service theme-rgb-hass origin https://typed.example:443\nnew-token' ]]; then
  pass "Connect keeps the typed token for the typed address and lists its lights"
else
  fail "Connect keeps the typed token for the typed address and lists its lights" "$(cat "$calls") / $(cat "$stored" 2>/dev/null)"
fi
rm -f "$stored"
if KEYRING="theme-rgb-hass https://typed.example:443" run connect https://typed.example </dev/null \
  && [[ ! -e $stored && $(cat "$calls") == "https://typed.example/api/states Bearer token-theme-rgb-hass" ]]; then
  pass "Connect with no token typed uses the one already kept"
else
  fail "Connect with no token typed uses the one already kept" "$(cat "$calls")"
fi

# --- no keyring tool -----------------------------------------------------------
bare_bin="$tmp/bare"
mkdir -p "$bare_bin"
for tool in bash jq mkdir mv cat awk; do ln -s "$(command -v "$tool")" "$bare_bin/$tool"; done
ln -s "$mock_bin/curl" "$bare_bin/curl"
: >"$calls"
if ! HOME="$home" CALL_LOG="$calls" PATH="$bare_bin" "$bare_bin/bash" "$HASS" lights >/dev/null 2>&1 \
  && [[ $(state) == no-keyring && ! -s $calls ]]; then
  pass "without secret-tool nothing is called and the panel is told"
else
  fail "without secret-tool nothing is called and the panel is told" "$(state)"
fi

echo
if (( failures > 0 )); then
  echo "$failures failing"
  exit 1
fi
echo "all passing"
