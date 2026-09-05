# Providers

What each provider loads, where mewai puts it, and where they genuinely differ.

## Rendered targets

| Source | Claude Code | Antigravity | Cursor |
| --- | --- | --- | --- |
| `core/instructions/base.md` | `~/.claude/CLAUDE.md` | `~/.gemini/GEMINI.md` | `~/.cursor/rules/mewai.mdc` |
| `core/policy/policy.json` | `~/.claude/settings.json` (permissions) | not applicable | `~/.cursor/hooks.json` plus `~/.cursor/hooks/` |
| `core/providers/claude/settings.json` | `~/.claude/settings.json` (everything else) | not applicable | not applicable |
| `core/providers/claude/statusline-command.sh` | `~/.claude/statusline-command.sh` | not applicable | not applicable |
| `core/providers/cursor/hooks.json` | not applicable | not applicable | `~/.cursor/hooks.json` |
| `core/skills/<name>/SKILL.md` | `~/.claude/skills/<name>/SKILL.md` | `~/.gemini/skills/<name>/SKILL.md` | already covered by `~/.claude/skills/` |

Every provider receives byte-identical instruction content. Only the filename, the install path, and Cursor's `alwaysApply` front matter differ. There are no per-provider instruction modules, so a rule that cannot be stated for all three does not belong in the instructions at all.

Antigravity gets instructions and skills, nothing else. `policy.json` is not applicable there. See "Antigravity does not get rendered permissions" below for why.

Cursor gets no skill copy of its own, because it already scans `~/.claude/skills/`, which the Claude Code row installs. Rendering another copy would create the exact duplication this repository exists to remove. Do not install a third tree under `~/.cursor/skills/`.

Skills are byte-identical across both locations. That is the whole point: they were maintained as separate files before, and one drifted.

## Invocation

- Claude Code: `/code-review`
- Antigravity: `/code-review`
- Cursor: `/code-review`

Claude Code also selects skills automatically from their descriptions, which is why every skill description states when to use it. A description without a trigger fails validation.

## How the three decisions map

| policy.json | Claude Code | Cursor |
| --- | --- | --- |
| `allow` | `permissions.allow` | no hook, `Run Everything` default |
| `confirm` | `permissions.ask` | hook `deny` unless the rule sets `cursor: "omit"`, in which case it runs |
| `forbid` | `permissions.deny` | hook `deny`, no handoff |

Antigravity has no column here. It does not render any of the three decisions.

Claude Code is the only provider that expresses all three as intended. `deny` and `ask` rules apply in every Claude Code permission mode, including `bypassPermissions`. `allow` rules do nothing in that mode. That is what makes full autonomy compatible with real boundaries: the mode removes prompts, the rules keep the hard stops.

## Where the providers differ

### Cursor maps confirm to deny

Cursor hooks document `allow`, `deny`, and `ask`. `ask` is a known no-op in `Run Everything`, which is the autonomy mode mewai targets, so a `confirm` rule that emitted `ask` would just run. mewai therefore renders confirm as deny and tells the agent to give the user the exact command, unless the rule sets `cursor: "omit"`. That field drops the rule from the hook so Cursor stays autonomous while Claude Code still prompts. Forbid is also deny, with a stop message that does not hand the command over. `cursor: "omit"` is illegal on forbid.

The hook is the hard stop. `failClosed` is set so a crashed or missing matcher blocks rather than fails open. Unlisted commands are allowed, because `Run Everything` is permissive by default with explicit exceptions.

Cursor has no `Bash()` / `PowerShell()` split. The matcher searches for the command tokens anywhere in the string, so a wrapper such as `rtk git push --force` is caught. Flag-at-fifth-word cases use `glob_rules` as globs against the full command string.

`permissions.json` `autoRun` is steering for Auto-review, not a boundary. mewai does not render it.

User-level instructions install to `~/.cursor/rules/mewai.mdc` with `alwaysApply: true`. Settings User Rules are account-synced and not a file the installer can copy. `~/.cursor/rules` is documented as machine-local.

mewai owns `~/.cursor/hooks.json`. Other user hooks in that file are overwritten on install, the same way Claude Code settings are.

Cloud Agents do not load `~/.cursor/` user hooks or user skills. They only see project files in the repository.

### Flag position

Claude Code matches commands by prefix. `git push --force` matches when `--force` is the third word. It does not match `git push origin main --force`, where the flag is fifth.

Claude Code can express a wildcard in the middle of a pattern, so mewai closes that gap with `claude_rules`, which carries `Bash(git push * --force*)` and its PowerShell twin. `glob_rules` carries the same patterns unwrapped, for the Cursor hook to match as globs against the whole command string.

The two escape hatches state the same intent in two syntaxes, which is a duplication this repository normally rejects. It is accepted here because the alternative is a pattern language of mewai's own that renders into both, and there are five patterns. Unify it when there are fifty.

### Wrappers

