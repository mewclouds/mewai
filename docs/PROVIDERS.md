# Providers

What each provider loads, where mewai puts it, and where they genuinely differ.

## Rendered targets

| Source | Claude Code | Codex | Antigravity |
| --- | --- | --- | --- |
| `core/instructions/*` | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` | `~/.gemini/GEMINI.md` |
| `core/policy/policy.json` | `~/.claude/settings.json` (permissions) | `~/.codex/rules/default.rules` | not applicable |
| `core/providers/claude/settings.json` | `~/.claude/settings.json` (everything else) | not applicable | not applicable |
| `core/providers/claude/statusline-command.sh` | `~/.claude/statusline-command.sh` | not applicable | not applicable |
| `core/providers/codex/config.toml` | not applicable | `~/.codex/config.toml` | not applicable |
| `core/skills/<name>/SKILL.md` | `~/.claude/skills/<name>/SKILL.md` | `~/.agents/skills/<name>/SKILL.md` | `~/.gemini/skills/<name>/SKILL.md` |

Antigravity gets instructions and skills, nothing else. `policy.json` is not applicable there. See "Antigravity does not get rendered permissions" below for why.

Skills are byte-identical across all three locations. That is the whole point: they were maintained as separate files before, and one drifted.

## Invocation

- Claude Code: `/code-review`
- Codex: `$code-review`
- Antigravity: `/code-review`

Codex also selects skills automatically from their descriptions. Claude Code selects from descriptions too, which is why every skill description states when to use it. A description without a trigger fails validation.

## How the three decisions map

| policy.json | Claude Code | Codex |
| --- | --- | --- |
| `allow` | `permissions.allow` | `prefix_rule(decision="allow")` |
| `confirm` | `permissions.ask` | no rule, falls through to the approval flow |
| `forbid` | `permissions.deny` | `prefix_rule(decision="forbidden")` |

Antigravity has no row here. It does not render any of the three decisions.

`deny` and `ask` rules apply in every Claude Code permission mode, including `bypassPermissions`. `allow` rules do nothing in that mode. That is what makes full autonomy compatible with real boundaries: the mode removes prompts, the rules keep the hard stops.

## Where the providers differ

### confirm has no direct Codex equivalent

Codex `execpolicy` expresses `allow` and `forbidden`. There is no prompt-level decision, so a `confirm` rule emits nothing and the command falls through to Codex's own approval flow. That is the intended behavior rather than a missing feature, but it does mean the guarantee is weaker: Claude Code will always prompt, Codex will prompt according to its own `approval_policy`.

### Flag position

Both providers match commands by prefix. `git push --force` matches when `--force` is the third word. It does not match `git push origin main --force`, where the flag is fifth.

Claude Code can express a wildcard in the middle of a pattern, so mewai closes that gap on the Claude side with explicit rules such as `Bash(git push * --force*)`. Codex `prefix_rule` cannot express a flag at an arbitrary position, so the Codex guarantee stays narrower. Worth knowing before assuming the two are equivalent.

### Wrappers

Claude Code strips a fixed set of wrappers before matching: `timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, and bare `xargs`. Tools that also execute their arguments are **not** stripped, including `rtk`, `npx`, `docker exec`, and `devbox run`. A bare prefix rule therefore misses `rtk git push --force`.

mewai closes this by emitting a leading-wildcard variant for every restricting rule, so `Bash(* git push --force *)` catches the wrapped form. It does this only for `confirm` and `forbid`. Broadening an `allow` rule the same way would approve anything that merely ends with the right words.

### Bash and PowerShell

Claude Code matches `Bash(...)` and `PowerShell(...)` rules separately. On Windows the agent can reach the same `git` binary through either shell, so mewai emits both variants for every command. A rule covering only one shell is a gap, not a rule.

### Antigravity does not get rendered permissions

An earlier version of this repo rendered `policy.json` into `~/.gemini/antigravity-cli/settings.json` using a `command(target)` / `read_file(target)` syntax. That worked, confirmed by hand: a `command()` deny rule blocked a real `rm -rf`, and a `read_file()` deny rule blocked a real `.env` read, both with an explicit "matches user-configured deny rule" message naming the rule, not the model choosing to decline, but it only worked under `toolPermission: "proceed-in-sandbox"`. Two other modes were tested and rejected: `always-proceed` bypasses the whole rules list, including deny; and `request-review` auto-denies everything, including allow-listed commands, in non-interactive use.

`proceed-in-sandbox` came with a different cost: any command not explicitly covered by `policy.json` falls to Antigravity's own internal judgment of "safe" vs "risky", which is opaque and inconsistent from mewai's side. Simple built-ins passed without a prompt; a multi-step piped command invoking a third-party analyzer did not, for reasons that were not fully knowable from outside. In daily use this meant frequent review prompts for ordinary commands, unlike Claude Code's `auto` mode, which is permissive by default with explicit exceptions rather than the reverse. The user's call: keep `toolPermission: "always-proceed"` and accept it has no tool-layer enforcement, rather than tolerate that friction or hand-maintain an ever growing allow list. See [`core/instructions/providers/antigravity.md`](../core/instructions/providers/antigravity.md) for what this means day to day.

`policy.json` and `New-ClaudeSettings`/`New-CodexRules` are unaffected. If a future Antigravity version adds a mode that is both permissive by default and still enforces explicit denies, matching Claude Code's `auto`, revisit this: the `command()`/`read_file()` syntax above is confirmed working, so rebuilding the render function (a `core/providers/antigravity/settings.json` base file plus a function mirroring `New-ClaudeSettings`) is straightforward, not a fresh investigation.

## Machine-local state

`~/.codex/config.toml` is rendered from `core/providers/codex/config.toml`, which includes project trust entries. Codex writes to that file itself when you trust a project interactively, so a new trust entry shows up in `status` as drift. Fold it into the source file when you want it on every machine, or reinstall to discard it.

`~/.gemini/antigravity-cli/settings.json` is not managed by mewai at all, for the reasons in "Antigravity does not get rendered permissions" above. Its `toolPermission`, `trustedWorkspaces`, `model`, and every other field are entirely yours to set, and mewai will not overwrite or report drift on any of it. `status` never lists this file, because it is no longer in the manifest.

Nothing else in `~/.codex`, `~/.claude`, or `~/.gemini` is managed either. Credentials, sessions, history, caches, plugin state, and SQLite databases are never read or written.

## Verification

Codex `execpolicy` assertions in `validate.ps1` run only when `codex` is on PATH and executable. When it is not, validation reports them as skipped rather than passed. An unverifiable check must never look like a passing one.

Antigravity has nothing for `validate.ps1` to check beyond the standard instruction-module and skill checks that already run for every provider, since it renders no permission file. If Antigravity permission rendering is ever reintroduced, retest by hand the same way: an allow-tier, an ask-tier, and a deny-tier command, run via `agy -p` in a disposable directory, since there is no `agy`-native dry-run (`agy plugin validate` validates a plugin manifest, not settings.json or command permissions).
