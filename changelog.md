# Changelog

## Unreleased

- Renamed from Homespring to `iphone-home-screen` (skill and GitHub repo). Backups stay in `~/Library/Application Support/homespring/`
- Installed with `npx skills add Dreamon-im/iphone-home-screen` only; Claude Code and Codex plugin installs moved to the `Dreamon-im/ai-agent-plugin` marketplace
- Smart Stacks are read as widgets. Previously they looked like empty folders and every plan on their page was refused with "Folder  is empty."
- Moving an app into or out of a folder only changes the pages it touches. Previously the whole folder was repacked into full pages of 9, shifting many unrelated apps
- The skill now ships a prebuilt `skill/bin/iconctl`, so installing the skill needs no build step
- `iconctl` release builds are universal (Apple silicon + Intel), run on macOS 13 or later, and no longer need Homebrew at run time: libimobiledevice and its dependencies are built from pinned sources and linked statically
- Wi-Fi support: when USB isn't plugged in, every device command connects to the iPhone over Wi-Fi automatically; `iconctl device` output gains a `connection` field
- Project skeleton: Swift Package `iconctl`, accessing the iPhone through libimobiledevice
- `iconctl devices`: lists connected devices as JSON
- `iconctl device`: device name, iOS version and home screen grid metrics
- `iconctl dump`: prints the actionable home screen inventory; `--raw` still prints the raw state
- `iconctl render`: prints estimated text grids
- `iconctl find`: finds entries by name or ID and returns every match
- `iconctl plan`: validates a batch of operations and prints the diff without writing to the device
- IconCore: move, swap, create folder, rename, sort, capacity and widget validation, state hash
- `iconctl apply`: checks the plan hash, backs up automatically, writes and verifies
- `iconctl backups` / `restore` / `snapshot`: manage plists in `~/Library/Application Support/homespring/`
- Added the `iphone-home-screen` skill, operation references, and build/install scripts
- Added a README covering build, install and backups
