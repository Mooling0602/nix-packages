#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
shopt -s globstar nullglob
update_scripts=("$repo_root"/pkgs/**/update.sh)

for update_script in "${update_scripts[@]}"; do
  echo "Running ${update_script#"$repo_root"/}"
  bash "$update_script"
done
