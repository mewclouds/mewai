#!/usr/bin/env bash
# Copies rendered files from build/ to their installed locations.
#
# This script holds no rendering logic. It reads build/manifest.json and copies.
# Keeping it dumb is what lets a shell installer and a PowerShell installer coexist
# without drifting apart, because there is nothing in either of them complex enough
# to disagree about.
#
# Run scripts/render.ps1 first. Existing targets are backed up before replacement.
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
backup_root="$HOME/.mewai/backups/$(date +%Y%m%d-%H%M%S)"

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

installed=0
unchanged=0
backed_up=0

back_up_target() {
  local target="$1" install_path="$2"
  local backup_name="${install_path#\~/}"
  backup_name="${backup_name//\//_}"

  if "$dry_run"; then
    printf 'would back up %s to %s/%s\n' "$target" "$backup_root" "$backup_name"
  else
    mkdir -p "$backup_root"
    cp -- "$target" "$backup_root/$backup_name"
  fi
}

while IFS=$'\t' read -r build_path install_path action expected_sha; do
  [[ -n "$build_path" ]] || continue

  if [[ "$action" != "copy" ]]; then
    printf "error: unsupported manifest action '%s' for %s\n" "$action" "$build_path" >&2
    exit 1
  fi

  source_file="$repo_root/$build_path"
  target="${install_path/#\~\//$HOME/}"

  if [[ ! -f "$source_file" ]]; then
    printf 'error: rendered file missing: %s\n' "$build_path" >&2
    exit 1
  fi

  if [[ -f "$target" ]]; then
    if [[ "$(sha_of "$target")" == "$expected_sha" ]]; then
      unchanged=$((unchanged + 1))
      continue
    fi

    # Back up only what is about to be replaced, so a second install of unchanged
    # content leaves no empty backup directory behind.
    back_up_target "$target" "$install_path"
    backed_up=$((backed_up + 1))
  fi

  if "$dry_run"; then
    printf 'would install %s to %s\n' "$build_path" "$target"
  else
    mkdir -p "$(dirname "$target")"
    cp -- "$source_file" "$target"
    printf 'installed %s\n' "$target"
  fi
  installed=$((installed + 1))
  # jq on Windows writes CRLF to stdout, which leaves a trailing carriage return on
  # the last field and makes every hash comparison fail. Strip it here rather than
  # trusting the platform.
done < <(jq -r '.entries[] | [.build, .install, .action, .sha256] | @tsv' "$manifest" | tr -d '\r')

verb="installed"
"$dry_run" && verb="would install"

printf '\n%s %d file(s), %d already current, %d backed up\n' \
  "$verb" "$installed" "$unchanged" "$backed_up"

if [[ $backed_up -gt 0 ]] && ! "$dry_run"; then
  printf 'backups in %s\n' "$backup_root"
fi
