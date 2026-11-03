---
name: iphone-home-screen
description: Organize the home screen of an iPhone connected over USB or Wi-Fi. Move apps, create or tidy folders, find offloaded apps, preview layout changes, back up and restore. Use when the user mentions iPhone icons, the home screen, folders, "page N", offloaded apps, or restoring a layout.
---

# iPhone Home Screen

Use `iconctl` for every deterministic operation. For categorization that needs subjective judgment, list the candidates first and write only after the user confirms.

## Setup

- The iPhone is unlocked and trusts this Mac, and is connected by USB; or "Show this iPhone when on Wi-Fi" is turned on in Finder and it is on the same Wi-Fi as the Mac. USB is preferred when plugged in.
- Over Wi-Fi, a locked or sleeping phone disappears from `iconctl devices`; ask the user to unlock it and try again.
- `iconctl` is the prebuilt binary at `bin/iconctl` in this skill's folder (universal, macOS 13 or later, no other installs needed). If it is missing, the skill install is incomplete: ask the user to reinstall the skill instead of trying to build it.
- With several devices, run `iconctl devices` first, then pass the same `--udid` to every device command.

## Workflow

1. Look at the pages with `iconctl render --udid <UDID>` and confirm IDs with `find`.
2. Write all operations to one JSON file and generate a plan with `iconctl plan --udid <UDID> ops.json`.
3. Show the user the requested moves, incidental shifts and removal count. Subjective categorizations must have their candidate list confirmed first.
4. Only after the user confirms, run `iconctl apply --udid <UDID> plan.json`.
5. Check for `verified: true`. On failure, report the automatic backup path and do not retry the write directly.

## Operation JSON

```json
[
  {"op":"move","id":"com.example.app","to":"page:1","position":"end"},
  {"op":"move","id":"com.example.bank","to":"folder:Banking","position":"sorted"},
  {"op":"swap","a":"com.example.one","b":"com.example.two"},
  {"op":"createFolder","page":3,"name":"China","ids":["com.example.one","com.example.two"]},
  {"op":"renameFolder","from":"Old","to":"New"},
  {"op":"sortFolder","name":"Google"}
]
```

`to` can be `dock`, `page:N` or `folder:Name`. `position` can be `end`, `start`, `sorted`, `before:<id>`, `after:<id>` or `index:N`.

## Rules

- Never skip `plan` and go straight to `apply`. Regenerate the plan when it is stale or the hash doesn't match.
- Show every `find` result; never pick between apps with the same name on your own.
- Never create operations that remove entries. System apps can't be uninstalled; folders can't be nested or placed in the Dock.
- Folders hold at most 9 items per page; the tool paginates automatically.
- `restore` creates a new backup first. Unless the user explicitly asks to restore, show the diff with `--dry-run` first.
- Backups and snapshots live in `~/Library/Application Support/homespring/`.

## Commands

`devices`, `device`, `dump`, `render`, `find`, `plan`, `apply`, `backups`, `restore`, `snapshot`. For fields and layout details see `references/icon-state-format.md`; for common organizing flows see `references/recipes.md`.
