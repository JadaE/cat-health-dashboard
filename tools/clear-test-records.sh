#!/usr/bin/env bash
# Owner-only, SAFE cleanup after a live test: deletes only records whose item_id is NOT in a snapshot
# taken before the test (bash tools/clear-test-records.sh snapshot > /tmp/before.json; ...test...;
#  bash tools/clear-test-records.sh clear /tmp/before.json). Real records that existed before are never touched.
set -euo pipefail
DIR=$(cd "$(dirname "$0")/.." && pwd); CFG="$DIR/secret-config.json"
S=$(jq -r .slug "$CFG"); C=$(jq -r .collection "$CFG")
KEY="${HERENOW_API_KEY:-$(cat "$HOME/.herenow/credentials")}"
API="https://here.now/api/v1/publishes/$S/data/$C"; H=(-H "Authorization: Bearer $KEY" -H "X-HereNow-Client: cursor/direct-api")
list(){ curl -sf "${H[@]}" "$API?limit=100"; }
case "${1:-}" in
  snapshot) list;;
  clear) BEFORE=$(jq -c '[.records[].data.item_id]' "$2"); RIDS=$(jq -r '.records[].id' "$2" | sort)
    list | jq -r --argjson keep "$BEFORE" '.records[]|select((.data.item_id as $i|$keep|index($i))|not)|"\(.id) \(.data.item_id) deleted=\(.data.deleted)"' | while read -r id item rest; do
      echo "$RIDS" | grep -qx "$id" && { echo "skip $id (pre-existing record)"; continue; }
      curl -sf -X DELETE "${H[@]}" "$API/$id" >/dev/null && echo "deleted test record $id ($item, $rest)"; done
    echo "remaining: $(list | jq '.records|length')";;
  *) echo "usage: snapshot | clear <snapshot.json>" >&2; exit 1;;
esac
