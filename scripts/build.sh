#!/bin/zsh
# Builds a universal (arm64 + x86_64) release iconctl into skill/bin/.
# libimobiledevice and its dependencies are linked statically from .deps/
# (built by scripts/build-deps.sh), so the binary needs nothing from Homebrew.
set -euo pipefail

root=${0:A:h:h}
pc_dir="$root/.deps/universal/lib/pkgconfig"
scratch="$root/iconctl/.build/dist"

if [[ ! -f $pc_dir/libimobiledevice-1.0.pc ]]; then
  "$root/scripts/build-deps.sh"
fi

# SwiftPM reads PKG_CONFIG_PATH before its default paths, so the static
# universal libraries win over any Homebrew copies.
export PKG_CONFIG_PATH="$pc_dir"

args=(--package-path "$root/iconctl" --scratch-path "$scratch" -c release --arch arm64 --arch x86_64)
swift build $args
binary="$(swift build $args --show-bin-path)/iconctl"
if [[ $(lipo -archs "$binary") != *arm64* || $(lipo -archs "$binary") != *x86_64* ]]; then
  printf 'Expected a universal binary, got: %s\n' "$(lipo -archs "$binary")" >&2
  exit 1
fi

mkdir -p "$root/skill/bin"
cp "$binary" "$root/skill/bin/iconctl"
chmod 755 "$root/skill/bin/iconctl"

# Fail if anything outside the OS would be loaded at run time.
if otool -L "$root/skill/bin/iconctl" | grep -E '^\s' | grep -vE '^\s+(/usr/lib/|/System/Library/)'; then
  printf 'iconctl links a library outside the OS (see above).\n' >&2
  exit 1
fi

printf 'Built %s (%s)\n' "$root/skill/bin/iconctl" "$(lipo -archs "$root/skill/bin/iconctl")"
