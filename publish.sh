#!/usr/bin/env bash
# (Re)publish the cat health log to here.now:   bash publish.sh
# The app lives at a secret path on its Site: https://<slug>.here.now/<path_token>/ (values in secret-config.json, mode 0600).
# Builds site/, refuses to publish if the API key or credential-looking text is in the files, then updates the Site.
# Shared records live in the Site's Site Data (secret collection name), not in the files, so republishing keeps them.
# First run with "slug": null in secret-config.json creates a NEW Site and saves its slug there.
# Never touches the Kanban board (YOUR-SITE-SLUG) or the retired YOUR-SITE-SLUG.
# Prints the secret app URL only when SHOW_URL=1.
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd); CFG="$DIR/secret-config.json"
SLUG="${HERENOW_SLUG:-$(jq -r '.slug//empty' "$CFG")}"
case "$SLUG" in YOUR-SITE-SLUG|YOUR-SITE-SLUG) echo "Refusing: $SLUG is not the cat dashboard's Site" >&2; exit 1;; esac
PUB=$(ls -d /home/box/agent-data/plugins/cache/cursor-public/here_now/*/skills/here-now/scripts/publish.sh 2>/dev/null | head -1)
[ -n "$PUB" ] || { echo "here.now publish.sh not found" >&2; exit 1; }
[ -n "${HERENOW_API_KEY:-}" ] || [ -f "$HOME/.herenow/credentials" ] || { echo "No here.now API key available" >&2; exit 1; }
python3 "$DIR/tools/build.py"
COLL=$(jq -r .collection "$CFG"); TOK=$(jq -r .path_token "$CFG")
jq -e --arg c "$COLL" '.collections[$c]' "$DIR/site/.herenow/data.json" >/dev/null || { echo "bad Site Data manifest" >&2; exit 1; }
[ -f "$DIR/site/$TOK/index.html" ] || { echo "app not at secret path" >&2; exit 1; }
KEYVAL="${HERENOW_API_KEY:-$(cat "$HOME/.herenow/credentials" 2>/dev/null || true)}"
if [ -n "$KEYVAL" ] && grep -rqF -- "$KEYVAL" "$DIR/site"; then echo "API key found in site files; NOT publishing" >&2; exit 1; fi
if grep -rqiE 'HERENOW_API_KEY|Authorization|Bearer|api[_-]?key|claim_?token|hnk_' "$DIR/site"; then echo "credential-looking text in site files; NOT publishing" >&2; exit 1; fi
cd "$DIR"
ARGS=("$DIR/site" --client cursor); [ -n "$SLUG" ] && ARGS+=(--slug "$SLUG")
OUT=$(bash "$PUB" "${ARGS[@]}" 2>&1) || { echo "$OUT" | grep -viE 'bearer|api_key|claim' >&2; echo "PUBLISH FAILED" >&2; exit 1; }
echo "$OUT" | grep -iE 'publish_result\.(persistence|auth_mode)|warn|error' || true
URL=$(echo "$OUT" | sed -n 's/^publish_result\.site_url=//p' | tail -1)
NEW=$(echo "$URL" | sed -E 's#^https://([^.]+)\.here\.now/?$#\1#')
[ -n "$NEW" ] || { echo "could not read slug from publish output" >&2; exit 1; }
if [ -z "$SLUG" ]; then jq --arg s "$NEW" '.slug=$s' "$CFG" > "$CFG.tmp" && chmod 600 "$CFG.tmp" && mv "$CFG.tmp" "$CFG"; SLUG=$NEW; echo "Created new Site $SLUG (saved in secret-config.json)"; fi
echo "Published $SLUG. Root shows a blank page; the app is at the secret path."
[ "${SHOW_URL:-}" = 1 ] && echo "App: https://$SLUG.here.now/$TOK/" || true
