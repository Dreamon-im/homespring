#!/bin/zsh
# Builds libimobiledevice and its dependencies from pinned source releases as
# static, universal (arm64 + x86_64) libraries, so the release iconctl binary
# does not load anything from Homebrew at run time.
#
# Output: .deps/universal/{include,lib}, plus a pkg-config file that
# scripts/build.sh points SwiftPM at. Safe to re-run; finished steps are skipped.
#
# TLS uses OpenSSL, like Homebrew's libimobiledevice. mbedTLS does not work:
# its X.509 parser rejects the empty subject names in the pairing certificates
# macOS creates, so every lockdown session fails with an SSL error.
set -euo pipefail

root=${0:A:h:h}
deps="$root/.deps"
min_macos=13.0
archs=(arm64 x86_64)
jobs=$(sysctl -n hw.ncpu)

# name version url sha256 (checksums match the Homebrew formulae / upstream releases)
packages=(
  "openssl 3.5.9 https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz 603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a"
  "libplist 2.8.0 https://github.com/libimobiledevice/libplist/releases/download/2.8.0/libplist-2.8.0.tar.bz2 b1f59f7634c58b2481325a23ff4e3bf51574a42d868cbe466d2b39b04550752a"
  "libimobiledevice-glue 1.3.3 https://github.com/libimobiledevice/libimobiledevice-glue/releases/download/1.3.3/libimobiledevice-glue-1.3.3.tar.bz2 920ce01382a32695f49b23292b4979a03f0afd16c58e8755d8b7f41804acc1a9"
  "libusbmuxd 2.1.1 https://github.com/libimobiledevice/libusbmuxd/releases/download/2.1.1/libusbmuxd-2.1.1.tar.bz2 5546f1aba1c3d1812c2b47d976312d00547d1044b84b6a461323c621f396efce"
  "libtatsu 1.0.5 https://github.com/libimobiledevice/libtatsu/releases/download/1.0.5/libtatsu-1.0.5.tar.bz2 536fa228b14f156258e801a7f4d25a3a9dd91bb936bf6344e23171403c57e440"
  "libimobiledevice 1.4.0 https://github.com/libimobiledevice/libimobiledevice/releases/download/1.4.0/libimobiledevice-1.4.0.tar.bz2 23cc0077e221c7d991bd0eb02150a0d49199bcca1ddf059edccee9ffd914939d"
)

mkdir -p "$deps/downloads"

archive() {
  local name=$1 version=$2 url=$3
  print -r -- "$deps/downloads/$name-$version.${${url:t}#*.tar.}"
}

fetch() {
  local name=$1 version=$2 url=$3 sha=$4
  local file=$(archive "$name" "$version" "$url")
  if [[ ! -f $file ]]; then
    printf 'Downloading %s %s\n' "$name" "$version"
    curl -fsSL -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  if [[ $(shasum -a 256 "$file" | cut -d' ' -f1) != "$sha" ]]; then
    printf 'Checksum mismatch for %s; deleting it.\n' "$file" >&2
    rm -f "$file"
    exit 1
  fi
}

# Extracts a fresh copy of a package into the per-arch source directory and prints its path.
unpack() {
  local name=$1 version=$2 url=$3 arch=$4
  local src="$deps/build/$arch/src"
  mkdir -p "$src"
  rm -rf "$src/$name-$version"
  tar -xf "$(archive "$name" "$version" "$url")" -C "$src"
  print -r -- "$src/$name-$version"
}

