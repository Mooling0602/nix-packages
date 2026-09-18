#!/usr/bin/env bash
# Update qoder-ide to the latest upstream release.
#
# Upstream renamed the IDE product from `qoder` to `qoder-ide` in 1.25.1 and
# moved the download path along with it. The pre-rename
# `release/latest/qoder_amd64.deb` URL still answers 200 but is frozen at 1.24.2,
# so probing it silently reported "already up to date" forever; discovery uses
# the renamed `release/latest/qoder-ide_amd64.deb` and the versioned download URL
# is `release/<version>/qoder-ide_amd64.deb`.
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") [version]" >&2
  echo "       $(basename "$0") -f|--force <version>" >&2
}

force=false

# Version of the artifact behind the version-less `latest` URL, read from the
# Debian control metadata. Only the first 64 KiB are fetched, which covers the
# leading `control.tar.xz` member of the archive; downloading the full ~180 MB
# package just to read one field would be absurd.
#
# The `control` Version carries a build timestamp suffix (1.30.1-1789452627)
# that the release path and `package.nix` do not use, so it is stripped.
latest_version() {
  local tmpdir control_version version

  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/qoder-ide-update.XXXXXX")"

  if ! curl -fsSL -r 0-65535 "https://download.qoder.com/release/latest/qoder-ide_amd64.deb" \
    -o "$tmpdir/qoder-ide-head.deb"; then
    rm -rf "$tmpdir"
    echo "Error: failed to fetch latest qoder-ide Debian package metadata" >&2
    exit 1
  fi

  if ! control_version="$(ar p "$tmpdir/qoder-ide-head.deb" control.tar.xz \
    | tar -xOJf - ./control \
    | sed -n 's/^Version: //p')"; then
    rm -rf "$tmpdir"
    echo "Error: failed to extract latest qoder-ide version from Debian control metadata" >&2
    exit 1
  fi
  rm -rf "$tmpdir"
  version="${control_version%%-*}"

  if [ -z "$version" ]; then
    echo "Error: failed to extract latest qoder-ide version from Debian control metadata" >&2
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
readme="$script_dir/README.md"
readme_zh="$script_dir/README_zh_CN.md"
current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' "$package_nix")"

# Update the version line in both the English and Chinese READMEs.
update_readme_versions() {
  sed -i -E "s|Current version: [0-9][^ ]*\.|Current version: $version.|" "$readme"
  sed -i -E "s|当前版本：[^。]+。|当前版本：$version。|" "$readme_zh"
}

if [ "$force" = false ] && [ "$current_version" = "$version" ]; then
  update_readme_versions
  echo "qoder-ide is already at $version"
  exit 0
fi

src_url="https://download.qoder.com/release/${version}/qoder-ide_amd64.deb"

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

echo "Updated qoder-ide to $version"
echo "src hash: $src_hash"
