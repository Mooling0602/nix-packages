#!/usr/bin/env bash
set -euo pipefail

# Update script for the `reasonix-desktop` package.
#
# Upstream `esengine/DeepSeek-Reasonix` publishes several independent release
# lines from different branches, each with its own tag namespace:
#
#   desktop-v*    the 1.x desktop app (branch `main-v2`)  <- this package
#   studio-v*     the 2.x Studio desktop app
#   v*, npm-v*    the 2.x CLI / npm package
#
# Only `desktop-v*` is relevant here: Studio is a different upstream product
# and would be packaged separately, so this script must not be pointed at
# `studio-v*` to "keep up" with it.
#
# GitHub's repository-wide "latest" release is whichever line happened to
# publish most recently, so `/releases/latest` now resolves to a `studio-v*`
# (or `v*`) tag and the previous check failed with
#   "latest release tag does not match desktop-v<version>"
# whenever the desktop line was not the newest of them. Version discovery
# therefore lists the `desktop-v*` tags directly with `git ls-remote`, which is
# also exempt from the REST API rate limit that `check-updates.sh` would run
# into when it executes every package's update script in one go.
#
# A tag can exist before (or entirely without) its GitHub Release assets, so
# the newest tags are probed in descending order and the first one whose Linux
# tarball actually resolves is used.

usage() {
  echo "Usage: $(basename "$0") [version]" >&2
  echo "       $(basename "$0") -f|--force <version>" >&2
}

repo_url="https://github.com/esengine/DeepSeek-Reasonix"
asset_name="Reasonix-linux-amd64.tar.gz"
# How many of the newest `desktop-v*` tags to probe before giving up. Keeps the
# runtime bounded when several recent tags have no published release assets.
max_probes=10

force=false
auto=false

asset_url() {
  printf '%s/releases/download/desktop-v%s/%s\n' "$repo_url" "$1" "$asset_name"
}

icon_url() {
  printf 'https://raw.githubusercontent.com/esengine/DeepSeek-Reasonix/desktop-v%s/desktop/build/appicon.png\n' "$1"
}

# Succeed only if the given asset URL is downloadable. A tag whose release
# assets were never uploaded answers 404, which `curl -f` turns into a failure.
release_asset_exists() {
  curl -fsIL -o /dev/null -- "$1" 2>/dev/null
}

# All `desktop-v<X.Y.Z>` tag versions, oldest first. Pre-release tags such as
# `desktop-v1.40.0-rc.1` are skipped on purpose: they are not releases, and
# version-sorting them against the plain `X.Y.Z` tags would rank them above the
# stable version they precede.
list_desktop_versions() {
  git ls-remote --tags --refs "$repo_url" 'refs/tags/desktop-v*' \
    | sed -n 's|^[[:xdigit:]]*[[:space:]]*refs/tags/desktop-v\(.*\)$|\1|p' \
    | grep -Ex '[0-9]+(\.[0-9]+)+' \
    | sort -V
}

# Newest published desktop release: walk the tags from newest to oldest and
# stop at the first one whose Linux tarball is actually downloadable.
latest_version() {
  local versions candidate probes=0
  versions="$(list_desktop_versions || true)"
  if [ -z "$versions" ]; then
    echo "Error: found no desktop-v* tag at $repo_url (network failure, or upstream renamed the desktop line)" >&2
    return 1
  fi

  while IFS= read -r candidate; do
    if release_asset_exists "$(asset_url "$candidate")"; then
      printf '%s\n' "$candidate"
      return 0
    fi
    probes=$((probes + 1))
    if [ "$probes" -ge "$max_probes" ]; then
      break
    fi
  done < <(printf '%s\n' "$versions" | sort -Vr)

  echo "Error: none of the $probes newest desktop-v* tags publishes $asset_name" >&2
  return 1
}

case "$#" in
  0)
    version="$(latest_version)"
    auto=true
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
  echo "reasonix-desktop is already at $version"
  exit 0
fi

src_url="$(asset_url "$version")"
app_icon_url="$(icon_url "$version")"

# An explicitly requested version was not probed above; check it now so a typo
# or an unpublished release fails here with a clear message instead of as an
# opaque prefetch error below.
if [ "$auto" = false ] && ! release_asset_exists "$src_url"; then
  echo "Error: no $asset_name published for desktop-v$version" >&2
  echo "       $src_url" >&2
  exit 1
fi

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

update_readme_versions

echo "Updated reasonix-desktop to $version"
echo "app icon hash: $app_icon_hash"
echo "src hash: $src_hash"
