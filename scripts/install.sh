#!/usr/bin/env bash
# Preserves the Unix command while PowerShell owns the implementation.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v pwsh >/dev/null 2>&1; then
  printf 'error: pwsh is required\n' >&2
  exit 1
fi

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) args+=(-DryRun) ;;
    *)
      printf 'usage: %s [--dry-run]\n' "$0" >&2
      exit 2
      ;;
  esac
  shift
done

exec pwsh "$script_dir/install.ps1" "${args[@]}"
