# Providers

Install paths and render logic live in `scripts/render.ps1`. This file is the surprises.

## Policy mapping

| policy.json | OpenCode | Hermes |
| --- | --- | --- |
| `confirm` | `"ask"` | `approvals.deny`, unless `autonomy_omit` |
| `forbid` | `"deny"` | `approvals.deny` |

Antigravity does not render policy. `always-proceed` bypasses deny rules.

Unmatched OpenCode bash commands run. Patterns are last-match-wins, so the renderer emits ask, then deny.

## Do not

- Do not install `~/.config/opencode/skills`. OpenCode already reads `~/.agents/skills/`.
- Do not resolve `$HERMES_HOME` at render time. The Windows path is hardcoded so `build/` stays identical across machines. Linux and macOS Hermes use `~/.hermes/` and are not a target here.
- Do not put an `approvals` key in `core/providers/hermes/config.yaml`. It would duplicate the generated block.
- Do not put a `permission` key in `core/providers/opencode/opencode.json`. It is generated.
- mewai owns `~/.config/opencode/opencode.jsonc`. Other entries in that file are overwritten on install.

## OpenCode config is `.jsonc`

When both `opencode.json` and `opencode.jsonc` exist, `.jsonc` wins. Target that name. `reverse.sh` cannot parse comments in it. Run `reverse.ps1` if OpenCode wrote any.

## Hermes `read_file`

`approvals.deny` never sees `read_file`. Secret paths also render into the `pre_tool_call` hook. The entry point is `mewai-hook.cmd` because Hermes on Windows cannot exec a `.sh`.
