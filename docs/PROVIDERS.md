# Providers

What each provider loads, where mewai puts it, and where they genuinely differ.

## Rendered targets

| Source | Claude Code | Hermes | Antigravity | Cursor |
| --- | --- | --- | --- | --- |
| `core/instructions/base.md` | `~/.claude/CLAUDE.md` | `$HERMES_HOME/SOUL.md` | `~/.gemini/GEMINI.md` | `~/.cursor/rules/mewai.mdc` |
| `core/policy/policy.json` | `~/.claude/settings.json` (permissions) | `$HERMES_HOME/config.yaml` (approvals.deny) | not applicable | `~/.cursor/hooks.json` plus `~/.cursor/hooks/` |
| `core/providers/claude/settings.json` | `~/.claude/settings.json` (everything else) | not applicable | not applicable | not applicable |
| `core/providers/claude/statusline-command.sh` | `~/.claude/statusline-command.sh` | not applicable | not applicable | not applicable |
| `core/providers/hermes/config.yaml` | not applicable | `$HERMES_HOME/config.yaml` (everything else) | not applicable | not applicable |
| `core/providers/cursor/hooks.json` | not applicable | not applicable | not applicable | `~/.cursor/hooks.json` |
| `core/skills/<name>/SKILL.md` | `~/.claude/skills/<name>/SKILL.md` | `~/.agents/skills/<name>/SKILL.md` | `~/.gemini/skills/<name>/SKILL.md` | already covered by `~/.claude/skills/` |

Every provider receives byte-identical instruction content. Only the filename, the install path, and Cursor's `alwaysApply` front matter differ. There are no per-provider instruction modules, so a rule that cannot be stated for all four does not belong in the instructions at all.

`$HERMES_HOME` is `%LOCALAPPDATA%\hermes` on Windows native, which is what the manifest targets, and `~/.hermes` on Linux and macOS. See "Hermes home is not `~/.hermes` on Windows" below.

Antigravity gets instructions and skills, nothing else. `policy.json` is not applicable there. See "Antigravity does not get rendered permissions" below for why.

Cursor gets no skill copy of its own, because it already scans `~/.claude/skills/` and `~/.agents/skills/`, both of which another row installs. Rendering a third copy would create the exact duplication this repository exists to remove. Do not install a tree under `~/.cursor/skills/`.

One consequence: Cursor sees every skill twice. It deduplicates by name, so the loaded content is correct. This cost was accepted before and nothing about the Hermes row changes it.

Skills are byte-identical across all three locations. That is the whole point: they were maintained as separate files before, and one drifted.

Claude Code cannot read `~/.agents/skills` and Antigravity cannot read either of the other two, so a single shared tree is not reachable without symlinks, which need Developer Mode or admin on Windows and are not available on this machine. `core/skills/` is the single source regardless. Every install root is a disposable copy, and dropping a provider drops its tree with it.

## Invocation

- Claude Code: `/code-review`
- Hermes: `/code-review`
- Antigravity: `/code-review`
- Cursor: `/code-review`

Claude Code also selects skills automatically from their descriptions, which is why every skill description states when to use it. A description without a trigger fails validation.

## How the three decisions map

| policy.json | Claude Code | Hermes | Cursor |
| --- | --- | --- | --- |
| `allow` | `permissions.allow` | no rule, Hermes only prompts on its own dangerous patterns | no hook, `Run Everything` default |
| `confirm` | `permissions.ask` | `approvals.deny` unless the rule sets `autonomy_omit`, in which case it runs | hook `deny` unless the rule sets `autonomy_omit`, in which case it runs |
| `forbid` | `permissions.deny` | `approvals.deny` | hook `deny`, no handoff |

Antigravity has no column here. It does not render any of the three decisions.

Claude Code is the only provider that expresses all three as intended. `deny` and `ask` rules apply in every Claude Code permission mode, including `bypassPermissions`. `allow` rules do nothing in that mode. That is what makes full autonomy compatible with real boundaries: the mode removes prompts, the rules keep the hard stops.

## Where the providers differ

### Cursor maps confirm to deny

