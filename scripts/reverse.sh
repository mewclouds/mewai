#!/usr/bin/env bash
# Pulls locally modified settings into core/ and re-renders.
#
# Reverse of install: reads the installed provider settings file
# (~/.config/opencode/opencode.jsonc), strips any generated policy permissions,
# and writes the user settings back into core/providers/.
#
# Only settings files are reversed. Skills, instructions, and policy rules are
# never reversed.
set -euo pipefail

dry_run=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=true ;;
    *)
      printf 'usage: %s [--dry-run]\n' "$0" >&2
      exit 2
      ;;
  esac
  shift
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/build/manifest.json"

if [[ ! -f "$manifest" ]]; then
  printf 'error: build/manifest.json not found. Run scripts/render.ps1 first.\n' >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'error: jq is required to process settings\n' >&2
  exit 1
fi

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

reversed_count=0

# --- opencode config ---------------------------------------------------------
opencode_installed="$HOME/.config/opencode/opencode.jsonc"
opencode_build="$repo_root/build/opencode/opencode.jsonc"
opencode_core="$repo_root/core/providers/opencode/opencode.json"

if [[ -f "$opencode_installed" ]]; then
  installed_sha="$(sha_of "$opencode_installed")"
  build_sha=""
  if [[ -f "$opencode_build" ]]; then
    build_sha="$(sha_of "$opencode_build")"
  fi

  if [[ "$installed_sha" != "$build_sha" ]]; then
    # The installed file is .jsonc, so comments are legal there and OpenCode may
    # write them. jq cannot read those, and stripping them here is not safe because
    # the $schema value legitimately contains "//". Fail with the fix rather than a
    # parse error, or worse, a mangled source file.
    if ! jq -e . "$opencode_installed" >/dev/null 2>&1; then
      printf 'error: %s is not plain JSON, most likely because it contains comments. jq cannot read those. Run scripts/reverse.ps1 instead, which can.\n' "$opencode_installed" >&2
      exit 1
    fi

    if "$dry_run"; then
      printf 'would reverse ~/.config/opencode/opencode.jsonc -> core/providers/opencode/opencode.json\n'
    else
      temp_out="$(mktemp)"
      jq --slurpfile core "$opencode_core" '
        ._comment = ($core[0]._comment // "Base OpenCode settings owned by mewai. The permission block is generated from core/policy/policy.json by scripts/render.ps1 and must not be set here. Everything else is yours to edit.") |
        {_comment} + (del(._comment, .permission))
      ' "$opencode_installed" | tr -d '\r' > "$temp_out"
      mv "$temp_out" "$opencode_core"
      printf 'reversed ~/.config/opencode/opencode.jsonc -> core/providers/opencode/opencode.json\n'
    fi
    reversed_count=$((reversed_count + 1))
  fi
fi

# --- hermes config -----------------------------------------------------------
# The generated approvals block is delimited by markers, so stripping it needs no
# YAML parser in either language. sed deletes through the end marker and awk drops
# the blank line that followed it.
hermes_installed="$HOME/AppData/Local/hermes/config.yaml"
hermes_build="$repo_root/build/hermes/config.yaml"
hermes_core="$repo_root/core/providers/hermes/config.yaml"

if [[ -f "$hermes_installed" ]]; then
  installed_sha="$(sha_of "$hermes_installed")"
  build_sha=""
  if [[ -f "$hermes_build" ]]; then
    build_sha="$(sha_of "$hermes_build")"
  fi

  if [[ "$installed_sha" != "$build_sha" ]]; then
    if ! grep -qF '# --- end generated ---' "$hermes_installed"; then
      printf 'error: %s has no mewai generated block. Reinstall before reversing, otherwise the generated rules would be written back into source.\n' "$hermes_installed" >&2
      exit 1
    fi

    if "$dry_run"; then
      printf 'would reverse ~/AppData/Local/hermes/config.yaml -> core/providers/hermes/config.yaml\n'
    else
      temp_out="$(mktemp)"
      sed '1,/^# --- end generated ---$/d' "$hermes_installed" | tr -d '\r' > "$temp_out"
      mv "$temp_out" "$hermes_core"
      printf 'reversed ~/AppData/Local/hermes/config.yaml -> core/providers/hermes/config.yaml\n'
    fi
    reversed_count=$((reversed_count + 1))
  fi
fi

# --- finalize ----------------------------------------------------------------
if [[ $reversed_count -eq 0 ]]; then
  printf 'all settings are in sync with core/\n'
  exit 0
fi

if "$dry_run"; then
  printf '\nwould reverse %d setting file(s)\n' "$reversed_count"
else
  printf '\n'
  if command -v pwsh >/dev/null 2>&1; then
    pwsh "$repo_root/scripts/render.ps1"
    pwsh "$repo_root/scripts/install.ps1"
  else
    "$repo_root/scripts/install.sh"
  fi
  printf '\nreversed %d setting file(s), re-rendered, and installed\n' "$reversed_count"
fi
