#!/usr/bin/env bash
set -euo pipefail

# Update script for the `deepseek-harness-git` (dsh, built from git release
# tags) package.
#
# Unlike the npm-tarball deepseek-harness package, the source of truth is the
# upstream `dsh-v*` tag sequence (pre-releases such as 0.1.2-alpha.1 often
# never reach npm). An update must:
#   1. resolve the tag and its commit into `version` + `rev` in hashes.json
#   2. recompute srcHash (the GitHub tag tarball hash)
#   3. refresh the pinned pnpm when upstream bumps `packageManager`
#   4. recompute pnpmDepsHash via a sacrificial build with a dummy hash
#      (harvested from Nix's fixed-output hash-mismatch error)

usage() {
  echo "Usage: $(basename "$0") [version]" >&2
  echo "       $(basename "$0") -f|--force <version>" >&2
}

force=false
repo_url="https://github.com/deepseek-ai/deepseek-harness"

latest_tag() {
  local tags
  tags="$(mktemp)"
  git ls-remote --tags "$repo_url" 'refs/tags/dsh-v*' > "$tags"
  local best_tag
  best_tag="$(grep -v '\^{}$' "$tags" | awk '{print substr($2, 11)}' | sort -V | tail -1)"
  if [ -z "$best_tag" ]; then
    rm -f "$tags"
    return 1
  fi
  # Prefer the peeled ^{} line so annotated tags yield the commit hash.
  local rev
  rev="$(awk -v t="refs/tags/$best_tag^{}" '$2 == t { print $1 }' "$tags")"
  [ -n "$rev" ] || rev="$(awk -v t="refs/tags/$best_tag" '$2 == t { print $1 }' "$tags")"
  rm -f "$tags"
  echo "${best_tag#dsh-v} $rev"
}

resolve_tag() {
  local want="$1" out rev
  out="$(git ls-remote "$repo_url" "refs/tags/dsh-v$want^{}" "refs/tags/dsh-v$want" || true)"
  rev="$(printf '%s\n' "$out" | awk '$2 ~ /\^/ { print $1; exit }')"
  [ -n "$rev" ] || rev="$(printf '%s\n' "$out" | awk '$2 !~ /\^/ { print $1; exit }')"
  [ -n "$rev" ] || return 1
  echo "$rev"
}

case "$#" in
  0)
    entry="$(latest_tag)" || { echo "Error: no dsh-v* tags found" >&2; exit 1; }
    version="${entry%% *}"
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
readme="$script_dir/README.md"
readme_zh="$script_dir/README_zh_CN.md"
current_version="$(sed -n 's/.*"version": *"\([^"]*\)",/\1/p' "$hashes_json")"
repo_root="$(cd -- "$script_dir" && git rev-parse --show-toplevel 2>/dev/null || echo "$script_dir/../../..")"

update_readme_versions() {
  sed -i -E "s|Current version: [0-9][^ ]*\.|Current version: $version.|" "$readme"
  sed -i -E "s|当前版本：[^。]+。|当前版本：$version。|" "$readme_zh"
}

if [ "$force" = false ] && [ "$current_version" = "$version" ]; then
  update_readme_versions
  echo "deepseek-harness-git is already at $version"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- 1. resolve the tag's commit ---
echo "Resolving tag dsh-v$version..."
rev="$(resolve_tag "$version" || true)"
if [ -z "$rev" ]; then
  echo "Error: tag dsh-v$version not found in $repo_url" >&2
  exit 1
fi
echo "rev: $rev"

# --- 2. prefetch the tag tarball for srcHash ---
echo "Prefetching source tarball hash..."
src_hash="$(nix --extra-experimental-features 'nix-command flakes' store prefetch-file --json \
    "https://codeload.github.com/deepseek-ai/deepseek-harness/tar.gz/$rev" \
    | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p')"
if [ -z "$src_hash" ]; then
  echo "Error: failed to extract srcHash" >&2
  exit 1
fi

# --- 3. refresh the pinned pnpm when upstream bumps packageManager ---
pnpm_version="$(sed -n 's/.*"pnpmVersion": *"\([^"]*\)".*/\1/p' "$hashes_json")"
upstream_pnpm="$(curl -fsSL "https://raw.githubusercontent.com/deepseek-ai/deepseek-harness/$rev/package.json" \
    | sed -n 's/.*"packageManager": *"pnpm@\([^"]*\)".*/\1/p')"
if [ -z "$upstream_pnpm" ]; then
  echo "Error: could not read packageManager from upstream package.json" >&2
  exit 1
fi
if [ "$upstream_pnpm" != "$pnpm_version" ]; then
  echo "Upstream pinned pnpm changed: $pnpm_version -> $upstream_pnpm; prefetching new hash..."
  pnpm_hash="$(nix --extra-experimental-features 'nix-command flakes' store prefetch-file --json \
      "https://registry.npmjs.org/pnpm/-/pnpm-$upstream_pnpm.tgz" \
      | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p')"
  if [ -z "$pnpm_hash" ]; then
    echo "Error: failed to prefetch pnpm-$upstream_pnpm.tgz" >&2
    exit 1
  fi
  pnpm_version="$upstream_pnpm"
else
  pnpm_hash="$(sed -n 's/.*"pnpmHash": *"\([^"]*\)".*/\1/p' "$hashes_json")"
fi

# --- 4. write version/rev/hashes, park a dummy pnpmDepsHash ---
DUMMY="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
cat > "$hashes_json" <<EOF
{
  "version": "$version",
  "rev": "$rev",
  "srcHash": "$src_hash",
  "pnpmDepsHash": "$DUMMY",
  "pnpmVersion": "$pnpm_version",
  "pnpmHash": "$pnpm_hash"
}
EOF

update_readme_versions

echo "Updated deepseek-harness-git to $version ($rev)"
echo "srcHash: $src_hash"
echo
echo "Now computing pnpmDepsHash via a build (this downloads all deps on first run)..."
echo "(pnpmDepsHash is currently a dummy; if this fails or you prefer, run manually:)"
echo "  cd '$repo_root' && nix build '.#deepseek-harness-git'"
echo

# --- 5. build once with the dummy hash to harvest the real pnpmDepsHash ---
build_log="$work/build.log"
if nix --extra-experimental-features 'nix-command flakes' build \
    "path:$repo_root#deepseek-harness-git" 2>"$build_log"; then
  echo "Build succeeded with the dummy hash (unexpected); pnpmDepsHash left as-is."
  exit 0
fi

got="$(grep -oE 'got:[[:space:]]*sha256-[A-Za-z0-9+/=]+' "$build_log" | head -1 | sed 's/.*sha256-/sha256-/')"
if [ -n "$got" ]; then
  sed -i -E "s|\"pnpmDepsHash\": \"[^\"]*\"|\"pnpmDepsHash\": \"$got\"|" "$hashes_json"
  echo "pnpmDepsHash: $got"
  echo "Verifying the final build..."
  if nix --extra-experimental-features 'nix-command flakes' build \
      "path:$repo_root#deepseek-harness-git" -o "$work/result" 2>>"$build_log"; then
    echo "deepseek-harness-git fully updated to $version."
  else
    echo "Final build failed; see log below." >&2
    tail -30 "$build_log" >&2
    exit 1
  fi
else
  echo "Could not harvest pnpmDepsHash automatically. Build output below." >&2
  echo "Fix the 'got:' hash or run the manual command above and paste the value into hashes.json." >&2
  sed -n '/error: hash mismatch/,$p' "$build_log" >&2
  exit 1
fi