Claude Code strips a fixed set of wrappers before matching: `timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, and bare `xargs`. Tools that also execute their arguments are **not** stripped, including `rtk`, `npx`, `docker exec`, and `devbox run`. A bare prefix rule therefore misses `rtk git push --force`.

mewai closes this by emitting a leading-wildcard variant for every restricting rule, so `Bash(* git push --force *)` catches the wrapped form. It does this only for `confirm` and `forbid`. Broadening an `allow` rule the same way would approve anything that merely ends with the right words.

### Bash and PowerShell

Claude Code matches `Bash(...)` and `PowerShell(...)` rules separately. On Windows the agent can reach the same `git` binary through either shell, so mewai emits both variants for every command. A rule covering only one shell is a gap, not a rule.

### Antigravity does not get rendered permissions

An earlier version of this repo rendered `policy.json` into `~/.gemini/antigravity-cli/settings.json` using a `command(target)` / `read_file(target)` syntax. That worked, confirmed by hand: a `command()` deny rule blocked a real `rm -rf`, and a `read_file()` deny rule blocked a real `.env` read, both with an explicit "matches user-configured deny rule" message naming the rule, not the model choosing to decline, but it only worked under `toolPermission: "proceed-in-sandbox"`. Two other modes were tested and rejected: `always-proceed` bypasses the whole rules list, including deny; and `request-review` auto-denies everything, including allow-listed commands, in non-interactive use.

`proceed-in-sandbox` came with a different cost: any command not explicitly covered by `policy.json` falls to Antigravity's own internal judgment of "safe" vs "risky", which is opaque and inconsistent from mewai's side. Simple built-ins passed without a prompt; a multi-step piped command invoking a third-party analyzer did not, for reasons that were not fully knowable from outside. In daily use this meant frequent review prompts for ordinary commands, unlike Claude Code's `auto` mode, which is permissive by default with explicit exceptions rather than the reverse. The user's call: keep `toolPermission: "always-proceed"` and accept it has no tool-layer enforcement, rather than tolerate that friction or hand-maintain an ever growing allow list.

Nothing in the rendered instruction file states this any more. Per-provider instruction modules were removed when every provider moved to identical content, so the Secrets and Requests sections of `base.md` are what covers Antigravity, with no deny rule behind them.

`policy.json` and `New-ClaudeSettings` are unaffected. If a future Antigravity version adds a mode that is both permissive by default and still enforces explicit denies, matching Claude Code's `auto`, revisit this: the `command()`/`read_file()` syntax above is confirmed working, so rebuilding the render function (a `core/providers/antigravity/settings.json` base file plus a function mirroring `New-ClaudeSettings`) is straightforward, not a fresh investigation.

## Machine-local state

`~/.claude/settings.json` changes when options are set from the Claude Code CLI, so a new option shows up in `status` as drift. Running `reverse` pulls those settings into `core/providers/` while leaving policy rules untouched, then re-renders and installs. It drops the generated permission block on the way in, so rendered output can never be laundered back into source.

Claude Code settings are the only thing `reverse` handles now. It was written for three providers whose config files they each wrote to themselves.

`~/.gemini/antigravity-cli/settings.json` is not managed by mewai at all, for the reasons in "Antigravity does not get rendered permissions" above. Its `toolPermission`, `trustedWorkspaces`, `model`, and every other field are entirely yours to set, and mewai will not overwrite or report drift on any of it. `status` never lists this file, because it is not in the manifest.

Nothing else in `~/.claude`, `~/.gemini`, or `~/.cursor` is managed either. Credentials, sessions, history, caches, plugin state, and SQLite databases are never read or written.

## Verification

Antigravity has nothing for `validate.ps1` to check beyond the standard instruction-module and skill checks that already run for every provider, since it renders no permission file. If Antigravity permission rendering is ever reintroduced, retest by hand: an allow-tier, an ask-tier, and a deny-tier command, run via `agy -p` in a disposable directory, since there is no `agy`-native dry-run (`agy plugin validate` validates a plugin manifest, not settings.json or command permissions).

Cursor hook matching is checked offline in `validate.ps1` by piping JSON into the rendered `mewai-policy.ps1`. Those assertions always run. They prove the matcher decides. They do not prove Cursor loaded `hooks.json`. Confirm that in the IDE:

| Action in chat | Expected |
| --- | --- |
| `run git status` | runs |
| `run gh pr create --title test` | runs. Confirm omit, not in the hook |
| `run git commit -m test` | blocked, agent gives you the command |
| `run git push --force` | blocked, no handoff |
| `run rtk git push --force` | blocked, the wrapper cannot launder it |
| `read ~/.ssh/config` | blocked |

Cursor watches `hooks.json` and reloads on save. If a hook still does not fire, restart Cursor. Check Customize > Hooks, and the Hooks output channel. Daily use is `Run Everything` under Settings > Agents > Approvals & Execution. Auto-review is not the enforcement path.

Every check in `validate.ps1` runs without an external binary, so nothing reports as skipped. When a provider needing one is added, report it as skipped rather than passing. An unverifiable check must never look like a passing one.
