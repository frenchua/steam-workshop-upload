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

# Shorten text until its escaped form fits within a character budget.
#
# SteamCMD's KeyValues parser aborts on an over-long string with
# "AddStringToPool: key name too long" followed by "Error while parsing text
# KeyValues for resource workshopitem", which is what a full multi-paragraph
# commit message produces once newlines are folded into \n.
#
# Usage: vdf_fit <max_escaped_chars> <text>
vdf_fit() {
  local max=$1 text=$2 esc n
  [ -n "$text" ] || { printf ''; return; }

  esc=$(vdf_escape "$text")
  if [ "${#esc}" -le "$max" ]; then
    printf '%s' "$text"
    return
  fi

  # Escaping can grow a string, so start well inside the budget and shrink.
  n=$(( max / 2 ))
  while [ "$n" -gt 0 ]; do
    esc=$(vdf_escape "${text:0:n} [truncated]")
    if [ "${#esc}" -le "$max" ]; then
      printf '%s' "${text:0:n} [truncated]"
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
