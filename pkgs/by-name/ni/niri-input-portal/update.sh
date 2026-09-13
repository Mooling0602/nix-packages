#!/usr/bin/env bash
# Update niri-input-portal to the latest commit of upstream main.
#
# This script updates:
#   1. src rev + version (unstable-<commit-date>) in package.nix
#   2. the src fetchFromGitHub hash
#   3. the cargoHash (by running the build twice)
#   4. the commit reference in both READMEs
set -euo pipefail

# --- Optional GitHub API authentication to avoid rate limiting --------------
# Export GITHUB_PAT (a GitHub personal access token) to authenticate GitHub
# REST / raw requests. GITHUB_TOKEN is honoured as a fallback.
gh_auth=()
if [ -n "${GITHUB_PAT:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
  gh_auth=(-H "Authorization: Bearer ${GITHUB_PAT:-${GITHUB_TOKEN:-}}")
fi

repo_api="https://api.github.com/repos/Qingswe/niri-input-portal"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_nix="$script_dir/package.nix"
readme="$script_dir/README.md"
readme_zh="$script_dir/README_zh_CN.md"
flake_root="$(cd "$script_dir/../../../.." && pwd)"

die() { echo "Error: $*" >&2; exit 1; }

# --- 1. Resolve the latest main HEAD commit ---------------------------------

head_json="$(curl -fsSL "${gh_auth[@]}" "$repo_api/commits/main")" || die "failed to fetch main HEAD"
new_rev="$(printf '%s' "$head_json" | sed -n 's/.*"sha": *"\([0-9a-f]\{40\}\)".*/\1/p' | head -n1)"
commit_date="$(printf '%s' "$head_json" | sed -n 's/.*"date": *"\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)T[^"]*".*/\1/p' | head -n1)"

[ -n "$new_rev" ] || die "failed to extract commit sha"
[ -n "$commit_date" ] || die "failed to extract commit date"

new_version="unstable-$commit_date"

update_readme_rev() {
  # Match the 40-hex SHA itself rather than the surrounding prose: the
  # English sentence is wrapped across two lines, so a line-based `sed` on
  # that phrase can silently miss it.
  perl -pi -e 's/`[0-9a-f]{40}`/`'"$new_rev"'`/g' "$readme" "$readme_zh"
}

# --- 2. Compare with the current pin ------------------------------------------

current_rev="$(sed -n 's/^[[:space:]]*rev = "\([0-9a-f]\{40\}\)";/\1/p' "$package_nix" | head -n1)"

# An unchanged revision still needs a pass while the cargoHash placeholder is
# unfilled (a freshly added package, or a manual revert).
cargo_hash_pending=0
grep -q 'cargoHash = lib\.fakeHash' "$package_nix" && cargo_hash_pending=1

if [ "$current_rev" = "$new_rev" ] && [ "$cargo_hash_pending" -eq 0 ]; then
  update_readme_rev
  echo "niri-input-portal is already at $new_rev ($new_version)"
  exit 0
fi

# --- 3. Prefetch the source tarball hash --------------------------------------

src_hash="$(
  # --unpack is required: it hashes the normalised unpacked tree, which is what
  # fetchFromGitHub produces. A plain file prefetch hashes the tarball bytes
  # instead and will never match the src hash in package.nix.
  nix --extra-experimental-features nix-command store prefetch-file --unpack --json \
    "https://github.com/Qingswe/niri-input-portal/archive/$new_rev.tar.gz" \
    | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p'
)"
[ -n "$src_hash" ] || die "failed to prefetch source hash"

# --- 4. Update rev, version and src hash (by exact line matching) -------------

python3 - "$package_nix" "$new_rev" "$new_version" "$src_hash" <<'PY'
import re, sys
path, rev, ver, h = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
text = open(path).read()
pairs = [
    (r'(rev = )"[0-9a-f]{40}"', r'\1"' + rev + '"'),
    # The only bare "unstable-…" version pin in the file.
    (r'(version = )"unstable-[0-9-]+"', r'\1"' + ver + '"'),
    # The source hash: first hash inside the niri-input-portal fetchFromGitHub.
    (r'(repo = "niri-input-portal";\n    inherit rev;\n    hash = )"[^"]+"', r'\1"' + h + '"'),
]
for pattern, repl in pairs:
    text, n = re.subn(pattern, repl, text, count=1)
    if n != 1:
        sys.exit(f"failed to rewrite pattern: {pattern}")
open(path, "w").write(text)
PY

# --- 5. Recompute the cargoHash (build twice) ---------------------------------

echo "Rebuilding to discover the cargoHash (first run is expected to fail)..."
# This build is expected to fail, so capture its log first: under `set -e`
# plus `pipefail`, a failing command substitution aborts the script before the
# hash can be extracted and before the guidance below can print.
build_log="$( cd "$flake_root" && nix build .#niri-input-portal --no-link 2>&1 )" || true
cargo_hash="$( printf '%s\n' "$build_log" | grep -oE 'got: +sha256-[A-Za-z0-9+/=]+' | sed 's/got: *//' | head -n1 )" || true

# Guard against writing a source hash into cargoHash: when the failure is the
# src fixed-output derivation, the prefetch in step 3 disagrees with what
# fetchFromGitHub computes, and the extracted hash is not the crate hash.
if printf '%s\n' "$build_log" | grep -qE "hash mismatch in fixed-output derivation '.*-source\.drv'"; then
  die "prefetched src hash does not match fetchFromGitHub; aborting before cargoHash is overwritten"
fi
if [ -z "$cargo_hash" ]; then
  echo "Warning: could not capture the cargoHash automatically." >&2
  echo "Run: nix build .#niri-input-portal" >&2
  echo "and substitute the 'got:' hash into cargoHash in $package_nix." >&2
  update_readme_rev
  exit 1
fi

python3 - "$package_nix" "$cargo_hash" <<'PY'
import re, sys
path, h = sys.argv[1], sys.argv[2]
text = open(path).read()
# Accepts both the lib.fakeHash placeholder and an already substituted hash.
text, n = re.subn(r'(cargoHash = )(?:"[^"]+"|lib\.fakeHash)', r'\1"' + h + '"', text, count=1)
if n != 1:
    sys.exit("failed to rewrite cargoHash")
open(path, "w").write(text)
PY

echo "cargoHash: $cargo_hash"
echo "Verifying with a second build..."
( cd "$flake_root" && nix build .#niri-input-portal --no-link )

update_readme_rev

echo ""
echo "Updated niri-input-portal to $new_rev ($new_version)"
echo "src hash: $src_hash"