build_arch() {
  local arch=$1
  local prefix="$deps/build/$arch/prefix"
  local host build=aarch64-apple-darwin ossl_target
  [[ $(uname -m) == x86_64 ]] && build=x86_64-apple-darwin
  case $arch in
    arm64) host=aarch64-apple-darwin; ossl_target=darwin64-arm64-cc ;;
    x86_64) host=x86_64-apple-darwin; ossl_target=darwin64-x86_64-cc ;;
  esac

  local sdk="$(xcrun --sdk macosx --show-sdk-path)"
  # Target flags live in CC so that no configure script can drop them by
  # overwriting CFLAGS during a feature check.
  export CC="$(xcrun -f clang) -arch $arch -isysroot $sdk -mmacosx-version-min=$min_macos"
  export CFLAGS="-O2"
  export CPPFLAGS="-I$prefix/include"
  export LDFLAGS="-L$prefix/lib"
  # Only our own prefix: never pick up Homebrew's copies.
  export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
  export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
  local common=(--prefix="$prefix" --host="$host" --build="$build" --disable-shared --enable-static --disable-dependency-tracking --silent)

  local entry name version url dir
  for entry in $packages; do
    read -r name version url _ <<< "$entry"
    if [[ -f "$prefix/.done-$name-$version" ]]; then
      continue
    fi
    printf 'Building %s %s for %s\n' "$name" "$version" "$arch"
    dir=$(unpack "$name" "$version" "$url" "$arch")
    case $name in
      openssl)
        # Built in place and copied by hand, so no path on this Mac ends up in
        # the binary. The OPENSSLDIR below doesn't exist on users' Macs, so no
        # config file is loaded at run time; providers are built in (no-module).
        (cd "$dir" && env -u CFLAGS -u CPPFLAGS -u LDFLAGS ./Configure "$ossl_target" \
          no-shared no-module no-tests no-docs no-apps \
          --prefix=/opt/homespring-openssl --openssldir=/opt/homespring-openssl/ssl >/dev/null \
          && make -s -j"$jobs" build_libs >/dev/null)
        mkdir -p "$prefix/lib" "$prefix/include"
        cp "$dir"/lib{crypto,ssl}.a "$prefix/lib/"
        cp -R "$dir/include/openssl" "$prefix/include/"
        ;;
      libplist)
        (cd "$dir" && ./configure $common --without-cython --without-tests && make -s -j"$jobs" >/dev/null && make -s install >/dev/null)
        ;;
      libtatsu)
        # libcurl comes from the macOS SDK, which ships no pkg-config file for it.
        (cd "$dir" && libcurl_CFLAGS=" " libcurl_LIBS="-lcurl" ./configure $common && make -s -j"$jobs" >/dev/null && make -s install >/dev/null)
        ;;
      libimobiledevice)
        (cd "$dir" && openssl_CFLAGS="-I$prefix/include" openssl_LIBS="-L$prefix/lib -lssl -lcrypto" \
          ./configure $common --without-cython && make -s -j"$jobs" >/dev/null && make -s install >/dev/null)
        ;;
      *)
        (cd "$dir" && ./configure $common && make -s -j"$jobs" >/dev/null && make -s install >/dev/null)
        ;;
    esac
    touch "$prefix/.done-$name-$version"
  done
}

for entry in $packages; do
  fetch ${=entry}
done
for arch in $archs; do
  build_arch "$arch"
done

# Merge the per-arch static libraries into universal ones.
universal="$deps/universal"
rm -rf "$universal"
mkdir -p "$universal/lib/pkgconfig"
cp -R "$deps/build/${archs[1]}/prefix/include" "$universal/include"
libs=(imobiledevice-1.0 usbmuxd-2.0 tatsu imobiledevice-glue-1.0 plist-2.0 ssl crypto)
for lib in $libs; do
  inputs=()
  for arch in $archs; do
    inputs+=("$deps/build/$arch/prefix/lib/lib$lib.a")
  done
  lipo -create $inputs -output "$universal/lib/lib$lib.a"
done

# One pkg-config file for SwiftPM's CIMobileDevice system library. Static archives
# need every dependency listed explicitly, in link order.
cat > "$universal/lib/pkgconfig/libimobiledevice-1.0.pc" <<EOF
prefix=$universal
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libimobiledevice (static, universal)
Description: libimobiledevice and dependencies built by scripts/build-deps.sh
Version: 1.4.0
Libs: -L\${libdir} ${(j: :)${(@)libs/#/-l}} -lcurl
Cflags: -I\${includedir}
EOF

printf 'Built universal static libraries in %s\n' "$universal"
lipo -info "$universal/lib/libimobiledevice-1.0.a"
