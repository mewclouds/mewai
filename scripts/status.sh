#!/usr/bin/env bash
# Reports which installed files still match the rendered source.
#
# This answers the question the repository exists for: what has changed and what has
# not. Four skills were copied into two locations by hand and one of them silently
# drifted. Nothing reported it. This does.
#
# Exit code is 1 when anything is modified or missing, so it works as a check.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/build/manifest.json"

if [[ ! -f "$manifest" ]]; then
  printf 'error: build/manifest.json not found. Run scripts/render.ps1 first.\n' >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'error: jq is required to read the manifest\n' >&2
  exit 1
fi

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

in_sync=()
modified=()
missing=()

# jq on Windows writes CRLF to stdout, which leaves a trailing carriage return on the
# last field and makes every comparison fail. Strip it rather than trusting the platform.
while IFS=$'\t' read -r install_path expected_sha; do
  [[ -n "$install_path" ]] || continue
  target="${install_path/#\~\//$HOME/}"

  if [[ ! -f "$target" ]]; then
    missing+=("$install_path")
  elif [[ "$(sha_of "$target")" == "$expected_sha" ]]; then
    in_sync+=("$install_path")
  else
    modified+=("$install_path")
  fi
done < <(jq -r '.entries[] | [.install, .sha256] | @tsv' "$manifest" | tr -d '\r')

# A skill deleted from core/skills stays installed forever unless something looks for
# it. An orphan still loads into context and still gets invoked.
orphans=()
managed="$(jq -r '.entries[].install' "$manifest" | tr -d '\r')"

for root in "$HOME/.claude/skills" "$HOME/.agents/skills" "$HOME/.gemini/skills"; do
  [[ -d "$root" ]] || continue
  display="~/${root#"$HOME"/}"

  for dir in "$root"/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    if ! grep -Fxq "$display/$name/SKILL.md" <<<"$managed"; then
      orphans+=("$display/$name")
    fi
  done
done

print_section() {
  local title="$1"
  shift
  (($# == 0)) && return 0
  printf '\n%s:\n' "$title"
  printf '  %s\n' "$@"
}

print_section 'in sync' ${in_sync[@]+"${in_sync[@]}"}
print_section 'modified on disk' ${modified[@]+"${modified[@]}"}
print_section 'not installed' ${missing[@]+"${missing[@]}"}
print_section 'installed but not managed by mewai' ${orphans[@]+"${orphans[@]}"}

printf '\n%d in sync, %d modified, %d not installed, %d unmanaged\n' \
  "${#in_sync[@]}" "${#modified[@]}" "${#missing[@]}" "${#orphans[@]}"

if ((${#modified[@]} > 0)); then
  printf '\n%s\n' 'A modified file was edited after install, or the source changed and was not reinstalled.'
  printf '%s\n' 'Run scripts/install.sh to overwrite, after saving anything worth keeping.'
fi

if ((${#modified[@]} > 0 || ${#missing[@]} > 0)); then
  exit 1
fi
