#!/usr/bin/env bash
# Update openfic-git to the latest commit of OpenFic's main branch.
#
# The pins live in hashes.json and in the two vendored pnpm lockfiles next to
# this script; package.nix consumes them directly (the lockfiles feed
# importPnpmLock, whose per-package integrity hashes replace the old probed
# pnpmDepsHash). An update is therefore just "fetch everything, then write
# atomically" — no dependency store has to be built twice and no pending
# state can be left behind.
#
# This script updates:
#   1. src rev + version (unstable-<commit-date>) in hashes.json
#   2. the embedded pnpm tarball pin when upstream changes packageManager
#   3. pnpm-lock.desktop.yaml / pnpm-lock.frontend.yaml from upstream
#   4. the commit reference in both READMEs
set -euo pipefail

# --- Optional GitHub API authentication to avoid rate limiting --------------
# Export GITHUB_PAT (a GitHub personal access token) to authenticate GitHub
# REST / raw requests. GITHUB_TOKEN is honoured as a fallback.
gh_auth=()
if [ -n "${GITHUB_PAT:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
  gh_auth=(-H "Authorization: Bearer ${GITHUB_PAT:-${GITHUB_TOKEN:-}}")
fi

repo_api="https://api.github.com/repos/syrizelink/OpenFic"
repo_raw="https://raw.githubusercontent.com/syrizelink/OpenFic"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hashes_json="$script_dir/hashes.json"
lock_desktop="$script_dir/pnpm-lock.desktop.yaml"
lock_frontend="$script_dir/pnpm-lock.frontend.yaml"
readme="$script_dir/README.md"
readme_zh="$script_dir/README_zh_CN.md"
flake_root="$(cd "$script_dir/../../../.." && pwd)"

die() { echo "Error: $*" >&2; exit 1; }

# Retry transient network failures; GitHub/npm occasionally return 5xx or
# reset the connection mid-request.
fetch() {
  curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "${gh_auth[@]}" "$@"
}

# Read a top-level string field from hashes.json (empty when the key is absent).
json_get() {
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' \
    "$hashes_json" "$1"
}

# Atomically rewrite hashes.json. Each KEY=VALUE sets a field; KEY= (an empty
# value) removes it.
json_write() {
  python3 - "$hashes_json" "$@" <<'PY'
import json, os, sys

path, pairs = sys.argv[1], sys.argv[2:]
with open(path) as f:
    data = json.load(f)
for pair in pairs:
    key, _, value = pair.partition("=")
    if value:
        data[key] = value
    else:
        data.pop(key, None)
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY
}

# Run the flake evaluation (this executes importPnpmLock's lockfile
# assertions) so a bad pin is reported here instead of at the next build.
verify_eval() {
  echo "Verifying flake evaluation..."
  ( cd "$flake_root" && nix eval --raw .#openfic-git.drvPath > /dev/null )
}

update_readme_versions() {
  # Replace the upstream commit SHA referenced in both READMEs (wrapped in
  # backticks). The English sentence may be wrapped across two lines, so a
  # line-based `sed` on that phrase can silently miss it; match the 40-hex SHA
  # itself instead — cross-line-safe and works for both languages.
  perl -pi -e 's/`[0-9a-f]{40}`/`'"$new_rev"'`/g' "$readme" "$readme_zh"
}

# --- 1. Resolve the latest main HEAD commit ---------------------------------

head_json="$(fetch "$repo_api/commits/main")" || die "failed to fetch main HEAD"
# `head -n1` closes the pipe after the first line, so the upstream `sed` can
# die with SIGPIPE (status 141) when the commits JSON is large. Under
# `set -e` + `pipefail` that would abort the script before the extraction is
# validated below; `|| true` absorbs the expected SIGPIPE.
new_rev="$(printf '%s' "$head_json" | sed -n 's/.*"sha": *"\([0-9a-f]\{40\}\)".*/\1/p' | head -n1)" || true
commit_date="$(printf '%s' "$head_json" | sed -n 's/.*"date": *"\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)T[^"]*".*/\1/p' | head -n1)" || true

[ -n "$new_rev" ] || die "failed to extract commit sha"
[ -n "$commit_date" ] || die "failed to extract commit date"

new_version="unstable-$commit_date"

# --- 2. Read pinned tooling from desktop/package.json at that commit ---------

pkg_json="$(fetch "$repo_raw/$new_rev/desktop/package.json")" \
  || die "failed to fetch desktop/package.json at $new_rev"
app_version="$(printf '%s' "$pkg_json" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -n1)" || true
pnpm_version="$(printf '%s' "$pkg_json" | sed -n 's/.*"packageManager": *"pnpm@\([^"]*\)".*/\1/p' | head -n1)" || true

[ -n "$app_version" ] || die "failed to extract app version"
[ -n "$pnpm_version" ] || die "failed to extract packageManager pnpm version"

# --- 3. Fetch and validate the upstream lockfiles -----------------------------

tmp_lock_desktop="$lock_desktop.tmp"
tmp_lock_frontend="$lock_frontend.tmp"
trap 'rm -f "$tmp_lock_desktop" "$tmp_lock_frontend"' EXIT

fetch -o "$tmp_lock_desktop" "$repo_raw/$new_rev/desktop/pnpm-lock.yaml" \
  || die "failed to fetch desktop/pnpm-lock.yaml at $new_rev"
fetch -o "$tmp_lock_frontend" "$repo_raw/$new_rev/frontend/pnpm-lock.yaml" \
  || die "failed to fetch frontend/pnpm-lock.yaml at $new_rev"

# importPnpmLock only supports lockfile format 9.0; refuse to pin anything it
# cannot parse instead of leaving an eval-time failure behind.
for lock in "$tmp_lock_desktop" "$tmp_lock_frontend"; do
  grep -q "lockfileVersion: '9.0'" "$lock" \
    || die "$lock is not a supported pnpm lockfile (expected lockfileVersion 9.0)"
done

# --- 4. Compare with the current pin -------------------------------------------

current_rev="$(json_get rev)"
current_pnpm_version="$(json_get pnpmVersion)"
locks_changed=false
cmp -s "$tmp_lock_desktop" "$lock_desktop" || locks_changed=true
cmp -s "$tmp_lock_frontend" "$lock_frontend" || locks_changed=true

if [ "$current_rev" = "$new_rev" ] \
  && [ "$current_pnpm_version" = "$pnpm_version" ] \
  && [ "$locks_changed" = false ]; then
  verify_eval
  update_readme_versions
  echo "openfic-git is already at $new_rev ($new_version, app $app_version)"
  exit 0
fi

# --- 5. Prefetch the hashes that need no build --------------------------------

src_hash="$(
  # --unpack is required: package.nix uses fetchFromGitHub, which hashes the
  # normalised unpacked tree (a nar hash). A plain prefetch hashes the
  # tarball bytes instead and will never match the src hash in hashes.json.
  nix --extra-experimental-features nix-command store prefetch-file --unpack --json \
    "https://github.com/syrizelink/OpenFic/archive/$new_rev.tar.gz" \
    | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p'
)"
[ -n "$src_hash" ] || die "failed to prefetch source hash"

if [ "$current_pnpm_version" != "$pnpm_version" ]; then
  echo "Upstream re-pinned pnpm: $current_pnpm_version -> $pnpm_version"
  pnpm_hash="$(
    nix --extra-experimental-features nix-command store prefetch-file --json \
      "https://registry.npmjs.org/pnpm/-/pnpm-$pnpm_version.tgz" \
      | sed -n 's/.*"hash": *"\([^"]*\)".*/\1/p'
  )"
  [ -n "$pnpm_hash" ] || die "failed to prefetch pnpm tarball hash"
else
  pnpm_hash="$(json_get pnpmHash)"
  [ -n "$pnpm_hash" ] || die "pnpmVersion is pinned but pnpmHash is missing from hashes.json"
fi

# --- 6. Write everything atomically (hashes.json last) -------------------------
# The lockfiles are written first and hashes.json last: hashes.json is what
# marks the revision as pinned, so it must never point at a lockfile set that
# was not fully written.

mv -- "$tmp_lock_desktop" "$lock_desktop"
mv -- "$tmp_lock_frontend" "$lock_frontend"

json_write \
  "rev=$new_rev" \
  "version=$new_version" \
  "srcHash=$src_hash" \
  "pnpmVersion=$pnpm_version" \
  "pnpmHash=$pnpm_hash" \
  "pnpmDepsHash="

# --- 7. Verify ------------------------------------------------------------------

verify_eval
update_readme_versions

echo ""
echo "Updated openfic-git to $new_rev ($new_version, app $app_version, pnpm $pnpm_version)"
echo "src hash: $src_hash"
echo "lockfiles: $(basename "$lock_desktop"), $(basename "$lock_frontend")"
