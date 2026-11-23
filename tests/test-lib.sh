#!/usr/bin/env bash
# Unit tests for the VDF helpers.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib.sh
. "$here/../scripts/lib.sh"

pass=0 fail=0

check() {
  local name=$1 want=$2 got=$3
  if [ "$want" = "$got" ]; then
    pass=$((pass + 1))
    printf 'ok   %s\n' "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$name" "$want" "$got"
  fi
}

check "plain text is unchanged" \
  'Simple note' "$(vdf_escape 'Simple note')"

check "double quotes are escaped" \
  'say \"hi\"' "$(vdf_escape 'say "hi"')"

check "backslashes are doubled" \
  'C:\\Users\\josh' "$(vdf_escape 'C:\Users\josh')"

check "newlines become a literal backslash-n" \
  'one\ntwo' "$(vdf_escape 'one
two')"

check "carriage returns are dropped" \
  'one\ntwo' "$(vdf_escape "$(printf 'one\r\ntwo')")"

check "a backslash before a quote stays unambiguous" \
  'back\\slash then \"quote\"' "$(vdf_escape 'back\slash then "quote"')"

check "empty input yields empty output" \
  '' "$(vdf_escape '')"

# A changenote must not be able to close the string and inject new keys: every
# quote that survives has to be backslash-escaped.
injected=$(vdf_escape '" } "appid" "666')
check "injection attempt stays escaped" \
  '\" } \"appid\" \"666' "$injected"

manifest=$(vdf_manifest 294100 123456 /work/staging 'line one
line "two"')
want='"workshopitem"
{
	"appid" "294100"
	"publishedfileid" "123456"
	"contentfolder" "/work/staging"
	"changenote" "line one\nline \"two\""
}'
check "manifest layout" "$want" "$manifest"

# require_numeric runs in a subshell because it exits on bad input.
if ( require_numeric appId 294100 ) >/dev/null 2>&1; then
  pass=$((pass + 1)); printf 'ok   %s\n' "require_numeric accepts digits"
else
  fail=$((fail + 1)); printf 'FAIL %s\n' "require_numeric rejected a valid id"
fi

if ( require_numeric appId '29x4' ) >/dev/null 2>&1; then
  fail=$((fail + 1)); printf 'FAIL %s\n' "require_numeric accepted a non-numeric id"
else
  pass=$((pass + 1)); printf 'ok   %s\n' "require_numeric rejects non-digits"
fi

if ( require_numeric appId '' ) >/dev/null 2>&1; then
  fail=$((fail + 1)); printf 'FAIL %s\n' "require_numeric accepted an empty id"
else
  pass=$((pass + 1)); printf 'ok   %s\n' "require_numeric rejects empty"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
