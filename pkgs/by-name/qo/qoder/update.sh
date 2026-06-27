#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") [version]" >&2
  echo "       $(basename "$0") -f|--force <version>" >&2
}

force=false

latest_version() {
  local tmpdir control_version version

  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/qoder-update.XXXXXX")"

  if ! curl -fsSL -r 0-65535 "https://download.qoder.com/release/latest/qoder_amd64.deb" \
    -o "$tmpdir/qoder-head.deb"; then
    rm -rf "$tmpdir"
    echo "Error: failed to fetch latest qoder Debian package metadata" >&2
    exit 1
  fi

  if ! control_version="$(ar p "$tmpdir/qoder-head.deb" control.tar.xz \
    | tar -xOJf - ./control \
    | sed -n 's/^Version: //p')"; then
    rm -rf "$tmpdir"
    echo "Error: failed to extract latest qoder version from Debian control metadata" >&2
    exit 1
  fi
  rm -rf "$tmpdir"
  version="${control_version%%-*}"

  if [ -z "$version" ]; then
    echo "Error: failed to extract latest qoder version from Debian control metadata" >&2
    exit 1
  fi

  printf '%s\n' "$version"
}

case "$#" in
  0)
    version="$(latest_version)"
    ;;
  1)
    case "$1" in
      -f|--force)
        usage
        exit 1
        ;;
      *)
        version="$1"
        ;;
    esac
    ;;
  2)
    case "$1" in
      -f|--force)
        force=true
        version="$2"
        ;;
      *)
        usage
        exit 1
        ;;
    esac
    ;;
  *)
    usage
    exit 1
    ;;
esac

case "$version" in
  ''|*[!0-9A-Za-z._-]*)
    echo "Error: version must only contain letters, numbers, dots, underscores, or hyphens" >&2
    exit 1
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_nix="$script_dir/package.nix"
current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' "$package_nix")"

if [ "$force" = false ] && [ "$current_version" = "$version" ]; then
  echo "qoder is already at $version"
  exit 0
fi

src_url="https://download.qoder.com/release/${version}/qoder_amd64.deb"

prefetch_hash() {
  nix --extra-experimental-features nix-command store prefetch-file --json "$1" \
    | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p'
}

src_hash="$(prefetch_hash "$src_url")"

if [ -z "$src_hash" ]; then
  echo "Error: failed to extract hash for $src_url" >&2
  exit 1
fi

sed -i -E \
  -e "s|version = \"[^\"]+\";|version = \"$version\";|" \
  -e "s|hash = \"[^\"]+\";|hash = \"$src_hash\";|" \
  "$package_nix"

echo "Updated qoder to $version"
echo "src hash: $src_hash"
