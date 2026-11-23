#!/usr/bin/env bash
#
# Update an existing Steam Workshop item from a folder on disk.
#
# Inputs arrive as environment variables rather than being interpolated into
# this script by the caller, so a changenote or path can never be executed as
# shell code.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

: "${INPUT_USERNAME:?username input is required}"
: "${INPUT_APPID:?appId input is required}"
: "${INPUT_PUBLISHEDFILEID:?publishedFileId input is required}"
: "${INPUT_PATH:?path input is required}"
change_note=${INPUT_CHANGENOTE:-}

test -n "${INPUT_CONFIGVDF:-}" \
  || die "configVdf is empty - set it from a repository secret containing your SteamCMD config.vdf"

require_numeric appId "$INPUT_APPID"
require_numeric publishedFileId "$INPUT_PUBLISHEDFILEID"

# SteamCMD needs an absolute content folder.
case "$INPUT_PATH" in
  /*) content=$INPUT_PATH ;;
  *)  content=${GITHUB_WORKSPACE:-$PWD}/$INPUT_PATH ;;
esac
test -d "$content" || die "path '$INPUT_PATH' is not a directory (resolved to '$content')"
test -n "$(ls -A "$content")" || die "path '$INPUT_PATH' is empty; refusing to publish an empty item"

steamcmd=${STEAMCMD:-${STEAMCMD_DIR:-${RUNNER_TEMP:-/tmp}/steamcmd}/steamcmd.sh}
test -x "$steamcmd" || die "SteamCMD not found at '$steamcmd'; run the install step first"

steam_home=${STEAM_HOME:-$HOME/Steam}
work=${RUNNER_TEMP:-/tmp}

# Restore the SteamCMD login session, so a password never reaches CI.
install -d -m 700 "$steam_home/config"
printf '%s' "$INPUT_CONFIGVDF" > "$steam_home/config/config.vdf"
chmod 600 "$steam_home/config/config.vdf"

# Verify the session before touching the item, so an expired Steam Guard
# session is reported as a login problem rather than a failed upload.
echo "Verifying SteamCMD login for '$INPUT_USERNAME'"
"$steamcmd" +login "$INPUT_USERNAME" +quit > "$work/steam-login.log" 2>&1 || true
cat "$work/steam-login.log"
if grep -qiE "FAILED login|Login Failure|Invalid Password|two-factor" "$work/steam-login.log"; then
  die "SteamCMD login failed - the configVdf session has most likely expired. Regenerate it (see the action README)."
fi

manifest="$work/workshop-manifest.vdf"
vdf_manifest "$INPUT_APPID" "$INPUT_PUBLISHEDFILEID" "$content" "$change_note" > "$manifest"
echo "Generated manifest:"
cat "$manifest"

echo "Uploading to Workshop item $INPUT_PUBLISHEDFILEID"
log="$work/steam-upload.log"
set +e
"$steamcmd" +login "$INPUT_USERNAME" +workshop_build_item "$manifest" +quit 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}
set -e

# SteamCMD's exit code alone is not trustworthy, so a success line is required
# too: a silent no-op would otherwise register as a published update.
if [ "$rc" -ne 0 ] || ! grep -qiE "Success|update successful" "$log"; then
  echo "SteamCMD logs:"
  for f in "$steam_home/logs"/*.txt; do
    [ -f "$f" ] || continue
    printf -- '----- %s\n' "$f"
    cat "$f"
  done
  die "Workshop upload failed (SteamCMD exit $rc)"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "manifest=$manifest" >> "$GITHUB_OUTPUT"
fi
echo "Workshop item $INPUT_PUBLISHEDFILEID updated."
