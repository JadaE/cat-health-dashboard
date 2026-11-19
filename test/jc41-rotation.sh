#!/usr/bin/env bash
# JC-41 tests: per-collection access in build.py (retired collections are owner-only and never reach the
# app), tools/prepare-rotation.py (new values only in a 0600 file under a 0700 folder, never printed,
# secret-config.json untouched), verify-no-secrets.sh retired-collection checks, and .gitignore additions.
# PLACEHOLDER secrets in a temp copy only; never the real secret-config.json, never the live site, no publish.
# Usage: bash test/jc41-rotation.sh      Needs: bash, python3, jq, curl, node, git, sha256sum.
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); chmod 700 "$T"; A=$T/app; mkdir -p "$A"; MP=""
cleanup(){ [ -n "$MP" ] && kill "$MP" 2>/dev/null; chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"; }; trap cleanup EXIT
cp -r "$REPO/src" "$REPO/tools" "$REPO/test" "$REPO/publish.sh" "$A/"; rm -rf "$A/test/node_modules"
PT=placeholdertoken0000000000000000abcd; PC=placeholder_coll_000000000000000000abcd; PR=placeholder_retired_00000000000000abcd
cfg(){ printf '{"slug":"placeholder-slug-0000","path_token":"%s","collection":"%s"%s}\n' "$PT" "$PC" "${1:+,$1}" > "$A/secret-config.json"; chmod 600 "$A/secret-config.json"; }
export CAT_HEALTH_DIR=$A
pass=0; failn=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }; no(){ echo "FAIL: $1"; failn=$((failn+1)); }
has(){ printf '%s' "$1" | grep -qF -e "$PT" -e "$PC" -e "$PR"; }
M=$A/site/.herenow/data.json; APP=$A/site/$PT/index.html
build(){ out=$(python3 "$A/tools/build.py" 2>&1); rc=$?; }
LIVE_ACC='{"read":"public","insert":"public","update":"public","delete":"owner"}'
OWN_ACC='{"read":"owner","insert":"owner","update":"owner","delete":"owner"}'

echo "== 1. build.py without retired collections (unchanged behavior)"
cfg; build; [ $rc = 0 ] && ok "build passes with no retired_collections" || no "build rc=$rc"
[ "$(jq -c '.collections|keys' "$M")" = "[\"$PC\"]" ] && ok "manifest has only the live collection" || no "manifest keys"
[ "$(jq -c --arg c "$PC" '.collections[$c].access' "$M")" = "$LIVE_ACC" ] && ok "live access unchanged (public read/insert/update, owner delete)" || no "live access"
[ "$(jq -r --arg c "$PC" '.collections[$c]|.publicMutation+" "+.rateLimit' "$M")" = "open 120/minute/ip" ] && ok "live keeps publicMutation + rateLimit" || no "live mutation/rate"
cfg '"retired_collections":null'; build; [ $rc = 0 ] && [ "$(jq '.collections|length' "$M")" = 1 ] && ok "retired_collections: null is treated as none" || no "null retired rc=$rc"

echo "== 2. build.py with a retired collection"
cfg "\"retired_collections\":[\"$PR\"]"; (umask 022; build); [ $rc = 0 ] && ok "build passes with one retired collection" || no "build rc=$rc"
has "$out" && no "build output printed a secret" || ok "build output has no token/collection names"
[ "$(jq -c --arg c "$PR" '.collections[$c].access' "$M")" = "$OWN_ACC" ] && ok "retired access is owner for read/insert/update/delete" || no "retired access"
[ "$(jq -r --arg c "$PR" '.collections[$c]|has("publicMutation") or has("rateLimit")' "$M")" = false ] && ok "retired has no publicMutation/rateLimit" || no "retired mutation keys"
[ "$(jq -c --arg c "$PR" '.collections[$c].fields' "$M")" = "$(jq -c --arg c "$PC" '.collections[$c].fields' "$M")" ] && ok "retired has the same fields as live" || no "retired fields differ"
[ "$(jq -c --arg c "$PC" '.collections[$c].access' "$M")" = "$LIVE_ACC" ] && ok "live access unchanged next to a retired one" || no "live access changed"
grep -qF "$PC" "$APP" && ok "app page uses the live collection" || no "live collection missing from app"
[ -z "$(grep -rlF "$PR" "$A/site" | grep -vF "$M")" ] && ok "retired name appears in no site file except the manifest" || no "retired name leaked into site files"
bash "$A/tools/check-site-modes.sh" "$A" "$PT" >/dev/null 2>&1 && ok "site/ modes still private (umask 022 build)" || no "modes not private"

