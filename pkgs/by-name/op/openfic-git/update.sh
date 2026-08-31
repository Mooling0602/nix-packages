#!/usr/bin/env bash
# Update openfic-git to the latest commit of OpenFic's main branch.
#
# This script updates:
#   1. src rev + version (unstable-<commit-date>) in package.nix
#   2. the embedded pnpm tarball pin when upstream changes packageManager
#   3. the pnpmDeps FOD hash (by running the build twice)
#   4. version strings in both READMEs
set -euo pipefail

# --- Optional GitHub API authentication to avoid rate limiting --------------
# Export GITHUB_PAT (a GitHub personal access token) to authenticate GitHub
# REST / raw requests. GITHUB_TOKEN is honoured as a fallback.
gh_auth=()
if [ -n "${GITHUB_PAT:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
  gh_auth=(-H "Authorization: Bearer ${GITHUB_PAT:-${GITHUB_TOKEN:-}}")
fi

repo_api="https://api.github.com/repos/syrizelink/OpenFic"
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

# --- 2. Read pinned tooling from desktop/package.json at that commit ---------

pkg_json="$(curl -fsSL "${gh_auth[@]}" "https://raw.githubusercontent.com/syrizelink/OpenFic/$new_rev/desktop/package.json")" \
  || die "failed to fetch desktop/package.json at $new_rev"
app_version="$(printf '%s' "$pkg_json" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -n1)"
pnpm_version="$(printf '%s' "$pkg_json" | sed -n 's/.*"packageManager": *"pnpm@\([^"]*\)".*/\1/p' | head -n1)"

[ -n "$app_version" ] || die "failed to extract app version"
[ -n "$pnpm_version" ] || die "failed to extract packageManager pnpm version"

# --- 3. Compare with the current pin ------------------------------------------

current_rev="$(sed -n 's/^[[:space:]]*rev = "\([0-9a-f]\{40\}\)";/\1/p' "$package_nix" | head -n1)"

new_version="unstable-$commit_date"

update_readme_versions() {
  sed -i -E "s|Following upstream main at \`[^\`]+\`\.|Following upstream main at \`$new_rev\`.|" "$readme"
  sed -i -E "s|跟踪上游 main 分支：\`[^\`]+\`。|跟踪上游 main 分支：\`$new_rev\`。|" "$readme_zh"
}

if [ "$current_rev" = "$new_rev" ]; then
  update_readme_versions
  echo "openfic-git is already at $new_rev ($new_version, app $app_version)"
  exit 0
fi

# --- 4. Prefetch the source tarball hash --------------------------------------

src_hash="$(
  nix --extra-experimental-features nix-command store prefetch-file --json \
    "https://github.com/syrizelink/OpenFic/archive/$new_rev.tar.gz" \
    | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p'
)"
[ -n "$src_hash" ] || die "failed to prefetch source hash"

# --- 5. Update rev, version and src hash (by exact line matching) -------------

python3 - "$package_nix" "$new_rev" "$new_version" "$src_hash" <<'PY'
import re, sys
path, rev, ver, h = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
text = open(path).read()
pairs = [
    (r'(rev = )"[0-9a-f]{40}"', r'\1"' + rev + '"'),
    # The only bare "unstable-…" version pin; the FOD inherits it.
    (r'(version = )"unstable-[0-9-]+"', r'\1"' + ver + '"'),
    # The first hash after the OpenFic fetchFromGitHub block.
    (r'(repo = "OpenFic";\n    inherit rev;\n    hash = )"[^"]+"', r'\1"' + h + '"'),
]
for pattern, repl in pairs:
    text, n = re.subn(pattern, repl, text, count=1)
    if n != 1:
        sys.exit(f"failed to rewrite pattern: {pattern}")
open(path, "w").write(text)
PY

# --- 6. Update the embedded pnpm tarball if upstream re-pinned it -------------

current_pnpm_version="$(
  sed -n '/pname = "pnpm-for-openfic";/{n;s/.*version = "\([0-9.]*\)".*/\1/;p}' "$package_nix" | head -n1
)"

if [ "$current_pnpm_version" != "$pnpm_version" ]; then
  echo "Upstream re-pinned pnpm: $current_pnpm_version -> $pnpm_version"
  pnpm_hash="$(
    nix --extra-experimental-features nix-command store prefetch-file --json \
      "https://registry.npmjs.org/pnpm/-/pnpm-$pnpm_version.tgz" \
      | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p'
  )"
  [ -n "$pnpm_hash" ] || die "failed to prefetch pnpm tarball hash"
  python3 - "$package_nix" "$pnpm_version" "$pnpm_hash" <<'PY'
