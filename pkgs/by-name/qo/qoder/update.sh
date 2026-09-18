#!/usr/bin/env bash
# Update qoder to the latest upstream release.
#
# Upstream split Qoder into separate products and moved the standalone app to
# the electron-builder path `qoder-app/releases/<version>/`. The version has a
# Debian epoch (`1:0.3.3`) that the download path and `package.nix` do not use,
# so it is stripped.
#
# Version discovery cross-checks two sources, because either can go stale on
# its own: the changelog page, which embeds every release as JSON, and the
# `control` metadata behind the version-less `latest` download URL. The `latest`
# alias has already lagged behind — it kept serving 0.2.5 after 0.3.3 had
# shipped — which made this script report "already up to date" for an outdated
# package without any error.
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") [version]" >&2
  echo "       $(basename "$0") -f|--force <version>" >&2
}

force=false

# Version of the newest release on the changelog page. Each release is an
# embedded JSON object carrying `tag_name` and `published_at`, and the newest is
# the one with the greatest `published_at`. The page ships them in one long
# line, so the entries are split on their `{"id":"` prefix before sorting.
latest_version_from_changelog() {
  local page version

  page="$(mktemp "${TMPDIR:-/tmp}/qoder-changelog.XXXXXX")"
  if ! curl -fsSL "https://qoder.com/zh/changelog?type=app" -o "$page"; then
    rm -f "$page"
    echo "Error: failed to fetch the qoder changelog page" >&2
    return 1
  fi

  version="$(tr -d '\\' < "$page" \
    | sed 's/{"id":"/\n/g' \
    | grep -F '"type":"app"' \
    | sed -n 's/.*"tag_name":"\([^"]*\)".*"published_at":"\([^"]*\)".*/\2 \1/p' \
    | sort -r \
    | head -n 1 \
    | cut -d' ' -f 2 || true)"
  rm -f "$page"

  if [ -z "$version" ]; then
    echo "Error: failed to extract latest qoder version from the changelog page" >&2
    return 1
  fi

  printf '%s\n' "$version"
}

# Version of the artifact behind the version-less `latest` URL, read from the
# Debian control metadata. Only the first 64 KiB are fetched, which covers the
# leading `control.tar.xz` member of the archive; downloading the full ~200 MB
# package just to read one field would be absurd.
#
# The `control` Version is `1:0.3.3` (Debian epoch) while the release path and
# `package.nix` use the bare `0.3.3`, so everything up to the last colon is
# stripped.
latest_version_from_deb() {
  local tmpdir control_version version

  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/qoder-update.XXXXXX")"

  if ! curl -fsSL -r 0-65535 "https://download.qoder.com/qoder-app/releases/latest/Qoder-linux-amd64.deb" \
    -o "$tmpdir/qoder-head.deb"; then
    rm -rf "$tmpdir"
    echo "Error: failed to fetch latest qoder Debian package metadata" >&2
    return 1
  fi

  if ! control_version="$(ar p "$tmpdir/qoder-head.deb" control.tar.xz \
    | tar -xOJf - ./control \
    | sed -n 's/^Version: //p')"; then
    rm -rf "$tmpdir"
    echo "Error: failed to extract latest qoder version from Debian control metadata" >&2
    return 1
  fi
  rm -rf "$tmpdir"

  # Strip the Debian epoch (`1:0.3.3` -> `0.3.3`).
  version="${control_version##*:}"

  if [ -z "$version" ]; then
    echo "Error: failed to extract latest qoder version from Debian control metadata" >&2
    return 1
  fi

  printf '%s\n' "$version"
}

# Take the greater of the two sources rather than preferring one, so that a
# stale `latest` alias cannot hide a release published to the changelog.
latest_version() {
  local from_changelog from_deb

  from_changelog="$(latest_version_from_changelog || true)"
  from_deb="$(latest_version_from_deb || true)"

  if [ -z "$from_changelog" ] && [ -z "$from_deb" ]; then
    echo "Error: could not determine the latest qoder version from the changelog or the Debian metadata" >&2
    exit 1
  fi

  printf '%s\n' "$from_changelog" "$from_deb" | sed '/^$/d' | sort -V | tail -n 1
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
  echo "qoder is already at $version"
  exit 0
fi

src_url="https://download.qoder.com/qoder-app/releases/${version}/Qoder-linux-amd64.deb"

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

echo "Updated qoder to $version"
echo "src hash: $src_hash"
