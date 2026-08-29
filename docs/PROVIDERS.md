# Providers

What each provider loads, where mewai puts it, and where they genuinely differ.

## Rendered targets

| Source | Claude Code | Codex | Antigravity | OpenCode |
| --- | --- | --- | --- | --- |
| `core/instructions/*` | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` | `~/.gemini/GEMINI.md` | `~/.config/opencode/AGENTS.md` |
| `core/policy/policy.json` | `~/.claude/settings.json` (permissions) | `~/.codex/rules/default.rules` | not applicable | `~/.config/opencode/opencode.jsonc` (permission) |
| `core/providers/claude/settings.json` | `~/.claude/settings.json` (everything else) | not applicable | not applicable | not applicable |
| `core/providers/claude/statusline-command.sh` | `~/.claude/statusline-command.sh` | not applicable | not applicable | not applicable |
| `core/providers/codex/config.toml` | not applicable | `~/.codex/config.toml` | not applicable | not applicable |
| `core/providers/opencode/opencode.json` | not applicable | not applicable | not applicable | `~/.config/opencode/opencode.jsonc` (everything else) |
| `core/skills/<name>/SKILL.md` | `~/.claude/skills/<name>/SKILL.md` | `~/.agents/skills/<name>/SKILL.md` | `~/.gemini/skills/<name>/SKILL.md` | already covered by `~/.agents/skills/` |

Antigravity gets instructions and skills, nothing else. `policy.json` is not applicable there. See "Antigravity does not get rendered permissions" below for why.

OpenCode gets instructions and permissions but no skill copy of its own, because it already scans `~/.agents/skills/`, which the Codex row installs. Rendering a fourth copy would create the exact duplication this repository exists to remove.

Skills are byte-identical across all three locations. That is the whole point: they were maintained as separate files before, and one drifted.

## Invocation

- Claude Code: `/code-review`
- Codex: `$code-review`
- Antigravity: `/code-review`
- OpenCode: no sigil. The agent loads a skill through its built-in `skill` tool.

Codex also selects skills automatically from their descriptions. Claude Code selects from descriptions too, which is why every skill description states when to use it. A description without a trigger fails validation. OpenCode has nothing but the description to go on, so that check matters most there.

## How the three decisions map

| policy.json | Claude Code | Codex | OpenCode |
| --- | --- | --- | --- |
| `allow` | `permissions.allow` | `prefix_rule(decision="allow")` | `"allow"` |
| `confirm` | `permissions.ask` | no rule, falls through to the approval flow | `"ask"` |
| `forbid` | `permissions.deny` | `prefix_rule(decision="forbidden")` | `"deny"` |

Antigravity has no row here. It does not render any of the three decisions.

OpenCode is the only provider besides Claude Code that expresses all three, so `confirm` means the same thing on both.

`deny` and `ask` rules apply in every Claude Code permission mode, including `bypassPermissions`. `allow` rules do nothing in that mode. That is what makes full autonomy compatible with real boundaries: the mode removes prompts, the rules keep the hard stops.

## Where the providers differ

### confirm has no direct Codex equivalent

Codex `execpolicy` expresses `allow` and `forbidden`. There is no prompt-level decision, so a `confirm` rule emits nothing and the command falls through to Codex's own approval flow. That is the intended behavior rather than a missing feature, but it does mean the guarantee is weaker: Claude Code will always prompt, Codex will prompt according to its own `approval_policy`.

### Flag position

All three matching providers match commands by prefix. `git push --force` matches when `--force` is the third word. It does not match `git push origin main --force`, where the flag is fifth.

Claude Code and OpenCode can both express a wildcard in the middle of a pattern, so mewai closes that gap on both sides: `claude_rules` carries `Bash(git push * --force*)` and `opencode_rules` carries the same pattern unwrapped. Codex `prefix_rule` cannot express a flag at an arbitrary position, so the Codex guarantee stays narrower. Worth knowing before assuming the three are equivalent.

The two escape hatches state the same intent in two syntaxes, which is a duplication this repository normally rejects. It is accepted here because the alternative is a pattern language of mewai's own that renders into both, and there are five patterns. Unify it when there are fifty.

### Wrappers

Claude Code strips a fixed set of wrappers before matching: `timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, and bare `xargs`. Tools that also execute their arguments are **not** stripped, including `rtk`, `npx`, `docker exec`, and `devbox run`. A bare prefix rule therefore misses `rtk git push --force`.

