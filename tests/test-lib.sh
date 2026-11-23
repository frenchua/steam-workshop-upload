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
  'Simple note' "$(vdf_sanitize 'Simple note')"

# SteamCMD does not honour escape sequences in a workshopitem manifest, so a
# quote cannot be represented and must be replaced outright. Emitting \" ends
# the string early and the upload fails to parse.
check "double quotes become apostrophes" \
  "say 'hi'" "$(vdf_sanitize 'say "hi"')"

check "newlines become single spaces" \
  'one two' "$(vdf_sanitize 'one
two')"

check "blank lines do not leave double spaces" \
  'subject body' "$(vdf_sanitize 'subject

body')"

check "carriage returns are folded too" \
  'one two' "$(vdf_sanitize "$(printf 'one\r\ntwo')")"

check "tabs become spaces" \
  'a b' "$(vdf_sanitize "$(printf 'a\tb')")"

check "surrounding whitespace is trimmed" \
  'trimmed' "$(vdf_sanitize '   trimmed
')"

check "interior backslashes survive" \
  'path C:\Users\josh' "$(vdf_sanitize 'path C:\Users\josh')"

# SC1003: the trailing lone backslash is the input under test.
# shellcheck disable=SC1003
check "a trailing backslash is dropped" \
  'ends here' "$(vdf_sanitize 'ends here\')"

check "empty input yields empty output" \
  '' "$(vdf_sanitize '')"

# The exact changenote that broke a real publish: a commit message quoting two
# mod names, which produced \" in the manifest and failed to parse.
check "the changenote from the failed rename publish is safe" \
  "Rename mod Rename mod from 'remember resource readout' to 'better reasourc readout', anticipating broader scope." \
  "$(vdf_sanitize 'Rename mod

Rename mod from "remember resource readout" to "better reasourc
readout", anticipating broader scope.')"

# No quote may survive anywhere in the output, since one quote is enough to
# terminate the string early.
nasty=$(vdf_sanitize '" } "appid" "666')
case "$nasty" in
  *'"'*) fail=$((fail + 1)); printf 'FAIL %s: %s\n' "a quote survived sanitizing" "$nasty" ;;
  *)     pass=$((pass + 1)); printf 'ok   %s\n' "injection attempt cannot close the string" ;;
esac

manifest=$(vdf_manifest 294100 123456 /work/staging 'line one
line "two"')
want='"workshopitem"
{
	"appid" "294100"
	"publishedfileid" "123456"
	"contentfolder" "/work/staging"
	"changenote" "line one line '"'"'two'"'"'"
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

# vdf_fit guards the other KeyValues limit: an over-long string aborts with
# "AddStringToPool: key name too long (1425 chars)".
short='a short note'
check "vdf_fit leaves a short note alone" \
  "$short" "$(vdf_fit 1000 "$short")"

check "vdf_fit leaves an empty note empty" \
  '' "$(vdf_fit 1000 '')"

long=$(printf 'word %.0s' $(seq 1 400))   # ~2000 characters
fitted=$(vdf_fit 1000 "$long")
if [ "${#fitted}" -le 1000 ] && [ "${#fitted}" -gt 0 ]; then
  pass=$((pass + 1)); printf 'ok   %s (%d chars)\n' "vdf_fit shortens a long note" "${#fitted}"
else
  fail=$((fail + 1)); printf 'FAIL %s: got %d chars\n' "vdf_fit shortens a long note" "${#fitted}"
fi

case "$fitted" in
  *'[truncated]') pass=$((pass + 1)); printf 'ok   %s\n' "vdf_fit marks truncation" ;;
  *)              fail=$((fail + 1)); printf 'FAIL %s\n' "vdf_fit did not mark truncation" ;;
esac

# A long note made entirely of quotes must come back both short enough and
# free of quotes.
quoted=$(printf '"%.0s' $(seq 1 1200))
quoted_fitted=$(vdf_fit 1000 "$quoted")
if [ "${#quoted_fitted}" -le 1000 ]; then
  case "$quoted_fitted" in
    *'"'*) fail=$((fail + 1)); printf 'FAIL %s\n' "vdf_fit left a quote in a long note" ;;
    *)     pass=$((pass + 1)); printf 'ok   %s (%d chars)\n' "vdf_fit handles a long quoted note" "${#quoted_fitted}" ;;
  esac
else
  fail=$((fail + 1)); printf 'FAIL %s: %d chars, over budget\n' "vdf_fit handles a long quoted note" "${#quoted_fitted}"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
