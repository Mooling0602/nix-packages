#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") [version]" >&2
  echo "       $(basename "$0") -f|--force <version>" >&2
}

force=false

latest_version() {
  curl -fsSL "https://api.github.com/repos/Mystic-Stars/Axolotl/releases/latest" \
    | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p'
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
readme="$script_dir/README.md"
current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' "$package_nix")"

if [ "$force" = false ] && [ "$current_version" = "$version" ]; then
  sed -i -E "s|当前版本：[^。]+。|当前版本：$version。|" "$readme"
  echo "axolotl-launcher-bin is already at $version"
  exit 0
fi

src_url="https://github.com/Mystic-Stars/Axolotl/releases/download/v${version}/Axolotl.Launcher_${version}_amd64.deb"

src_hash="$(nix --extra-experimental-features 'nix-command flakes' store prefetch-file --json "$src_url" \
  | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p')"

if [ -z "$src_hash" ]; then
  echo "Error: failed to extract hash for $src_url" >&2
  exit 1
fi

sed -i -E \
  -e "s|version = \"[^\"]+\";|version = \"$version\";|" \
  -e "s|hash = \"[^\"]+\";|hash = \"$src_hash\";|" \
  "$package_nix"

sed -i -E "s|当前版本：[^。]+。|当前版本：$version。|" "$readme"

echo "Updated axolotl-launcher-bin to $version"
echo "src hash: $src_hash"
