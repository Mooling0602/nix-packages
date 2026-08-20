#!/usr/bin/env bash
set -euo pipefail

# Update script for the `deepseek-harness` (dsh) package.
#
# Unlike static binary packages, dsh is built from an npm tarball via
# buildNpmPackage, so an update must:
#   1. bump `version` in hashes.json
#   2. regenerate package-lock.json for the new version
#   3. recompute sourceHash (the npm tarball hash)
#   4. recompute npmDepsHash (the hash of the installed node_modules tree)
#
# npmDepsHash cannot be prefetched directly: it is the hash of what
# `npm install` produces, which is only known after a build. We therefore
# write a dummy hash, run `nix build`, and harvest the real value from the
# fixed-output hash-mismatch error reported by Nix (same trick as
# numtide/llm-agents.nix).

usage() {
  echo "Usage: $(basename "$0") [version]" >&2
  echo "       $(basename "$0") -f|--force <version>" >&2
}

force=false

latest_version() {
  curl -fsSL "https://registry.npmjs.org/@deepseek-ai%2fdsh/latest" \
    | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p'
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
hashes_json="$script_dir/hashes.json"
lockfile="$script_dir/package-lock.json"
readme="$script_dir/README.md"
readme_zh="$script_dir/README_zh_CN.md"
current_version="$(sed -n 's/.*"version": *"\([^"]*\)",/\1/p' "$hashes_json")"
repo_root="$(cd -- "$script_dir" && git rev-parse --show-toplevel 2>/dev/null || echo "$script_dir/../../..")"

update_readme_versions() {
  sed -i -E "s|Current version: [0-9][^ ]*\.|Current version: $version.|" "$readme"
  sed -i -E "s|当前版本：[^。]+。|当前版本：$version。|" "$readme_zh"
}

src_url="https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${version}.tgz"

if [ "$force" = false ] && [ "$current_version" = "$version" ]; then
  update_readme_versions
  echo "deepseek-harness is already at $version"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- 1. prefetch the npm tarball for sourceHash ---
echo "Prefetching npm tarball hash..."
src_hash="$(nix --extra-experimental-features 'nix-command flakes' store prefetch-file --json "$src_url" \
  | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p')"
if [ -z "$src_hash" ]; then
  echo "Error: failed to extract sourceHash for $src_url" >&2
  exit 1
fi

# --- 2. regenerate package-lock.json for the new version ---
# Use a private npm cache so stale/root-owned ~/.npm does not interfere.
echo "Regenerating package-lock.json (this fetches registry metadata)..."
mkdir -p "$work/pkg" "$work/npmcache"
curl -fsSL "$src_url" -o "$work/dsh.tgz"
tar -xzf "$work/dsh.tgz" -C "$work/pkg" --strip-components=1
(
  cd "$work/pkg"
  npm install --package-lock-only --ignore-scripts --no-audit --no-fund \
    --cache "$work/npmcache"
)
cp "$work/pkg/package-lock.json" "$lockfile"

# --- 3. write version + sourceHash, park a dummy npmDepsHash ---
DUMMY="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
cat > "$hashes_json" <<EOF
{
  "version": "$version",
  "sourceHash": "$src_hash",
  "npmDepsHash": "$DUMMY"
}
EOF

update_readme_versions

echo "Updated deepseek-harness to $version"
echo "sourceHash: $src_hash"
echo
echo "Now computing npmDepsHash via a build (this downloads all $version deps on first run)..."
echo "(npmDepsHash is currently a dummy; if this fails or you prefer, run manually:)"
echo "  cd '$repo_root' && nix build '.#deepseek-harness'"
echo

# --- 4. build once with the dummy hash to harvest the real npmDepsHash ---
build_log="$work/build.log"
if nix --extra-experimental-features 'nix-command flakes' build \
    "path:$repo_root#deepseek-harness" 2>"$build_log"; then
  echo "Build succeeded with the dummy hash (unexpected); npmDepsHash left as-is."
  exit 0
fi

got="$(grep -oE 'got:[[:space:]]*sha256-[A-Za-z0-9+/=]+' "$build_log" | head -1 | sed 's/.*sha256-/sha256-/')"
if [ -n "$got" ]; then
  cat > "$hashes_json" <<EOF
{
  "version": "$version",
  "sourceHash": "$src_hash",
  "npmDepsHash": "$got"
}
EOF
  echo "npmDepsHash: $got"
  echo "deepseek-harness fully updated to $version."
else
  echo "Could not harvest npmDepsHash automatically. Build output below." >&2
  echo "Fix the 'got:' hash or run the manual command above and paste the value into hashes.json." >&2
  sed -n '/error: hash mismatch/,$p' "$build_log" >&2
  exit 1
fi