echo "== 3. build.py refuses bad retired_collections (names never printed)"
refuse(){ cfg "$1"; build; [ $rc != 0 ] && printf '%s' "$out" | grep -q "build refused" && ok "refuses: $2" || no "accepted: $2 (rc=$rc)"
  has "$out" && no "refusal printed a secret ($2)"; }
refuse "\"retired_collections\":[\"$PC\"]" "retired equals live"
refuse '"retired_collections":["Bad_Upper"]' "uppercase name"
refuse '"retired_collections":["9starts_with_digit"]' "leading digit"
refuse '"retired_collections":["a/b"]' "slash in name"
refuse '"retired_collections":[""]' "empty name"
refuse '"retired_collections":[123]' "non-string name"
refuse "\"retired_collections\":\"$PR\"" "not a list"
refuse "\"retired_collections\":[\"$PR\",\"$PR\"]" "duplicates"

echo "== 4. prepare-rotation.py"
cfg "\"retired_collections\":[\"$PR\"]"; H0=$(sha256sum "$A/secret-config.json" | cut -d' ' -f1)
N=$A/.rotation/secret-config.next.json
out=$(python3 "$A/tools/prepare-rotation.py" 2>&1); rc=$?
[ $rc = 0 ] && ok "generates the next config" || no "prepare rc=$rc"
[ "$(stat -c %a "$A/.rotation")" = 700 ] && ok ".rotation/ is 0700" || no ".rotation mode $(stat -c %a "$A/.rotation")"
[ "$(stat -c %a "$N")" = 600 ] && ok "secret-config.next.json is 0600" || no "next mode $(stat -c %a "$N")"
[ "$(sha256sum "$A/secret-config.json" | cut -d' ' -f1)" = "$H0" ] && [ "$(stat -c %a "$A/secret-config.json")" = 600 ] && ok "secret-config.json untouched" || no "secret-config.json changed"
NC=$(jq -r .collection "$N"); NT=$(jq -r .path_token "$N")
printf '%s' "$out" | grep -qF -e "$NC" -e "$PT" -e "$PC" -e "$PR" && no "prepare output printed a value" || ok "prepare output shows no old or new values"
printf '%s' "$NC" | grep -qE '^c[a-z2-7]{32}$' && ok "new collection is 160-bit base32 with a letter prefix" || no "new collection format"
[ "$NC" != "$PC" ] && ok "new collection differs from the old" || no "collection not rotated"
[ "$NT" = "$PT" ] && ok "path token unchanged without --token" || no "token changed without --token"
[ "$(jq -c .retired_collections "$N")" = "[\"$PR\",\"$PC\"]" ] && ok "old collection appended to existing retired list" || no "retired list"
[ "$(jq -r .slug "$N")" = placeholder-slug-0000 ] && ok "slug unchanged" || no "slug changed"
H1=$(sha256sum "$N" | cut -d' ' -f1); out=$(python3 "$A/tools/prepare-rotation.py" 2>&1); rc=$?
[ $rc != 0 ] && [ "$(sha256sum "$N" | cut -d' ' -f1)" = "$H1" ] && ok "second run refuses, file not overwritten" || no "overwrite rc=$rc"
out=$(python3 "$A/tools/prepare-rotation.py" --check 2>&1); [ $? = 0 ] && ! printf '%s' "$out" | grep -qF "$NC" && ok "--check passes without showing values" || no "--check failed"
chmod 644 "$N"; python3 "$A/tools/prepare-rotation.py" --check >/dev/null 2>&1 && no "--check accepted a 0644 file" || ok "--check fails on a 0644 file"; chmod 600 "$N"
chmod 755 "$A/.rotation"; python3 "$A/tools/prepare-rotation.py" --check >/dev/null 2>&1 && no "--check accepted a 0755 folder" || ok "--check fails on a 0755 folder"; chmod 700 "$A/.rotation"
python3 "$A/tools/prepare-rotation.py" --bogus >/dev/null 2>&1 && no "unknown flag accepted" || ok "unknown flag refused"
grep -qE '^import.*(socket|urllib|http|requests|subprocess)' "$A/tools/prepare-rotation.py" && no "prepare-rotation imports network/subprocess modules" || ok "prepare-rotation has no network or subprocess imports"
# the next config builds: new live collection public, old one owner-only and absent from the app
B=$T/b; mkdir -p "$B"; cp -r "$A/src" "$A/tools" "$B/"; cp "$N" "$B/secret-config.json"
out=$(CAT_HEALTH_DIR=$B python3 "$B/tools/build.py" 2>&1); rc=$?
[ $rc = 0 ] && [ "$(jq -c --arg c "$NC" '.collections[$c].access' "$B/site/.herenow/data.json")" = "$LIVE_ACC" ] \
  && [ "$(jq -c --arg c "$PC" '.collections[$c].access' "$B/site/.herenow/data.json")" = "$OWN_ACC" ] && ok "next config builds: new live public, old retired owner-only" || no "next config build rc=$rc"
