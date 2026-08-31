#!/usr/bin/env bash
set -euo pipefail

# --- Optional GitHub API authentication to avoid rate limiting --------------
# Export GITHUB_PAT (a GitHub personal access token) to authenticate GitHub
# REST / raw requests. GITHUB_TOKEN is honoured as a fallback.
gh_auth=()
if [ -n "${GITHUB_PAT:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
  gh_auth=(-H "Authorization: Bearer ${GITHUB_PAT:-${GITHUB_TOKEN:-}}")
fi

usage() {
  echo "Usage: $(basename "$0") [version]" >&2
  echo "       $(basename "$0") -f|--force <version>" >&2
}

force=false

latest_version() {
  local tag
  tag="$(curl -fsSL "${gh_auth[@]}" "https://api.github.com/repos/esengine/DeepSeek-Reasonix/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')"

  case "$tag" in
    desktop-v*)
      printf '%s\n' "${tag#desktop-v}"
      ;;
    *)
      echo "Error: latest release tag does not match desktop-v<version>: $tag" >&2
      exit 1
      ;;
  esac
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
  echo "reasonix-desktop is already at $version"
  exit 0
fi

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

update_readme_versions

echo "Updated reasonix-desktop to $version"
echo "app icon hash: $app_icon_hash"
echo "src hash: $src_hash"
