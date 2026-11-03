# iPhone Home Screen

A Claude Code skill and Swift CLI for organizing an iPhone home screen over USB or Wi-Fi. It can move apps, create and tidy folders, and find offloaded apps, and it produces a reviewable plan before anything is written to the phone.

## Install

With the skills CLI (Claude Code, Codex and other agents):

```bash
npx skills add Dreamon-im/iphone-home-screen
```

As a Claude Code plugin (this repo is also the `dreamon` plugin marketplace):

```
/plugin install iphone-home-screen --marketplace Dreamon-im/iphone-home-screen
```

On Claude Code older than 2.1.275, add the marketplace first:

```
/plugin marketplace add Dreamon-im/iphone-home-screen
/plugin install iphone-home-screen@dreamon
```

From a local clone, for development:

```bash
scripts/install.sh
```

`install.sh` links `skill/` to `~/.agents/skills/iphone-home-screen`, and that to `~/.claude/skills/iphone-home-screen`. Don't use both methods on the same Mac, or the skill loads twice.

No build step is needed either way: `skill/bin/iconctl` is a prebuilt universal (Apple silicon + Intel) binary committed to the repo. It runs on macOS 13 or later and loads nothing from Homebrew.

The iPhone must be unlocked and trust this Mac, and connected by USB. You can also connect it by USB once, turn on "Show this iPhone when on Wi-Fi" in Finder, and then use it wirelessly on the same Wi-Fi network. When the cable is plugged in, USB is used. Over Wi-Fi, a locked or sleeping iPhone disappears from the device list and `iconctl` reports that no device was found; unlock it and try again.

## Usage

```bash
skill/bin/iconctl devices
skill/bin/iconctl render --udid <UDID>
skill/bin/iconctl plan --udid <UDID> ops.json -o plan.json
skill/bin/iconctl apply --udid <UDID> plan.json
```

Every write goes through `plan` first. `apply` rechecks the state hash, saves a binary plist backup automatically, then writes and verifies the result. Backups and snapshots live in `~/Library/Application Support/homespring/`.

## Building iconctl

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
