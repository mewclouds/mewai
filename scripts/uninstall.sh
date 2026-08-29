#!/usr/bin/env bash
# Removes the files mewai installs, after backing them up.
#
# Use this to clear provider config back to a blank state before a first install, or
# to back mewai out entirely.
#
# Two deliberate safety properties:
#
#   - It reports what it would do and changes nothing unless you pass --confirm.
#   - It only removes paths listed in build/manifest.json, plus skill directories
#     under the three skill roots. It never touches credentials, sessions, history,
#     caches, or runtime databases.
#
# Everything removed is copied to ~/.mewai/backups/<timestamp>/ first.
set -euo pipefail

confirm=false
include_unmanaged=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm) confirm=true ;;
    --include-unmanaged-skills) include_unmanaged=true ;;
    *)
      printf 'usage: %s [--confirm] [--include-unmanaged-skills]\n' "$0" >&2
      exit 2
      ;;
  esac
  shift
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/build/manifest.json"
backup_root="$HOME/.mewai/backups/uninstall-$(date +%Y%m%d-%H%M%S)"

if [[ ! -f "$manifest" ]]; then
  printf 'error: build/manifest.json not found. Run scripts/render.ps1 first.\n' >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'error: jq is required to read the manifest\n' >&2
  exit 1
fi

targets=()
while IFS= read -r install_path; do
  [[ -n "$install_path" ]] && targets+=("$install_path")
done < <(jq -r '.entries[].install' "$manifest" | tr -d '\r')

if "$include_unmanaged"; then
  managed="$(jq -r '.entries[].install' "$manifest" | tr -d '\r')"
  for root in "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.gemini/skills"; do
    [[ -d "$root" ]] || continue
    # shellcheck disable=SC2088 # literal display text, not a path being expanded
    display="~/${root#"$HOME"/}"
    for dir in "$root"/*/; do
      [[ -d "$dir" ]] || continue
      name="$(basename "$dir")"
      grep -Fxq "$display/$name/SKILL.md" <<<"$managed" || targets+=("$display/$name")
    done
  done
fi

removed=0
absent=0

for target in "${targets[@]}"; do
  path="${target/#\~\//$HOME/}"

  if [[ ! -e "$path" ]]; then
    absent=$((absent + 1))
    continue
  fi

  if ! "$confirm"; then
    printf 'would remove %s\n' "$target"
    removed=$((removed + 1))
    continue
  fi

  backup_name="${target#\~/}"
  backup_name="${backup_name//\//_}"
  mkdir -p "$backup_root"
  cp -r -- "$path" "$backup_root/$backup_name"

  rm -rf -- "$path"
  printf 'removed %s\n' "$target"
  removed=$((removed + 1))
done

# Removing a skill's SKILL.md leaves its directory behind. Prune only directories
# that are now empty, and only directly under the skill roots. Never walk further up:
# deleting a non-empty parent is where an uninstall script turns into a mistake.
if "$confirm"; then
  for root in "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.gemini/skills"; do
    [[ -d "$root" ]] || continue
    find "$root" -mindepth 1 -maxdepth 1 -type d -empty -exec rmdir {} +
  done
fi

printf '\n'
if "$confirm"; then
  printf 'removed %d path(s), %d already absent\n' "$removed" "$absent"
  ((removed > 0)) && printf 'backups in %s\n' "$backup_root"
else
  printf 'would remove %d path(s), %d already absent\n' "$removed" "$absent"
  printf 'Nothing was changed. Pass --confirm to actually remove them.\n'
  "$include_unmanaged" ||
    printf 'Pass --include-unmanaged-skills to also remove skills mewai does not manage.\n'
fi
