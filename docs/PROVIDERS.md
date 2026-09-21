# Providers

Install paths and render logic live in `scripts/render.ps1`. This file is the surprises.

## Policy mapping

| policy.json | OpenCode | Codex |
| --- | --- | --- |
| `confirm` | `"ask"` | `prefix_rule(decision="prompt")` |
| `forbid` | `"deny"` | `prefix_rule(decision="forbidden")` |

Antigravity does not render policy. `always-proceed` bypasses deny rules.

Unmatched OpenCode bash commands run. Patterns are last-match-wins, so the renderer emits ask, then deny.

Codex `execpolicy` precedence is `forbidden > prompt > allow`. Unmatched commands allow. `prefix_rule` matches command prefixes, so a wrapper or a flag after arguments can miss.

Codex does not render `read_paths`. The `secret-files` rule has an empty `commands` array, so it emits no `prefix_rule`.

## Do not

- Do not install `~/.config/opencode/skills` or `~/.codex/skills`. Skills already go to `~/.agents/skills/`, which OpenCode and Codex both read.
- Do not put a `permission` key in `core/providers/opencode/opencode.json`. It is generated.
- mewai owns `~/.config/opencode/opencode.jsonc`. Other entries in that file are overwritten on install.

## Codex config.toml

`~/.codex/config.toml` is rendered from `core/providers/codex/config.toml`. Codex writes project trust entries into that file, which shows up as drift in `status`. Fold them with `scripts/reverse.ps1` (or `scripts/reverse.sh`), or reinstall to discard them.

Codex execpolicy assertions in `validate.ps1` run only when `codex` is on PATH. When it is not, validation reports them as skipped. An unverifiable check must never look like a passing one.

## OpenCode config is `.jsonc`

When both `opencode.json` and `opencode.jsonc` exist, `.jsonc` wins. Target that name. Both reverse commands use PowerShell and can parse its comments.
