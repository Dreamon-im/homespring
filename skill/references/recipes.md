# Recipes

## Move into an existing folder

1. Use `find` to confirm both the app and the target folder.
2. Generate a plan with a single `move` operation: `{"op":"move","id":"...","to":"folder:Banking","position":"sorted"}`.
3. Show the diff. After confirmation, `apply` and check `verified`.

## Create folders by category

First build a candidate list with `render` and `find`. Give the user each candidate app's name, ID and current folder to confirm. After confirmation, move all IDs at once with one `createFolder` operation; don't write each app separately.

## Find installed apps sitting in To Hide

After `dump`, filter for entries whose container starts with `folder:To Hide` and whose `installState` is `installed`. Show them grouped by name and wait for the user to choose which IDs to move out.

## Restore

Run `backups` first, then `restore --dry-run` for the chosen ID. Drop `--dry-run` only after the user confirms. A restore writes a new backup before anything else.