Cursor hooks document `allow`, `deny`, and `ask`. `ask` is a known no-op in `Run Everything`, which is the autonomy mode mewai targets, so a `confirm` rule that emitted `ask` would just run. mewai therefore renders confirm as deny and tells the agent to give the user the exact command, unless the rule sets `autonomy_omit`. That field drops the rule from the hook so Cursor stays autonomous while Claude Code still prompts. Forbid is also deny, with a stop message that does not hand the command over. `autonomy_omit` is illegal on forbid.

The hook is the hard stop. `failClosed` is set so a crashed or missing matcher blocks rather than fails open. Unlisted commands are allowed, because `Run Everything` is permissive by default with explicit exceptions.

Cursor has no `Bash()` / `PowerShell()` split. The matcher searches for the command tokens anywhere in the string, so a wrapper such as `rtk git push --force` is caught. Flag-at-fifth-word cases use `glob_rules` as globs against the full command string.

`permissions.json` `autoRun` is steering for Auto-review, not a boundary. mewai does not render it.

User-level instructions install to `~/.cursor/rules/mewai.mdc` with `alwaysApply: true`. Settings User Rules are account-synced and not a file the installer can copy. `~/.cursor/rules` is documented as machine-local.

mewai owns `~/.cursor/hooks.json`. Other user hooks in that file are overwritten on install, the same way Claude Code settings are.

Cloud Agents do not load `~/.cursor/` user hooks or user skills. They only see project files in the repository.

### Hermes has no ask tier

`approvals.mode` is `smart`, `manual`, or `off`. None of them is a per-command prompt: `smart` asks an auxiliary LLM to judge risk, `manual` prompts on Hermes' own dangerous-pattern list, and `off` is persistent yolo. A `git commit` is not on that list, so a `confirm` rule that rendered nothing would simply run.

`approvals.deny` is the one boundary that holds. It is a list of case-insensitive fnmatch globs matched against the whole command string, and a match blocks unconditionally, checked before `--yolo`, `/yolo`, and `approvals.mode: off`. That is the same guarantee Claude Code gives with deny under `bypassPermissions`.

So mewai renders both `forbid` and `confirm` into `approvals.deny`, the same decision Cursor forced, and for the same reason. `autonomy_omit` drops a confirm rule from both.

Because the match runs against the whole command string, a pattern needs no leading-wildcard variant to survive a wrapper: `*git push --force*` already catches `rtk git push --force`. Hermes also matches over the same deobfuscated variants its dangerous-pattern detector uses, so quoting tricks do not slip past.

`approvals.deny` applies to shell commands on host-reaching backends only, so an isolated container backend skips the guard stack entirely. It also does not cover Hermes' own non-shell tools. `write_file` and `patch` carry a built-in denylist for `~/.ssh`, `~/.aws`, and `~/.kube`. **`read_file` has no path restriction at all**, which was confirmed by watching it read `~/.ssh/` outside any workspace. There is no `HERMES_READ_SAFE_ROOT`.

That is why the `secret-files` rule renders twice. Its paths become command globs in `approvals.deny`, anchored on a path separator or on the whitespace that starts an argument so `*/.env*` does not also block `--env` and `environment`. The same paths become `rules.json` next to a `pre_tool_call` hook, which is the only thing that reaches `read_file`. See "The read hook" below.

### Hermes home is not `~/.hermes` on Windows

The Hermes documentation describes `~/.hermes/`. On a Windows native install that is wrong: `HERMES_HOME` is set to `%LOCALAPPDATA%\hermes`, and `hermes config path` confirms it. The manifest targets `~/AppData/Local/hermes/`.

That path is hardcoded rather than resolved from `$env:HERMES_HOME` at render time, because rendering has to be pure. The same `core/` must produce byte-identical `build/` output on every machine, and CI depends on it. Resolving an environment variable during render would make the manifest machine-specific and break that.

The cost is that a Linux, macOS, or WSL2 install of Hermes reads `~/.hermes/` and would need the two paths in the provider row and the config target changed. There is one install of Hermes here and it is Windows native, so this is a known limitation rather than a bug.

### The read hook

`approvals.deny` never sees `read_file`, so `secret-files` needs a second mechanism. mewai renders a `pre_tool_call` shell hook: `mewai-hook.cmd` calls `mewai-hook.ps1`, which matches the tool arguments against `rules.json` and returns `{"action":"block"}` or `{}`.

