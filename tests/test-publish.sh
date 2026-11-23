#!/usr/bin/env bash
# Integration tests for publish.sh, driven against a stub SteamCMD.
#
# The stub stands in for the real binary so the upload path, the login check
# and the failure handling can all be exercised without Steam credentials.
# Requires a POSIX filesystem (it checks file modes), so it runs on CI rather
# than on a Windows checkout.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
pass=0 fail=0

# Write a stub steamcmd.sh that behaves as $1 ("ok", "badlogin" or "badupload").
make_stub() {
  local mode=$1 dest=$2
  mkdir -p "$(dirname "$dest")"
  {
    echo '#!/usr/bin/env bash'
    echo "mode=$mode"
    echo 'printf "Logging in user to Steam Public..."'
    echo 'if [ "$mode" = badlogin ]; then echo "FAILED login with result code Expired"; exit 5; fi'
    echo 'echo OK'
    echo 'for a in "$@"; do'
    echo '  if [ "$a" = "+workshop_build_item" ]; then'
    echo '    if [ "$mode" = badupload ]; then'
    echo '      echo "ERROR! Failed to commit workshop builds"; exit 8'
    echo '    fi'
    echo '    echo "Success. Published file update successful"'
    echo '  fi'
    echo 'done'
    echo 'exit 0'
  } > "$dest"
  chmod +x "$dest"
}

# run_case <name> <mode> <expected exit> [extra env assignments...]
run_case() {
  local name=$1 mode=$2 want=$3; shift 3
  local work
  work=$(mktemp -d)
  mkdir -p "$work/home" "$work/temp" "$work/ws/staging"
  echo "a staged file" > "$work/ws/staging/About.xml"
  make_stub "$mode" "$work/temp/steamcmd/steamcmd.sh"

  local out got
  out=$(
    HOME="$work/home" \
    RUNNER_TEMP="$work/temp" \
    GITHUB_WORKSPACE="$work/ws" \
    GITHUB_OUTPUT="$work/gh-output" \
    STEAM_HOME="$work/home/Steam" \
    INPUT_USERNAME=someuser \
    INPUT_CONFIGVDF='"InstallConfigStore" { "token" "abc" }' \
    INPUT_APPID=294100 \
    INPUT_PUBLISHEDFILEID=3456789012 \
    INPUT_PATH=staging \
    INPUT_CHANGENOTE='Fix the "online" bug
second line' \
    "$@" \
    bash "$root/scripts/publish.sh" 2>&1
  )
  got=$?

  if [ "$got" -eq "$want" ]; then
    pass=$((pass + 1)); printf 'ok   %s (exit %d)\n' "$name" "$got"
  else
    fail=$((fail + 1)); printf 'FAIL %s: want exit %d, got %d\n%s\n' "$name" "$want" "$got" "$out"
  fi

  printf '%s' "$out" > "$work/out.log"
  LAST_WORK=$work
}

echo "== success path"
run_case "successful upload" ok 0
w=$LAST_WORK
if grep -q '"changenote" "Fix the \\"online\\" bug\\nsecond line"' "$w/temp/workshop-manifest.vdf"; then
  pass=$((pass + 1)); printf 'ok   %s\n' "manifest escapes the changenote"
else
  fail=$((fail + 1)); printf 'FAIL %s\n' "manifest changenote is wrong:"; cat "$w/temp/workshop-manifest.vdf"
fi
if grep -q "manifest=" "$w/gh-output"; then
  pass=$((pass + 1)); printf 'ok   %s\n' "manifest output is written"
else
  fail=$((fail + 1)); printf 'FAIL %s\n' "manifest output missing"
fi
mode=$(stat -c '%a' "$w/home/Steam/config/config.vdf" 2>/dev/null || echo unknown)
if [ "$mode" = 600 ]; then
  pass=$((pass + 1)); printf 'ok   %s\n' "config.vdf is mode 600"
else
  fail=$((fail + 1)); printf 'FAIL %s: config.vdf mode is %s, want 600\n' "credential permissions" "$mode"
fi

echo "== failure paths"
run_case "expired login is caught" badlogin 1
run_case "failed upload is caught" badupload 1

echo "== input validation"
run_case "non-numeric appId is rejected" ok 1 INPUT_APPID=29x4
run_case "empty publishedFileId is rejected" ok 1 INPUT_PUBLISHEDFILEID=
run_case "missing configVdf is rejected" ok 1 INPUT_CONFIGVDF=
run_case "nonexistent path is rejected" ok 1 INPUT_PATH=nope

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
