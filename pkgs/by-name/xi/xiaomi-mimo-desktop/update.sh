#!/usr/bin/env bash
# Update xiaomi-mimo-desktop to the latest upstream release.
#
# Upstream only links the Windows and macOS installers on its download page.
# The official Linux build exists only as a versioned Debian package on the
# download CDN, with no `latest` alias and no update feed, so there is nothing
# authoritative to probe for the newest version. Version discovery therefore
# reads the AUR `mimo-desktop` package metadata, which tracks exactly this
# artifact, and then verifies that the versioned CDN URL actually responds
# before any hash is computed. When the AUR package lags behind or disappears,
# pass the version explicitly; the CDN URL pattern is documented in README.md.
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") [version]" >&2
  echo "       $(basename "$0") -f|--force <version>" >&2
}

force=false

# Newest version tracked by the AUR, from the RPC interface. The `Version`
# field carries an Arch `pkgrel` suffix (26.909.91205-1) that the download URL
# and `package.nix` do not use, so it is stripped.
latest_version() {
  local aur_version version

  if ! aur_version="$(curl -fsSL "https://aur.archlinux.org/rpc/v5/info?arg[]=mimo-desktop" \
    | sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' \
    | head -n 1)"; then
    echo "Error: failed to query the AUR for the latest xiaomi-mimo-desktop version" >&2
    exit 1
  fi

  version="$(printf '%s' "$aur_version" | sed -E 's/-[0-9]+$//')"

  if [ -z "$version" ]; then
    echo "Error: failed to extract the latest xiaomi-mimo-desktop version from the AUR response" >&2
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

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
package_nix="$script_dir/package.nix"
readme="$script_dir/README.md"
readme_zh="$script_dir/README_zh_CN.md"
current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' "$package_nix")"

# Update the version line in both the English and Chinese READMEs.
update_readme_versions() {
  sed -i -E "s|Current version: [0-9][^ ]*\.|Current version: $version.|" "$readme"
  sed -i -E "s|当前版本：[^。]+。|当前版本：$version。|" "$readme_zh"
}

src_url="https://mimocode-cdn.xiaomimimo.com/mimocode/mimodesktop/XiaomiMiMo-${version}-x64.deb"

if [ "$force" = false ] && [ "$current_version" = "$version" ]; then
  update_readme_versions
  echo "xiaomi-mimo-desktop is already at $version"
  exit 0
fi

# The URL is versioned, so a version the CDN does not carry (yet, or anymore)
# would otherwise only surface as a confusing prefetch failure.
if ! curl -fsIL "$src_url" -o /dev/null; then
  echo "Error: no upstream artifact at $src_url" >&2
  echo "The AUR-reported version may not be published on the CDN; pass the version manually." >&2
  exit 1
fi

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

update_readme_versions

echo "Updated xiaomi-mimo-desktop to $version"
echo "src hash: $src_hash"
