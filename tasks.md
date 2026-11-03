# Tasks

## This Week

- [x] M1: `SpringBoardSession` connects to the device (lockdown + property_list_service) and implements `getIconState` / `getHomeScreenIconMetrics`
  - Did not use the sbservices wrapper: it doesn't expose icon metrics, so every command sends plists directly
- [x] M1: `PlistBridge`: libplist ⇄ binary plist ⇄ `PropertyListSerialization`
- [x] M1: `iconctl device`, `iconctl dump --raw [--save x.plist]`
- [x] M1: `scripts/dev/m1-verify.sh` + `compare_raw.py` (self-tested against an old backup)
- [x] M1: 2026-10-31 read-only verification on a real device passed: main phone (iPhone17,3, iOS 27.2). An independent read matched: 6 top-level lists (including the Dock), 437 entries, output MATCH.
  - Two USB devices were detected and the original verify script stopped because no UDID was given; the comparison was finished by passing the same main phone to both Swift and Python by hand. The script still needs a UDID option.
  - Grid: home screen 4×6, Dock 4, folders 3×3. The raw JSON and binary plist are saved in `/tmp/ios-home-screen-m1.3WPsRN/` (temporary verification files).
  - Reading metrics from the other USB device failed; nothing was written to any device.

- [x] Wi-Fi connection: device lookup includes both USB and network, preferring USB when plugged in; the same phone appearing on both USB and Wi-Fi is no longer reported as several devices. 2026-11-02 on a real device (main phone), with USB unplugged, `device`, `dump` and a no-op `plan` (same hash before and after) all worked over Wi-Fi; nothing was written.
  - When the phone locks it disappears from the Wi-Fi device list; unlock it and try again.
  - 2026-11-02 `apply` over Wi-Fi: Muse moved from page 2 to the end of page 1 and landed in the right place, but `verified: false`. Cause: after the write, SpringBoard added 3 apps that had only been in the App Library (TikTok, Youku, WeType) back to page 2, in Muse's old spot. None of the earlier backups contain these 3 apps. Backup: `2026-11-02T14-18-19Z.plist`.
  - Second `apply` over Wi-Fi the same day: moved those 3 apps to the end of page 3, `verified: true`, and no apps were added back this time. Backup: `2026-11-02T14-36-48Z.plist`.
- [ ] Find out why SpringBoard adds App Library-only apps back to the home screen after setIconState, and whether `apply` should report this case separately instead of only returning `verified: false`

- [x] Portable binary: `scripts/build-deps.sh` builds libimobiledevice 1.4.0, libplist 2.8.0, libimobiledevice-glue 1.3.3, libusbmuxd 2.1.1, libtatsu 1.0.5 and OpenSSL 3.5.9 as static universal libraries; `scripts/build.sh` links them into a universal `iconctl` with minimum macOS 13. `otool -L` shows only OS libraries (libcurl, Foundation, CryptoKit, Swift runtime). Both slices start (`--version`, x86_64 via Rosetta).
  - [x] 2026-11-03 verified against the phone over USB on both slices (x86_64 via Rosetta): `device`, `dump` (441 entries, identical on both) and a no-op `plan` (same hash, nothing moved or removed). Nothing was written.
  - The first build used mbedTLS 3.6.7 and failed every connection with `lockdownd error -5` (SSL): mbedTLS rejects the empty subject names in the pairing certificates macOS creates (`parsing root cert failed: -0x23E0`). Switched to OpenSSL, as Homebrew uses.
  - [ ] Over Wi-Fi with the new binary
  - [ ] Not yet tested on an Intel Mac or on macOS older than 27
- [x] Ship the binary: `skill/bin/` is no longer gitignored and `skill/bin/iconctl` (15 MB, universal, ad-hoc signed) is committed. SKILL.md tells the agent to ask for a reinstall if it is missing instead of building. Rule: rebuild and commit the binary together with any `iconctl/` change.
  - [ ] Developer ID signing and notarization, if the binary is ever downloaded outside git (browser downloads are quarantined by Gatekeeper)
- [x] Install with `npx skills add` only. The `.claude-plugin/marketplace.json` marketplace was added and then removed on 2026-11-03; the README documents only npx (plus `scripts/install.sh` for development).
- [x] 2026-11-04 listed as its own plugin in `Dreamon-im/ai-agent-plugin` (Claude Code and Codex marketplaces). Installs from GitHub tested with npx, Claude Code and Codex; `bin/iconctl` stays executable in all three. After changing `skill/` here, rsync it into `plugins/iphone-home-screen/skills/iphone-home-screen/` there and bump both `plugin.json` versions.
- [x] Folder edits no longer repack the whole folder: removing an app only changes its own page (dropped if empty), and inserting only carries over into following pages while a page is full. Two new tests; 14 pass.
  - 2026-11-03 on the phone over USB: Carro moved from "To Hide 1" (folder page 4) to the end of SGLife. Plan: 1 requested move, 1 incidental (Cathay Pacific, one spot left on the same page), 0 removed; before the fix it was 70 incidental. `verified: true`. Backup: `2026-11-03T13-59-05Z.plist`.
- [x] Merged `fix/smart-stack-widgets`: entries with `elements` (Smart Stacks) decode as widgets named "Smart Stack". 15 tests pass. 2026-11-03 rebuilt binary checked over Wi-Fi on both slices (`device`, `dump`, no-op `plan`); this phone has no Smart Stacks, so the fix itself is covered only by its unit test.
- [x] Renamed to `iphone-home-screen`: GitHub repo `Dreamon-im/iphone-home-screen` (old URL redirects), skill name, `install.sh`. The backup folder keeps the old name so existing backups still restore. History squashed to one commit before the rename (local backup tag `backup/pre-squash-2026-11-03`).
- [ ] Move the test fixtures into the repo (they read `/tmp` and the uv cache today), trimmed and with fake app names

## Backlog

- [x] M2: IconCore data model, stable IDs, offloaded/unknown classification, folder pagination, five operations and positions, transactional rollback, capacity/widget validation, separating requested moves from incidental shifts, state hash and stale-base protection. All 12 `swift test` tests pass.
- [x] M2: Wired up the read-only CLI: `dump`, `render`, `find`, `plan`. 2026-10-31 read-only preview on a real device of moving Gemini into the Google folder: the diff was 1 requested move, 8 incidental shifts, 0 removals; nothing was written.
- [x] M2: Position JSON in `plan` now uses stable forms such as `page:N` and `folder:Name@...`.
- [x] M3: Implemented `apply`, `backups`, `restore`, `snapshot`. 2026-10-31 on a real device: an unchanged write-back, moving Gemini to the first spot on page 1, then restoring from the automatic backup; the final positions matched those before the move.
  - `setIconState` returns no plist, so it now sends without waiting for a reply.
  - Reading right after a write can time out briefly, so three short retries were added; the restore result was confirmed by a separate query afterwards.
- [x] M4: Wrote SKILL.md, two references, build.sh and install.sh. 2026-10-31 the release build succeeded and was installed via symlinks `~/.agents/skills` → `~/.claude/skills`.
- [x] M5: Wrote the README covering build, install and backups.

## Done

- [x] M0: `brew install libimobiledevice pkgconf` (libimobiledevice 1.4.0_2)
- [x] M0: git init, directory skeleton, `.gitignore`
- [x] M0: Swift Package (systemLibrary + swift-argument-parser 1.8.2), `swift build` / `swift test` pass
- [x] M0: `iconctl devices` can call libimobiledevice