[ -z "$(grep -rlF "$PC" "$B/site" | grep -v '/.herenow/data.json$')" ] && ok "old collection absent from the rebuilt app" || no "old collection in rebuilt app"

echo "== 5. prepare-rotation.py --token and refusals"
rm -rf "$A/.rotation"; out=$(python3 "$A/tools/prepare-rotation.py" --token 2>&1); rc=$?; NT=$(jq -r .path_token "$N" 2>/dev/null)
[ $rc = 0 ] && printf '%s' "$NT" | grep -qE '^[a-z2-7]{32}$' && [ "$NT" != "$PT" ] && ok "--token writes a new 160-bit path token" || no "--token rc=$rc"
printf '%s' "$out" | grep -qF -e "$NT" -e "$(jq -r .collection "$N")" && no "--token output printed a value" || ok "--token output shows no values"
rm -rf "$A/.rotation"; chmod 644 "$A/secret-config.json"; python3 "$A/tools/prepare-rotation.py" >/dev/null 2>&1; rc=$?
[ $rc != 0 ] && [ ! -e "$N" ] && ok "refuses when secret-config.json is group/world readable" || no "loose config accepted"; chmod 600 "$A/secret-config.json"
mkdir -p "$T/elsewhere"; chmod 700 "$T/elsewhere"; ln -s "$T/elsewhere" "$A/.rotation"; python3 "$A/tools/prepare-rotation.py" >/dev/null 2>&1; rc=$?
[ $rc != 0 ] && [ -z "$(ls "$T/elsewhere")" ] && ok "refuses a symlinked .rotation folder" || no "symlink followed"; rm -f "$A/.rotation"
mkdir -m 755 "$A/.rotation"; python3 "$A/tools/prepare-rotation.py" >/dev/null 2>&1; rc=$?
[ $rc != 0 ] && [ ! -e "$N" ] && ok "refuses an existing 0755 .rotation folder" || no "loose folder accepted"; rm -rf "$A/.rotation"
cfg '"retired_collections":["Bad"]'; python3 "$A/tools/prepare-rotation.py" >/dev/null 2>&1 && no "bad current retired list accepted" || ok "refuses an invalid current retired list"
mkdir -p "$T/nocfg"; out=$(CAT_HEALTH_DIR=$T/nocfg python3 "$A/tools/prepare-rotation.py" 2>&1); [ $? != 0 ] && [ ! -e "$T/nocfg/.rotation" ] && ok "refuses with no secret-config.json" || no "no-config run"

