# Icon State Format

`dump` prints the actionable inventory. `dump --raw` prints SpringBoard's raw state, with dates shown as ISO-8601 and binary data as Base64. `--save` also writes a binary plist that keeps the original types.

## Identifiers

- Apps use `bundleIdentifier` when present, otherwise `displayIdentifier`.
- Web clips always use `displayIdentifier`, never the URL. Shortcuts with the same URL are still separate entries.
- Folders use their exact display name. When names are duplicated the operation is refused rather than guessing the target.
- `installed` entries have both a bundle identifier and a bundle version. `offloaded` entries are missing one of them. Entries where neither gives a stable ID are marked `unknown`.

## Positions

Positions are encoded as `dock`, `page:N` or `folder:Name@page:N/folderPage:N`. Indexes start at 0 and rows and columns at 1. Positions are estimated from icon order and widget footprints; they are not device coordinates.

## Preserved fields

Edits only change entry order and folder structure. Dates, binary fields, unknown keys and widget fields must be kept as they are. Widgets support only `small`, `medium` and `large`; a plan is refused when a size is missing or different.
