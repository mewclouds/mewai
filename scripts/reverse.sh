#!/usr/bin/env bash
# Pulls locally modified settings into core/ and re-renders.
#
# Reverse of install: reads the installed provider settings file
# (~/.claude/settings.json), strips any generated policy permissions, and writes
# the user settings back into core/providers/.
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

# --- claude settings ---------------------------------------------------------
claude_installed="$HOME/.claude/settings.json"
claude_build="$repo_root/build/claude/settings.json"
claude_core="$repo_root/core/providers/claude/settings.json"

if [[ -f "$claude_installed" ]]; then
  installed_sha="$(sha_of "$claude_installed")"
  build_sha=""
  if [[ -f "$claude_build" ]]; then
    build_sha="$(sha_of "$claude_build")"
  fi

  if [[ "$installed_sha" != "$build_sha" ]]; then
    if "$dry_run"; then
      printf 'would reverse ~/.claude/settings.json -> core/providers/claude/settings.json\n'
    else
      # Strip allow/ask/deny permissions and preserve core comment headers
      temp_out="$(mktemp)"
      jq --slurpfile core "$claude_core" '
        ._comment = ($core[0]._comment // "Base Claude Code settings owned by mewai. The allow, ask, and deny arrays under permissions are generated from core/policy/policy.json by scripts/render.ps1 and must not be set here. Everything else under permissions, including defaultMode, is yours to edit.") |
        if .permissions then
          .permissions = (
            ($core[0].permissions._comment // "auto mode is what makes the three-tier policy work. Ask rules prompt, deny rules block, and allow rules resolve without reaching the classifier. Under bypassPermissions the ask tier is silently inert. Do not set disableAutoMode here: it turns auto mode off.") as $c |
            (.permissions | del(.allow, .ask, .deny, ._comment)) |
            if $c then ({_comment: $c} + .) else . end
          )
        else . end |
        {_comment, permissions} + (del(._comment, .permissions))
      ' "$claude_installed" | tr -d '\r' > "$temp_out"
      mv "$temp_out" "$claude_core"
      printf 'reversed ~/.claude/settings.json -> core/providers/claude/settings.json\n'
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
