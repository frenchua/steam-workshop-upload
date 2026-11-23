#!/usr/bin/env bash
#
# Download Valve's SteamCMD and run it once to bootstrap itself.
#
# SteamCMD is deliberately installed and run on the runner rather than in a
# container. Docker 29.4.2 (shipped on GitHub's ubuntu-26.04 runner image)
# denies socketcall(2) in its default seccomp profile; SteamCMD is a 32-bit
# binary and 32-bit glibc routes every socket() through socketcall, so in a
# container it loses all networking and aborts with "Steamcmd needs to be
# online to update". See steamcmd/docker#93.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

: "${RUNNER_OS:=Linux}"
steamcmd_dir=${STEAMCMD_DIR:-${RUNNER_TEMP:-/tmp}/steamcmd}

case "$RUNNER_OS" in
  Linux)  archive=steamcmd_linux.tar.gz ;;
  macOS)  archive=steamcmd_osx.tar.gz ;;
  *)      die "unsupported runner OS '$RUNNER_OS' - this action supports Linux and macOS runners" ;;
esac

if [ "$RUNNER_OS" = Linux ]; then
  # Valve ships SteamCMD as a 32-bit x86 binary. The GitHub runner images
  # already carry the 32-bit runtime; installing it explicitly means an image
  # that ever drops i386 fails here with a clear message rather than inside
  # SteamCMD, where the symptom is an unrelated-looking network error.
  if ! dpkg -s lib32gcc-s1 >/dev/null 2>&1; then
    echo "Installing 32-bit runtime (lib32gcc-s1)"
    sudo dpkg --add-architecture i386
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends lib32gcc-s1 \
      || die "could not install lib32gcc-s1; SteamCMD needs a 32-bit runtime on this runner"
  fi
fi

mkdir -p "$steamcmd_dir"
echo "Downloading $archive to $steamcmd_dir"
curl -sSfL "https://steamcdn-a.akamaihd.net/client/installer/$archive" \
  | tar --no-same-owner -xzf - -C "$steamcmd_dir" \
  || die "could not download or unpack $archive"

steamcmd="$steamcmd_dir/steamcmd.sh"
test -f "$steamcmd" || die "$steamcmd is missing after unpacking $archive"
chmod +x "$steamcmd"

# The first run bootstraps and self-updates. It can exit non-zero even when it
# has succeeded, so only a second consecutive failure is treated as fatal.
echo "Bootstrapping SteamCMD"
"$steamcmd" +quit || "$steamcmd" +quit \
  || die "SteamCMD failed to bootstrap. If this says it needs to be online, the runner is blocking its self-update."

if [ -n "${GITHUB_ENV:-}" ]; then
  echo "STEAMCMD=$steamcmd" >> "$GITHUB_ENV"
fi
echo "SteamCMD ready at $steamcmd"