Three things about it are load bearing and were each found the hard way.

**The entry point must be batch, not shell.** Hermes cannot exec a `.sh` on Windows. It fails with `[WinError 193] %1 is not a valid Win32 application`, and the failure is a log line rather than anything visible in the session. Hermes does accept a command string with arguments, but it does not expand `~` inside them, so `pwsh -File ~/...` fails too. The `.cmd` wrapper exists because `%~dp0` locates the matcher without a machine-specific absolute path.

**`hooks_auto_accept: true` is rendered on purpose.** An unapproved hook script is skipped with a warning, not blocked, so the boundary silently stops existing. Re-rendering changes the script, which drops it off the allowlist again, which means every install would leave the hook inert until someone approved it at a TTY prompt that headless sessions never see. `fail_closed: true` covers the case where the hook runs and fails.

**The matcher checks every string in `tool_input`.** Hermes does not document which argument name `read_file` uses for its path. Scanning all string values cannot miss it by guessing the wrong key.

The hook only covers `read_file`. Terminal commands are already covered by `approvals.deny`, and doubling up would mean two places to change one rule.

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

`$HERMES_HOME/config.yaml` is written by Hermes itself. Approving a command with "always" appends it to `command_allowlist`, and `hermes config set` writes there too, so both show up in `status` as drift. `reverse` strips the generated block by its marker lines and writes the rest back to `core/providers/hermes/config.yaml`. That is a text operation on purpose: PowerShell has no built-in YAML parser, and a hand-rolled one would be a worse dependency than a pair of comment lines. `reverse` refuses outright when the installed file carries no marker, rather than writing generated rules back into source.

`$HERMES_HOME/SOUL.md` is fully owned by mewai and is overwritten on install. Hermes ships its own identity text there. Installing replaces it with the shared instructions, which open with "You are an agent" rather than naming Hermes.

`$HERMES_HOME/.env`, `auth.json`, `memories/`, `cron/`, `sessions/`, and the caches are never read or written.

`~/.gemini/antigravity-cli/settings.json` is not managed by mewai at all, for the reasons in "Antigravity does not get rendered permissions" above. Its `toolPermission`, `trustedWorkspaces`, `model`, and every other field are entirely yours to set, and mewai will not overwrite or report drift on any of it. `status` never lists this file, because it is not in the manifest.

Nothing else in `~/.claude`, `$HERMES_HOME`, `~/.gemini`, or `~/.cursor` is managed either. Credentials, sessions, history, caches, plugin state, and SQLite databases are never read or written.

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

Hermes is checked statically. `validate.ps1` fails the build if the base config declares its own `approvals` key, which would be a duplicate YAML key; if a `forbid` or non-omitted `confirm` command rendered no deny pattern; if an `autonomy_omit` rule rendered one anyway; or if any pattern lost its surrounding wildcards. Both the duplicate-key check and the coverage check were confirmed by breaking them on purpose and watching the build fail.

What that does not prove is enforcement. Confirm by hand in a disposable directory, with `--yolo` on, since the point is that these hold anyway:

| Command | Expected |
| --- | --- |
| `hermes chat --yolo -q "run git status"` | runs |
| `hermes chat --yolo -q "run git push --force"` | blocked |
| `hermes chat --yolo -q "run rtk git push --force"` | blocked, the wrapper cannot launder it |
| `hermes chat --yolo -q "run git push origin main --force"` | blocked, the flag is fifth |
| `hermes chat --yolo -q "run git commit -m test"` | blocked, confirm renders as deny |
| `hermes chat --yolo -q "run gh pr create --title test"` | runs. autonomy_omit, not in the deny list |
| `hermes chat --yolo -q "read ~/.ssh/config"` | blocked |

Deny changes take effect immediately, no restart needed. Skill discovery is checked with `hermes skills list`, which should show the thirteen mewai skills resolved under `~/.agents/skills`.

Every check in `validate.ps1` runs without an external binary, so nothing reports as skipped. When a provider needing one is added, report it as skipped rather than passing. An unverifiable check must never look like a passing one.
