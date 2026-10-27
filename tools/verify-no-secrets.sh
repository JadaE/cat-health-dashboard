#!/usr/bin/env bash
# Fetch every published file (as listed in local site/) from the live Site, plus a live data read,
# and grep for the API key or credential-like text. Also checks robots/referrer meta + headers.
# The secret path is masked as <TOKEN> in the output.
set -uo pipefail
DIR=$(cd "$(dirname "$0")/.." && pwd); CFG="$DIR/secret-config.json"
S=$(jq -r .slug "$CFG"); TOK=$(jq -r .path_token "$CFG"); C=$(jq -r .collection "$CFG"); BASE="https://$S.here.now"
KEYVAL="${HERENOW_API_KEY:-$(cat "$HOME/.herenow/credentials" 2>/dev/null || true)}"
T=$(mktemp -d); fail=0
mask(){ sed -E "s#$TOK#<TOKEN>#g; s#$C#<COLL>#g"; }
check(){ local path="$1" code
  code=$(curl -s -D "$T/h" -o "$T/f" -w '%{http_code}' "$BASE/$path"); printf '%-34s HTTP %s %7s bytes  ' "/$path" "$code" "$(wc -c <"$T/f")" | mask
  hit=0; [ -n "$KEYVAL" ] && cat "$T/h" "$T/f" | grep -aqF -- "$KEYVAL" && hit=1
  cat "$T/h" "$T/f" | grep -aqiE 'HERENOW_API_KEY|Authorization|Bearer|api[_-]?key|claim_?token|hnk_' && hit=$((hit+2))
  [ $hit = 0 ] && echo clean || { echo "SUSPICIOUS($hit)"; fail=1; }; }
cd "$DIR/site"; while IFS= read -r f; do f=${f#./}; [[ $f == .herenow/* ]] && continue; check "$f"; done < <(find . -type f | sort)
check "$TOK/"; check ".herenow/data.json"; check ".herenow/data/$C?limit=100"
echo "--- headers / meta on the app page"
curl -s -D "$T/h" -o "$T/f" "$BASE/$TOK/"
grep -i '^referrer-policy' "$T/h" || { echo "MISSING Referrer-Policy header"; fail=1; }
grep -i '^x-robots-tag' "$T/h" || echo "no X-Robots-Tag header (here.now has no custom-header setting; meta robots used instead)"
grep -o '<meta name="robots"[^>]*>' "$T/f" || { echo "MISSING meta robots"; fail=1; }
grep -o '<meta name="referrer"[^>]*>' "$T/f" || { echo "MISSING meta referrer"; fail=1; }
grep -qF "$TOK" <(curl -s "$BASE/") && { echo "ROOT PAGE LEAKS TOKEN"; fail=1; } || echo "root page does not contain the secret path"
rm -rf "$T"; [ $fail = 0 ] && echo "PASS: no key or token found in served files." || echo "FAIL"; exit $fail
