#!/usr/bin/env bash
# Update startlive to the latest version tagged on GitHub.
#
# Upstream publishes its PyPI sdist from a workflow that requires a manual
# approval, so PyPI can lag the GitHub release by days. The release tag is used
# as the source instead; it carries everything the build needs.
#
# This script updates:
#   1. version + hash in package.nix
#   2. the vendored PyQtDarkTheme-fork, if upstream raised its requirement
#   3. the version line in both READMEs
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") [version]" >&2
  echo "       $(basename "$0") -f|--force <version>" >&2
}

force=false
case "$#" in
  0)
    version=""
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

if [ -n "$version" ]; then
  case "$version" in
    *[!0-9A-Za-z._-]*)
      echo "Error: version must only contain letters, numbers, dots, underscores, or hyphens" >&2
      exit 1
      ;;
  esac
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_nix="$script_dir/package.nix"
fork_nix="$script_dir/pyqtdarktheme-fork.nix"
readme="$script_dir/README.md"
readme_zh="$script_dir/README_zh_CN.md"
flake_root="$(cd "$script_dir/../../../.." && pwd)"

die() { echo "Error: $*" >&2; exit 1; }
nix_cmd() { nix --extra-experimental-features 'nix-command flakes' "$@"; }

# The GitHub API rejects unauthenticated requests once its rate limit is hit,
# so the latest release is resolved from the `/releases/latest` redirect
# instead, which needs no API call at all.
curl_gh() { curl -fsSL -H "User-Agent: nix-packages-update" "$@"; }

# --- 1. Resolve the target version and its dependency metadata ---------------

# Tags are authoritative: upstream releases on GitHub first and only later
# pushes the same tree to PyPI.
if [ -z "$version" ]; then
  latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
    "https://github.com/Radekyspec/StartLive/releases/latest")" \
    || die "failed to resolve the latest release from GitHub"
  version="${latest_url##*/}"
  version="${version#v}"
fi
[ -n "$version" ] || die "failed to resolve the latest release from GitHub"

repo_raw="https://raw.githubusercontent.com/Radekyspec/StartLive/$version"

# Older tags predate `pyproject.toml` and are not installable as a package at
# all, so refuse them early instead of failing later in the build.
curl_gh "$repo_raw/requirements.txt" >/dev/null \
  || die "startlive $version has no requirements.txt; it predates pyproject.toml and cannot be built from the tag"

# Upstream pins PyQtDarkTheme-fork with `~=`. That package is not in nixpkgs,
# so it is vendored next to this one and has to move in lockstep: a stale pin
# fails the runtime dependency check at build time.
fork_version="$(curl_gh "$repo_raw/requirements.txt" | python3 -c '
import re, sys
for line in sys.stdin:
    match = re.match(r"PyQtDarkTheme-fork\s*~=\s*([0-9][^;,\s]*)", line, re.I)
    if match:
        print(match.group(1))
        break
')"
fork_version="${fork_version//[[:space:]]/}"
[ -n "$fork_version" ] || die "startlive $version no longer requires PyQtDarkTheme-fork; the vendored package can be dropped"

update_readme_versions() {
  sed -i -E "s|Current version: [0-9][^ ]*\.|Current version: $version.|" "$readme"
  sed -i -E "s|当前版本：[^。]+。|当前版本：$version。|" "$readme_zh"
}

current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' "$package_nix" | head -n1)"
current_fork_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' "$fork_nix" | head -n1)"

if [ "$force" = false ] && [ "$current_version" = "$version" ] \
    && [ "$current_fork_version" = "$fork_version" ]; then
  update_readme_versions
  echo "startlive is already at $version"
  exit 0
fi

# --- 2. Prefetch the source hashes ------------------------------------------

prefetch_hash() {
  local url="$1" hash
  hash="$(nix_cmd store prefetch-file --json "$url" \
    | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p')"
  [ -n "$hash" ] || die "failed to prefetch $url"
  printf '%s' "$hash"
}

src_url="https://github.com/Radekyspec/StartLive/archive/refs/tags/${version}.tar.gz"
src_hash="$(nix_cmd store prefetch-file --json --unpack "$src_url" \
  | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p')"
[ -n "$src_hash" ] || die "failed to prefetch $src_url"

# PyPI serves the file under the distribution's original underscore name.
fork_src_url="https://files.pythonhosted.org/packages/source/p/pyqtdarktheme_fork/pyqtdarktheme_fork-${fork_version}.tar.gz"
fork_hash=""
if [ "$current_fork_version" != "$fork_version" ]; then
  fork_hash="$(prefetch_hash "$fork_src_url")"
fi

# --- 3. Rewrite the version/hash pins ---------------------------------------

sed -i -E \
  -e "s|version = \"[^\"]+\";|version = \"$version\";|" \
  -e "s|hash = \"[^\"]+\";|hash = \"$src_hash\";|" \
  "$package_nix"

if [ -n "$fork_hash" ]; then
  sed -i -E \
    -e "s|version = \"[^\"]+\";|version = \"$fork_version\";|" \
    -e "s|hash = \"[^\"]+\";|hash = \"$fork_hash\";|" \
    "$fork_nix"
fi

update_readme_versions

# --- 4. Verify ---------------------------------------------------------------

echo "Verifying with a build..."
( cd "$flake_root" && nix build .#startlive --no-link )

echo ""
echo "Updated startlive to $version"
echo "src hash: $src_hash"
if [ -n "$fork_hash" ]; then
  echo "Updated PyQtDarkTheme-fork to $fork_version"
  echo "fork hash: $fork_hash"
fi
