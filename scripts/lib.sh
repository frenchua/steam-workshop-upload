#!/usr/bin/env bash
# Shared helpers for the Steam Workshop Upload action.

# Emit a GitHub Actions error annotation and exit non-zero.
die() {
  printf '::error::%s\n' "$*" >&2
  exit 1
}

# Make text safe to place inside a double-quoted VDF string.
#
# SteamCMD's KeyValues parser does not honour escape sequences when reading a
# workshopitem manifest. A \" does not produce a quote: it ends the string
# early, and the upload dies with
#
#   ../tier1/KeyValues.cpp (3202) : Assertion Failed:
#   Error while parsing text KeyValues for resource workshopitem
#
# This was seen on a real publish whose changenote quoted a mod name. A double
# quote therefore cannot be represented at all, so it becomes an apostrophe.
# A VDF string also cannot span lines, so newlines and tabs collapse into
# single spaces. Trailing backslashes are dropped so they cannot escape the
# closing quote in a parser that does honour escapes.
vdf_sanitize() {
  local s=$1 apostrophe="'" space=' '
  s=${s//'"'/"$apostrophe"}
  s=${s//$'\r'/"$space"}
  s=${s//$'\n'/"$space"}
  s=${s//$'\t'/"$space"}

  # Collapse runs of spaces left behind by the folding above.
  while [ "${s#*  }" != "$s" ]; do
    s=${s//  /"$space"}
  done

  # Trim leading and trailing whitespace.
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}

  # Drop any trailing backslashes.
  # SC1003: a lone backslash is exactly what is being compared against.
  # shellcheck disable=SC1003
  while [ -n "$s" ] && [ "${s: -1}" = '\' ]; do
    s=${s%?}
  done

  printf '%s' "$s"
}

# Shorten text until its sanitized form fits a character budget.
#
# SteamCMD's KeyValues parser also aborts on an over-long string, with
# "AddStringToPool: key name too long" followed by the same parse failure as
# above. A full multi-paragraph commit message is enough to trigger it.
#
# Usage: vdf_fit <max_chars> <text>
vdf_fit() {
  local max=$1 text=$2 clean n
  [ -n "$text" ] || { printf ''; return; }

  clean=$(vdf_sanitize "$text")
  if [ "${#clean}" -le "$max" ]; then
    printf '%s' "$clean"
    return
  fi

  n=$max
  while [ "$n" -gt 0 ]; do
    clean=$(vdf_sanitize "${text:0:n} [truncated]")
    if [ "${#clean}" -le "$max" ]; then
      printf '%s' "$clean"
      return
    fi
    n=$(( n - 64 ))
  done
  printf '[changenote omitted: too long]'
}

# Write a workshopitem manifest.
# Usage: vdf_manifest <appid> <publishedfileid> <contentfolder> <changenote>
vdf_manifest() {
  printf '"workshopitem"\n{\n\t"appid" "%s"\n\t"publishedfileid" "%s"\n\t"contentfolder" "%s"\n\t"changenote" "%s"\n}\n' \
    "$1" "$2" "$3" "$(vdf_sanitize "$4")"
}

# Require a value to be a non-empty string of digits.
require_numeric() {
  local name=$1 value=$2
  case "$value" in
    '') die "$name is empty" ;;
    *[!0-9]*) die "$name must be numeric, got '$value'" ;;
  esac
}
