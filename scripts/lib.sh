#!/usr/bin/env bash
# Shared helpers for the Steam Workshop Upload action.

# Emit a GitHub Actions error annotation and exit non-zero.
die() {
  printf '::error::%s\n' "$*" >&2
  exit 1
}

# Escape a string for use inside a double-quoted VDF value.
#
# VDF strings cannot span lines and are delimited by double quotes, so
# backslashes and quotes are escaped and newlines folded into literal \n.
# The replacements are taken from variables on purpose: bash strips
# backslashes out of a literal ${var//pattern/replacement} replacement, which
# silently turns \n into a bare "n".
vdf_escape() {
  # SC1003: a lone backslash is exactly what is wanted here.
  # shellcheck disable=SC1003
  local s=$1 bs='\'
  s=${s//"$bs"/"$bs$bs"}
  s=${s//'"'/"$bs\""}
  s=${s//$'\r'/}
  s=${s//$'\n'/"${bs}n"}
  printf '%s' "$s"
}

# Write a workshopitem manifest.
# Usage: vdf_manifest <appid> <publishedfileid> <contentfolder> <changenote>
vdf_manifest() {
  printf '"workshopitem"\n{\n\t"appid" "%s"\n\t"publishedfileid" "%s"\n\t"contentfolder" "%s"\n\t"changenote" "%s"\n}\n' \
    "$1" "$2" "$3" "$(vdf_escape "$4")"
}

# Require a value to be a non-empty string of digits.
require_numeric() {
  local name=$1 value=$2
  case "$value" in
    '') die "$name is empty" ;;
    *[!0-9]*) die "$name must be numeric, got '$value'" ;;
  esac
}