import sys
path, ver, h = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
old_url = "https://registry.npmjs.org/pnpm/-/pnpm-11.8.0.tgz"
new_url = f"https://registry.npmjs.org/pnpm/-/pnpm-{ver}.tgz"
if old_url not in text:
    # Fallback for arbitrary previous pins.
    import re
    text, n = re.subn(
        r'url = "https://registry\.npmjs\.org/pnpm/-/pnpm-[0-9.]+\.tgz";\n(\s*hash = )"[^"]+"',
        f'url = "{new_url}";\n\\1"{h}"',
        text, count=1,
    )
    if n != 1:
        sys.exit("failed to rewrite pnpm tarball pin")
    text = re.sub(r'(pname = "pnpm-for-openfic";\n\s*version = )"[0-9.]+"', r'\1"' + ver + '"', text, count=1)
else:
    text = text.replace(old_url, new_url, 1)
    text = text.replace(
        'hash = "sha256-HpY6XEylFoVQugP8TujYc6dysHK3/OY7SP/yfXIOLpg=";',
        f'hash = "{h}";', 1,
    )
    text = text.replace('version = "11.8.0";', f'version = "{ver}";', 1)
open(path, "w").write(text)
PY
  echo "Updated embedded pnpm to $pnpm_version ($pnpm_hash)"
fi

# --- 7. Recompute the pnpmDeps FOD hash (build twice) --------------------------

echo "Rebuilding to discover the pnpmDeps FOD hash (first run is expected to fail)..."
fod_hash="$(
  cd "$flake_root"
  nix build .#openfic-git --no-link 2>&1 \
    | grep -oE 'got: +sha256-[A-Za-z0-9+/=]+' | sed 's/got: *//' | head -n1
)"
if [ -z "$fod_hash" ]; then
  echo "Warning: could not capture the FOD hash automatically." >&2
  echo "Run: nix build .#openfic-git" >&2
  echo "and substitute the 'got:' hash into the fetchPnpmDeps hash in $package_nix." >&2
  update_readme_versions
  exit 1
fi

python3 - "$package_nix" "$fod_hash" <<'PY'
import re, sys
path, h = sys.argv[1], sys.argv[2]
text = open(path).read()
# The dependency-store hash is the last `hash = ` argument of the
# fetchPnpmDeps call (the src fetchFromGitHub hash was rewritten earlier).
text, n = re.subn(r'(fetchPnpmDeps \{)', r'\1', text)  # anchor check
# Replace the hash = "…" line that sits right before the closing `};` of
# fetchPnpmDeps — identified by the pnpmInstallFlags block preceding it.
pattern = r'(pnpmInstallFlags = \[[^\]]*\];\n\n    hash = )"[^"]+"'
text, n = re.subn(pattern, r'\1"' + h + '"', text, count=1)
if n != 1:
    sys.exit("failed to rewrite fetchPnpmDeps hash")
open(path, "w").write(text)
PY

echo "FOD hash: $fod_hash"
echo "Verifying with a second build..."
( cd "$flake_root" && nix build .#openfic-git --no-link )

update_readme_versions

echo ""
echo "Updated openfic-git to $new_rev ($new_version, app $app_version, pnpm $pnpm_version)"
echo "src hash: $src_hash"
