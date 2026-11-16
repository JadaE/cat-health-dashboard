#!/usr/bin/env bash
# Mode gate: the built site/ must be private on a shared machine.
#   site/, site/.herenow/, site/<token>/ must be 0700; data.json and <token>/index.html must be 0600;
#   nothing else under site/ may be group/world readable, writable or traversable.
# Usage: check-site-modes.sh <app dir> <path token>. Prints <TOKEN> instead of the token.
# Exit 0 only when every check ran and passed; any error (bad args, stat/find failure) fails the check.
set -uo pipefail
[ $# -eq 2 ] && [ -n "$1" ] && [ -n "$2" ] || { echo "MODE CHECK: usage: check-site-modes.sh <app dir> <path token>" >&2; exit 2; }
DIR="$1"; TOK="$2"; S="$DIR/site"; bad=0
case "$TOK" in */*|.|..|.herenow) echo "MODE CHECK: invalid path token" >&2; exit 2;; esac
want(){ local p="$1" m="$2" have
  if [ ! -e "$p" ]; then echo "MODE CHECK: missing ${p//$TOK/<TOKEN>}" >&2; bad=1; return; fi
  if ! have=$(stat -c %a -- "$p" 2>/dev/null) || [ -z "$have" ]; then echo "MODE CHECK: cannot stat ${p//$TOK/<TOKEN>}" >&2; bad=1; return; fi
  [ "$have" = "$m" ] || { echo "MODE CHECK: ${p//$TOK/<TOKEN>} is $have, must be $m" >&2; bad=1; }; }
want "$S" 700; want "$S/.herenow" 700; want "$S/$TOK" 700
want "$S/.herenow/data.json" 600; want "$S/$TOK/index.html" 600
if loose=$(find "$S" -perm /077 -print 2>/dev/null); then
  n=$(printf '%s' "$loose" | grep -c . || true)
  [ "$n" = 0 ] || { echo "MODE CHECK: $n path(s) under site/ are group/world accessible" >&2; bad=1; }
else echo "MODE CHECK: could not scan site/ (find failed)" >&2; bad=1; fi
[ $bad = 0 ] && echo "mode check: site/ is private (dirs 0700, files 0600)"
exit $bad
