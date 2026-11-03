# iPhone Home Screen

A Claude Code skill and Swift CLI for organizing an iPhone home screen over USB or Wi-Fi. It can move apps, create and tidy folders, and find offloaded apps, and it produces a reviewable plan before anything is written to the phone.

## Install

```bash
npx skills add Dreamon-im/iphone-home-screen
```

The CLI asks which agents (Claude Code, Codex and others) and which scope to install to. To skip the questions and install for Claude Code for your whole user account:

```bash
npx skills add Dreamon-im/iphone-home-screen -g --agent claude-code
```

No build step is needed: the skill ships a prebuilt universal (Apple silicon + Intel) `bin/iconctl` that runs on macOS 13 or later and needs nothing else installed.

Update or remove it with:

```bash
npx skills update
npx skills remove iphone-home-screen        # add -g if you installed with -g
```

Removing the skill keeps your home screen backups.

To install it as a Claude Code or Codex plugin instead, use the [Dreamon-im/ai-agent-plugin](https://github.com/Dreamon-im/ai-agent-plugin) marketplace, which hosts Dreamon's skills.

## Connect the iPhone

- Connect it by USB, unlock it, and tap Trust on the iPhone.
- For Wi-Fi, connect by USB once, select the iPhone in Finder, turn on "Show this iPhone when on Wi-Fi", and keep the Mac and iPhone on the same Wi-Fi network. When the cable is plugged in, USB is used.
- Over Wi-Fi, a locked or sleeping iPhone disappears and `iconctl` reports that no device was found. Unlock it and try again.

## Usage

Ask your agent in plain language, for example "move Carro into the SGLife folder" or "put all Chinese apps on page 3". The skill finds the apps, shows you the planned changes, and writes to the phone only after you confirm.

`iconctl` can also be run directly from the installed skill folder:

```bash
iconctl devices
iconctl render --udid <UDID>
iconctl plan --udid <UDID> ops.json -o plan.json
iconctl apply --udid <UDID> plan.json
```

Every write goes through `plan` first. `apply` rechecks the state hash, saves a binary plist backup automatically, then writes and verifies the result. Backups and snapshots live in `~/Library/Application Support/homespring/`.

## Development

To use the skill straight from a local clone, run:

```bash
scripts/install.sh
```

It links `skill/` to `~/.agents/skills/iphone-home-screen`, and that to `~/.claude/skills/iphone-home-screen`. Don't also install it with `npx skills add -g` on the same Mac, or the skill loads twice.

### Building iconctl

Only needed when changing `iconctl/`. Requires Xcode and `brew install pkgconf`.

```bash
scripts/build.sh
```

`build.sh` writes `skill/bin/iconctl`. On the first run it calls `scripts/build-deps.sh`, which downloads pinned, checksum-verified source releases of libimobiledevice, libplist, libimobiledevice-glue, libusbmuxd, libtatsu and OpenSSL 3.5 LTS, and builds them as static universal libraries in `.deps/` (about two minutes). It fails if the binary would load any library outside macOS.

**Whenever `iconctl/` changes, run `scripts/build.sh` and commit the new `skill/bin/iconctl` in the same commit**, so the shipped binary always matches the source.

For development, `swift build` and `swift test` inside `iconctl/` link Homebrew's libraries instead (`brew install libimobiledevice`).

## Design

`iconctl` handles reading, validation, planning and writing. The skill handles categorization, confirmation and showing the diff. One reorganization produces one plan and one write.

- Web clips use their stable `displayIdentifier`, not their URL, which may be duplicated.
- Folders with more than 9 items per page are paginated automatically.
- Stale plans are rejected once the state changes, so manual changes made on the phone are never overwritten.
- Backups are binary plists, which keep dates, binary data and unknown fields.
- Backups are stored in Application Support, not in the tool's install directory or a cache.

Verified so far: reading real layouts, offline layout tests, and on a real device an unchanged write-back, a single move, and restoring from a backup.
