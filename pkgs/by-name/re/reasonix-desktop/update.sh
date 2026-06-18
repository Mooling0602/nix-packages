#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $(basename "$0") <version>" >&2
  exit 1
fi

version="$1"

case "$version" in
  ''|*[!0-9A-Za-z._-]*)
    echo "Error: version must only contain letters, numbers, dots, underscores, or hyphens" >&2
    exit 1
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_nix="$script_dir/package.nix"
app_icon_url="https://raw.githubusercontent.com/esengine/DeepSeek-Reasonix/desktop-v${version}/desktop/build/appicon.png"
src_url="https://github.com/esengine/DeepSeek-Reasonix/releases/download/desktop-v${version}/Reasonix-linux-amd64.tar.gz"

prefetch_hash() {
  nix --extra-experimental-features nix-command store prefetch-file --json "$1" \
    | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p'
}

app_icon_hash="$(prefetch_hash "$app_icon_url")"
src_hash="$(prefetch_hash "$src_url")"

if [ -z "$app_icon_hash" ]; then
  echo "Error: failed to extract hash for $app_icon_url" >&2
  exit 1
fi

if [ -z "$src_hash" ]; then
  echo "Error: failed to extract hash for $src_url" >&2
  exit 1
fi

sed -i -E \
  -e "s|version = \"[^\"]+\";|version = \"$version\";|" \
  -e "/raw\.githubusercontent\.com/,/};/s|hash = \"[^\"]+\";|hash = \"$app_icon_hash\";|" \
  -e "/releases\/download/,/};/s|hash = \"[^\"]+\";|hash = \"$src_hash\";|" \
  "$package_nix"

echo "Updated reasonix-desktop to $version"
echo "app icon hash: $app_icon_hash"
echo "src hash: $src_hash"
