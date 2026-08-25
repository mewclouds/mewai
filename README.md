# mewai

This is my workflow for AI-assisted development: one source of truth for agent instructions, command boundaries, and skills, rendered into every provider I use.

Today that's Claude Code, Codex, and Antigravity CLI (`agy`). When I pick up a fourth, I write one adapter in the renderer instead of maintaining a fourth copy of my rules.

## Why I built this

My config kept drifting because the same content lived in several places and nothing compared them. I'd copy a skill into `~/.claude/skills` and `~/.agents/skills`, they'd stay in sync for a while, then I'd edit one and forget the other. Nothing told me.

mewai fixes that three ways:

- **One source.** `core/` is what I author. `build/` is generated.
- **Committed output.** Rendered files are checked in, so `git diff` shows me exactly what a change did to every provider before I install it.
- **A drift report.** `status` hashes what's installed against what was rendered and tells me what no longer matches.

## Quick start

```bash
pwsh ./scripts/render.ps1
```

```bash
pwsh ./scripts/validate.ps1
```

```bash
./scripts/install.sh --dry-run
```

```bash
./scripts/install.sh
```

I use `pwsh ./scripts/install.ps1` on Windows instead. Both installers do the same thing, driven by the same manifest.

I restart the provider afterward so it reloads instructions and skills.

## Daily use

Check whether anything drifted:

```bash
./scripts/status.sh
```

It reports four groups: in sync, modified on disk, not installed, and installed but not managed by mewai. That last group is what catches a skill I deleted from `core/` that's still sitting in a provider directory, still loading into context.

When you change settings interactively in Claude Code or Codex, pull them into the repo:

```bash
./scripts/reverse.sh
```

Or `pwsh ./scripts/reverse.ps1` on Windows. It strips generated policy rules, updates `core/providers/`, re-renders, and brings installed files back in sync.

After changing anything under `core/`:

```bash
pwsh ./scripts/render.ps1 && pwsh ./scripts/validate.ps1 && ./scripts/install.sh
```

## Starting from a blank state

mewai owns its target files outright. To clear them first:

```bash
./scripts/uninstall.sh --include-unmanaged-skills
```

That's a dry run. I add `--confirm` to actually remove them. Everything removed gets copied to `~/.mewai/backups/<timestamp>/` first, and only paths listed in the manifest are touched. Credentials, sessions, history, caches, and runtime databases are never in scope.

## What lives where

| Path | Holds |
| --- | --- |
| `core/instructions/` | Behavior rules, authored as modules and concatenated per provider |
| `core/policy/policy.json` | Command boundaries, rendered to every provider that can enforce them |
| `core/providers/` | Provider config that isn't derived from anything else |
| `core/skills/` | Reusable workflows, provider-neutral |
| `build/` | Generated. Committed on purpose. Never edit by hand |
| `scripts/` | render, validate, install, status, reverse, uninstall |
| `docs/` | Reference, loaded only when I link or request it |

`docs/AUTHORING.md` covers how I add a rule or a skill without bloating what the agent loads every session. `docs/PROVIDERS.md` covers what each provider reads and where they differ.

## Requirements

- PowerShell 7 for `render` and `validate`. Runs on Windows, Linux, and macOS.
- `jq` for the shell installer and status script.
- Nothing else. mewai doesn't install Claude Code, Codex, Antigravity CLI, or any model runtime.