mewai closes this by emitting a leading-wildcard variant for every restricting rule, so `Bash(* git push --force *)` catches the wrapped form. It does this only for `confirm` and `forbid`. Broadening an `allow` rule the same way would approve anything that merely ends with the right words.

### Bash and PowerShell

Claude Code matches `Bash(...)` and `PowerShell(...)` rules separately. On Windows the agent can reach the same `git` binary through either shell, so mewai emits both variants for every command. A rule covering only one shell is a gap, not a rule.

### OpenCode config is `opencode.jsonc`, not `opencode.json`

Both filenames are read from `~/.config/opencode/`, and when both exist **`.jsonc` wins**. Verified on 1.18.25 with a sentinel key in each.

This matters because OpenCode writes an `opencode.jsonc` for itself on first run. mewai originally targeted `opencode.json`, which meant the rendered permission block installed correctly, sat on disk correctly, hashed correctly in `status`, and was silently shadowed by OpenCode's own file. Every rule would have been inert with nothing reporting a problem. mewai therefore owns the `.jsonc` name.

One consequence: comments are legal in that file, and OpenCode may write them. `reverse.ps1` handles a commented file, because PowerShell's JSON parser skips comments. `reverse.sh` cannot, because `jq` rejects them and stripping `//` is unsafe when the `$schema` value legitimately contains it. The shell version detects this and tells you to run the PowerShell one rather than failing on a parse error or writing a mangled source file.

### OpenCode resolves by last match, not by strictness

Claude Code and Codex pick the most specific rule. OpenCode takes the last pattern in the file that matches, so position is the decision. A `deny` written above an overlapping `ask` never fires.

`New-OpenCodeSettings` therefore emits every allow pattern, then every ask pattern, then every deny pattern, and `validate.ps1` fails the build if that order is ever broken. This is a rendering invariant rather than a formatting preference. Hand-reordering the generated block downgrades boundaries without changing a single pattern, and nothing about reading a 220 line object reveals it.

### OpenCode has one bash matcher, not two

Claude Code matches `Bash(...)` and `PowerShell(...)` separately, so mewai emits both for every command. OpenCode has a single `bash` tool whose shell is chosen by its own `shell` config key, so each command produces one pattern set instead of two.

Almost every policy command is spelled the same in both shells, so this costs nothing for `git`, `gh`, `npm`, `rg`, and the rest. The exception is deletion: `rm -rf` is POSIX, and PowerShell reaches the same destruction through `Remove-Item` with a recurse switch, aliased as `rm`, `ri`, `rd`, and `del`. Those five are covered explicitly by `opencode_rules`, so the deny tier holds whichever shell you point it at.

Two details of those patterns are worth knowing before editing them:

- The switch is anchored with no space before it (`Remove-Item *-?ecurse*`, not `Remove-Item * -Recurse *`). The spaced form requires an argument between the command and the flag, so `Remove-Item -Recurse -Force ./x` walked straight through it. That was a live hole in the Claude rules too, now closed on both sides.
- PowerShell accepts any casing for a switch and neither matcher documents how it compares. OpenCode's single-character wildcard covers `-Recurse` and `-recurse` in one pattern. Claude Code has no documented `?`, so it lists both spellings instead. Neither covers `-RECURSE` or the abbreviated `-r`, which no glob separates from a path containing `-r`.

### OpenCode approves anything the policy does not name

Claude Code `auto` mode sends an unlisted command to its own classifier. Codex falls through to `approval_policy`. OpenCode does neither: its `bash` default is `allow`, and mewai deliberately emits no `"*"` catch-all.

