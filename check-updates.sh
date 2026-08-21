#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
shopt -s globstar nullglob
update_scripts=("$repo_root"/pkgs/**/update.sh)

# Update scripts to skip, keyed by path relative to repo_root, valued by the
# reason shown to the user. Add an entry here to skip a long-running script.
declare -A skipped_update_scripts=(
  ["pkgs/by-name/de/deepseek-harness/update.sh"]="due to the excessive time it would consume"
)

for update_script in "${update_scripts[@]}"; do
  rel_path="${update_script#"$repo_root"/}"
  if [[ -v "skipped_update_scripts[$rel_path]" ]]; then
    echo "Skipping $rel_path ${skipped_update_scripts[$rel_path]}."
    echo "You can run it manully."
    continue
  fi
  echo "Running $rel_path"
  bash "$update_script"
done
