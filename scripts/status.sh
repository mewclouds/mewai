#!/usr/bin/env bash
# Preserves the Unix command while PowerShell owns the implementation.
set -euo pipefail

if [[ $# -ne 0 ]]; then
  printf 'usage: %s\n' "$0" >&2
  exit 2
fi

if ! command -v pwsh >/dev/null 2>&1; then
  printf 'error: pwsh is required\n' >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec pwsh "$script_dir/status.ps1"