The alternative was `"*": "ask"`, which prompts on every command outside the 26 entry allow list, including `pwsh`, `node`, `npm run`, and `make`. That is the same friction that got Antigravity's `proceed-in-sandbox` rejected. The deny tier still blocks unconditionally, so the hard stops are real. The soft middle is not, and the Autonomy section of the instructions is what covers it.

### OpenCode is the only other provider that enforces secret file reads

`policy.json` carries `read_paths` on the `secret-files` rule, a file-read boundary rather than a command one. Claude Code renders it as `Read()` matchers and OpenCode as `permission.read` entries. Codex has no file-read matcher, which is why that rule's `commands` array is empty and Codex gets nothing from it.

The path forms differ slightly. Claude Code patterns are repository-relative (`./**/.env`), OpenCode matches file paths with tilde expansion, so the renderer strips the `./` prefix and adds a `**/` variant for any relative path. OpenCode also denies `.env` reads on its own by default, independent of anything mewai writes.

### OpenCode sees every skill twice, and picks one at random

mewai installs byte-identical skills to `~/.claude/skills` and `~/.agents/skills`. OpenCode scans both, plus `~/.config/opencode/skills`. It deduplicates by name, so the loaded content is correct and each skill appears once.

What is not deterministic is which path it reports. [anomalyco/opencode#29950](https://github.com/anomalyco/opencode/issues/29950) documents the resolved root flipping between sessions, which changes the system prompt at a deep offset and defeats upstream prefix caching. There is no config lever for it: `OPENCODE_DISABLE_CLAUDE_CODE=1` also switches off the `.agents/skills` scan ([#12432](https://github.com/anomalyco/opencode/issues/12432)), which is the root mewai actually installs to. Accepted cost, not a misconfiguration.

### Antigravity does not get rendered permissions

An earlier version of this repo rendered `policy.json` into `~/.gemini/antigravity-cli/settings.json` using a `command(target)` / `read_file(target)` syntax. That worked, confirmed by hand: a `command()` deny rule blocked a real `rm -rf`, and a `read_file()` deny rule blocked a real `.env` read, both with an explicit "matches user-configured deny rule" message naming the rule, not the model choosing to decline, but it only worked under `toolPermission: "proceed-in-sandbox"`. Two other modes were tested and rejected: `always-proceed` bypasses the whole rules list, including deny; and `request-review` auto-denies everything, including allow-listed commands, in non-interactive use.

`proceed-in-sandbox` came with a different cost: any command not explicitly covered by `policy.json` falls to Antigravity's own internal judgment of "safe" vs "risky", which is opaque and inconsistent from mewai's side. Simple built-ins passed without a prompt; a multi-step piped command invoking a third-party analyzer did not, for reasons that were not fully knowable from outside. In daily use this meant frequent review prompts for ordinary commands, unlike Claude Code's `auto` mode, which is permissive by default with explicit exceptions rather than the reverse. The user's call: keep `toolPermission: "always-proceed"` and accept it has no tool-layer enforcement, rather than tolerate that friction or hand-maintain an ever growing allow list. See [`core/instructions/providers/antigravity.md`](../core/instructions/providers/antigravity.md) for what this means day to day.

`policy.json` and `New-ClaudeSettings`/`New-CodexRules` are unaffected. If a future Antigravity version adds a mode that is both permissive by default and still enforces explicit denies, matching Claude Code's `auto`, revisit this: the `command()`/`read_file()` syntax above is confirmed working, so rebuilding the render function (a `core/providers/antigravity/settings.json` base file plus a function mirroring `New-ClaudeSettings`) is straightforward, not a fresh investigation.

## Machine-local state

`~/.codex/config.toml` is rendered from `core/providers/codex/config.toml`, which includes project trust entries. Codex writes to that file itself when you trust a project interactively, so a new trust entry shows up in `status` as drift. Fold it into the source file with `scripts/reverse.ps1` (or `scripts/reverse.sh`) when you want it on every machine, or reinstall to discard it.

The same applies to `~/.claude/settings.json` when options change from the Claude Code CLI, and to `~/.config/opencode/opencode.jsonc` when you pick a model or provider from the OpenCode TUI. Running `reverse` pulls the new settings into `core/providers/` while keeping policy rules untouched, then re-renders and installs. For both JSON files it drops the generated permission block on the way in, so rendered output can never be laundered back into source.

`~/.gemini/antigravity-cli/settings.json` is not managed by mewai at all, for the reasons in "Antigravity does not get rendered permissions" above. Its `toolPermission`, `trustedWorkspaces`, `model`, and every other field are entirely yours to set, and mewai will not overwrite or report drift on any of it. `status` never lists this file, because it is no longer in the manifest.

Nothing else in `~/.codex`, `~/.claude`, `~/.gemini`, or `~/.config/opencode` is managed either. Credentials, sessions, history, caches, plugin state, and SQLite databases are never read or written.

## Verification

Codex `execpolicy` assertions in `validate.ps1` run only when `codex` is on PATH and executable. When it is not, validation reports them as skipped rather than passed. An unverifiable check must never look like a passing one.

Antigravity has nothing for `validate.ps1` to check beyond the standard instruction-module and skill checks that already run for every provider, since it renders no permission file. If Antigravity permission rendering is ever reintroduced, retest by hand the same way: an allow-tier, an ask-tier, and a deny-tier command, run via `agy -p` in a disposable directory, since there is no `agy`-native dry-run (`agy plugin validate` validates a plugin manifest, not settings.json or command permissions).

OpenCode is checked two ways.

Statically, `validate.ps1` reads the rendered `opencode.jsonc` as text and fails if the allow, ask, deny tiers are out of order, if any `forbid` command rendered no deny pattern, or if any `opencode_rules` pattern lost its exact spelling on the way through. It reads the text rather than a parsed object on purpose: both the order and the casing of those keys are load bearing, and a hashtable preserves neither.

Against the real binary, `validate.ps1` points `OPENCODE_CONFIG` at the build file and runs `opencode debug config`. That resolves the file through OpenCode's own config loader without installing it anywhere, so the assertions are:

- OpenCode accepts the file. An invalid action value fails the build with OpenCode's own message rather than at install time.
- The resolved config has a `permission` block. A file that loads while its rules quietly do not is the failure this catches.
- The per-tier pattern counts match what was rendered, so nothing was dropped or collapsed in parsing.

These need a working `opencode` on PATH. Without one they report as skipped, the same as the Codex `execpolicy` assertions.

What that still does not prove is enforcement: that a `deny` pattern actually stops the command. `opencode debug config` shows the loaded rules, not a decision for a given command line, so there is no equivalent of `codex execpolicy check <argv>`. Confirm by hand in a disposable directory:

| Command | Expected |
| --- | --- |
| `opencode run "run git status"` | runs, no prompt |
| `opencode run "run git commit --allow-empty -m test"` | prompts |
| `opencode run "run git push --force"` | blocked |
| `opencode run "run rtk git push --force"` | blocked, the wrapper cannot launder it |
| `opencode run "run git push origin main --force"` | blocked, the flag is fifth |
| `opencode run "read ~/.ssh/config"` | blocked |
| `opencode run "run ls && rm -rf /tmp/x"` | unverified. OpenCode documents matching parsed commands but not how a compound one is split |

Skill discovery is verifiable offline with `opencode debug skill`, which lists every skill it found and the path each resolved to. Expect the twelve mewai skills, each once, all under `.agents/skills`, plus OpenCode's own built-in `customize-opencode`.

Instruction pickup has no debug command. Confirm it by asking OpenCode which provider notes it is running under. Getting the Claude Code ones back means `~/.config/opencode/AGENTS.md` did not install and it fell back to `~/.claude/CLAUDE.md`.

Config is read once at startup and is not hot reloaded, so restart OpenCode after any install before testing.
