# Providers

Install paths and render logic live in `scripts/render.ps1`. This file is the surprises.

## Policy mapping

| policy.json | OpenCode |
| --- | --- |
| `confirm` | `"ask"` |
| `forbid` | `"deny"` |

Antigravity does not render policy. `always-proceed` bypasses deny rules.

Unmatched OpenCode bash commands run. Patterns are last-match-wins, so the renderer emits ask, then deny.

## Do not

- Do not install `~/.config/opencode/skills`. Skills already go to `~/.agents/skills/`, which OpenCode reads.
- Do not put a `permission` key in `core/providers/opencode/opencode.json`. It is generated.
- mewai owns `~/.config/opencode/opencode.jsonc`. Other entries in that file are overwritten on install.

## OpenCode config is `.jsonc`

When both `opencode.json` and `opencode.jsonc` exist, `.jsonc` wins. Target that name. `reverse.sh` cannot parse comments in it. Run `reverse.ps1` if OpenCode wrote any.
