# Steam Workshop Upload

A GitHub Action that updates an existing Steam Workshop item with SteamCMD.

It is a **composite** action: SteamCMD is installed and run directly on the runner, not
inside a container. That is the whole point of this action — see
[Why not a container](#why-not-a-container).

```yaml
- uses: frenchua/steam-workshop-upload@v1
  with:
    username: ${{ secrets.STEAM_USERNAME }}
    configVdf: ${{ secrets.STEAM_CONFIG_VDF }}
    appId: '294100'
    publishedFileId: '3456789012'
    path: staging
    changeNote: ${{ github.event.head_commit.message }}
```

## Inputs

| Input | Required | Description |
| --- | --- | --- |
| `username` | yes | Steam account name that owns the Workshop item. |
| `configVdf` | yes | Contents of SteamCMD's `config/config.vdf` from a login that cleared Steam Guard. Always pass a secret. |
| `appId` | yes | Steam AppID the item belongs to (`294100` for RimWorld). |
| `publishedFileId` | yes | Numeric id of the existing Workshop item to update. |
| `path` | yes | Folder whose contents become the item. Relative paths resolve against the workspace. |
| `changeNote` | no | Changenote for the update. Multi-line text is escaped for you, and shortened if needed (see below). |

### Outputs

| Output | Description |
| --- | --- |
| `manifest` | Path to the generated `manifest.vdf`, useful for debugging. |


### Changenote length

SteamCMD's KeyValues parser aborts on an over-long string, logging
`AddStringToPool: key name too long` and then `Error while parsing text KeyValues for
resource workshopitem`. A full multi-paragraph commit message passed as `changeNote` is
enough to trigger it, so the changenote is shortened to about 1000 characters, marked
`[truncated]`, and a warning is written to the job log. Override the budget with the
`CHANGENOTE_MAX_CHARS` environment variable if you need to.

## Requirements

- A Linux or macOS runner. Windows runners are rejected with a clear error.
- An item that **already exists** on the Workshop. This action updates items; it does not
  create them. Create it once by hand, then put its id in `publishedFileId`.
- The contents of `path` are uploaded as-is, so stage a clean folder first. Nothing is
  filtered out — a stray `.git` directory would be published.

## Authentication

SteamCMD is given a pre-authorized login session so a password and Steam Guard code never
reach CI:

1. Run `steamcmd +login <username> <password> +quit` locally and enter the Steam Guard code.
2. Run `steamcmd +login <username> +quit` again and confirm it no longer prompts.
3. Copy the contents of SteamCMD's `config/config.vdf` into a repository secret, e.g.
   `STEAM_CONFIG_VDF`. Pass it raw — it is not base64-encoded.
4. Store the account name in a second secret, e.g. `STEAM_USERNAME`.

If the session later expires, run `steamcmd +set_steam_guard_code <code>` locally and replace
the secret with the new `config.vdf`. The action verifies the login **before** touching the
Workshop item, so an expired session fails with a login error rather than a broken upload.

Never commit `config.vdf`: it is a credential equivalent to a logged-in session.

## Why not a container

Docker 29.4.2, shipped on GitHub's `ubuntu-26.04` runner image, denies the `socketcall(2)`
multiplexer in its default seccomp profile (hardening against an AF_ALG filter bypass).
SteamCMD is a 32-bit binary, and 32-bit glibc routes every `socket()` call through
`socketcall`, so inside a container SteamCMD loses all networking and aborts its self-update
with:

```
Steamcmd needs to be online to update. Please confirm your network connection and try again.
```

A Docker-based action cannot pass `--security-opt` for itself, so the only fixes available to
a containerized action are host-side: pin the runner to an older image, or change the Docker
daemon's default seccomp profile. Running SteamCMD on the host avoids container seccomp
entirely, so this action keeps working on `ubuntu-latest` whatever Docker version the image
carries. See [steamcmd/docker#93](https://github.com/steamcmd/docker/issues/93) and
[moby/moby#52506](https://github.com/moby/moby/issues/52506).

## Limitations

These are SteamCMD's, not this action's:

- Workshop **tags** cannot be set. Existing tags survive an update, but new ones must be
  added by hand on the Workshop page.
- The **preview image** is not re-uploaded.
- The item **title and description** are untouched, which is deliberate: renaming an item on
  the Workshop page is not reverted by a later upload.

## Design notes

- Inputs reach the scripts as environment variables rather than being interpolated into a
  `run:` body, so a changenote containing shell metacharacters cannot be executed.
- Changenotes are escaped for VDF: backslashes are doubled, quotes escaped, newlines folded
  into `\n`. A changenote cannot close the string and inject manifest keys.
- Success requires both a zero exit code **and** a success line in SteamCMD's output, because
  SteamCMD's exit code alone is not reliable and a silent no-op would otherwise look like a
  published update.
- An empty content folder is refused rather than published.
- On failure, `~/Steam/logs/*.txt` is dumped into the job log.

## Development

```sh
shellcheck -x scripts/*.sh tests/*.sh
bash tests/test-lib.sh      # VDF escaping and validation helpers
bash tests/test-publish.sh  # full publish path against a stub SteamCMD (needs Linux/macOS)
```

CI additionally installs SteamCMD for real on both `ubuntu-latest` and `ubuntu-24.04` to
confirm the native install keeps working as runner images change.

## License

MIT — see [LICENSE](LICENSE).
