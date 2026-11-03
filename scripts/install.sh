#!/bin/zsh
set -euo pipefail

root=${0:A:h:h}
name=iphone-home-screen
agents="$HOME/.agents/skills/$name"
claude="$HOME/.claude/skills/$name"

if [[ -e $agents && ! -L $agents ]]; then
  printf 'Refusing to replace existing directory: %s\n' "$agents" >&2
  exit 1
fi
ln -sfn "$root/skill" "$agents"

mkdir -p "${claude:h}"
if [[ -e $claude && ! -L $claude ]]; then
  printf 'Refusing to replace existing directory: %s\n' "$claude" >&2
  exit 1
fi
ln -sfn "$agents" "$claude"
printf 'Installed %s -> %s -> %s\n' "$claude" "$agents" "$root/skill"