echo "== 6. verify-no-secrets.sh with a retired collection (local mock)"
cfg "\"retired_collections\":[\"$PR\"]"; build
PORT=$((20000 + RANDOM % 20000)); (cd "$A/test" && MOCK_ROOT="$A/site" exec node mock-server.js $PORT >/dev/null 2>&1) & MP=$!
for i in $(seq 50); do curl -s -o /dev/null "http://localhost:$PORT/robots.txt" && break; sleep 0.1; done
code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/.herenow/data/$PR?limit=1"); [ "$code" = 401 ] && ok "mock: retired collection answers 401 without auth" || no "mock retired code $code"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -d '{}' "http://localhost:$PORT/.herenow/data/$PR"); [ "$code" = 401 ] && ok "mock: retired collection refuses public insert" || no "mock retired POST $code"
code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/.herenow/data/$PC?limit=1"); [ "$code" = 200 ] && ok "mock: live collection still public" || no "mock live code $code"
out=$(VERIFY_BASE=http://localhost:$PORT bash "$A/tools/verify-no-secrets.sh" 2>&1); rc=$?
[ $rc = 0 ] && ok "verify passes with an owner-only retired collection" || { no "verify rc=$rc"; printf '%s\n' "$out" | sed "s#$PT#<TOKEN>#g; s#$PC#<COLL>#g; s#$PR#<RETIRED>#g"; }
has "$out" && no "verify output leaked a name" || ok "verify output masks token, collection and retired names"
printf '%s' "$out" | grep -q "retired collection: public read HTTP 401" && ok "verify checks the retired collection's public read" || no "retired read check missing"
jq --arg c "$PR" '.collections[$c].access.read="public"' "$M" > "$T/m.json" && cat "$T/m.json" > "$M"
out=$(VERIFY_BASE=http://localhost:$PORT bash "$A/tools/verify-no-secrets.sh" 2>&1); rc=$?
[ $rc != 0 ] && printf '%s' "$out" | grep -q "publicly readable" && ok "verify fails if a retired collection is publicly readable" || no "public retired not caught (rc=$rc)"
build; echo "<p>$PR</p>" > "$A/site/index.html"; chmod 600 "$A/site/index.html"
out=$(VERIFY_BASE=http://localhost:$PORT bash "$A/tools/verify-no-secrets.sh" 2>&1); rc=$?
[ $rc != 0 ] && printf '%s' "$out" | grep -q "RETIRED COLLECTION" && ok "verify fails if the root page has a retired name" || no "retired root leak not caught"
has "$out" && no "verify failure output leaked a name" || ok "verify failure output still masked"
CS=$T/curlshim; mkdir -p "$CS"; printf '#!/bin/sh\ntouch %s/curl-called\nexit 7\n' "$T" > "$CS/curl"; chmod +x "$CS/curl"
for bad in '"retired_collections":"x"' '"retired_collections":["Bad"]' '"retired_collections":[1]'; do
  cfg "$bad"; rm -f "$T/curl-called"; PATH="$CS:$PATH" VERIFY_BASE=http://localhost:$PORT bash "$A/tools/verify-no-secrets.sh" >/dev/null 2>&1; rc=$?
  [ $rc = 2 ] && [ ! -e "$T/curl-called" ] && ok "bad retired_collections -> error before any curl" || no "bad retired rc=$rc"; done

echo "== 7. .gitignore additions (Security Lead JC-36 NB-1/NB-2) and repo checks"
for f in config.local.json config.local.js .rotation/secret-config.next.json .rotation/x data.json secret-config.next.json; do
  git -C "$REPO" check-ignore -q "$f" && ok ".gitignore drops $f" || no "$f not ignored"; done
for f in secret-config.example.json src/app.html tools/prepare-rotation.py; do
  git -C "$REPO" check-ignore -q "$f" && no "$f is ignored" || ok "$f stays tracked"; done
[ -z "$(git -C "$REPO" grep -lF -e "$PT" -e "$PC" -e "$PR" -- ':!test/jc36-modes.sh' ':!test/jc41-rotation.sh' 2>/dev/null)" ] && ok "repo has no placeholder values outside the tests" || no "repo grep hit"
[ -z "$(git -C "$REPO" ls-files .rotation)" ] && ok ".rotation/ not in the repo" || no ".rotation tracked"
[ -z "$(grep -rlF '/workspace/cat-health' "$REPO/tools")" ] && ok "no hardcoded app dir in tools/" || no "hardcoded app dir"

echo; echo "TOTAL pass=$pass fail=$failn"; [ $failn = 0 ]
