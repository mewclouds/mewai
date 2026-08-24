# Repository instructions

Rules for maintaining mewai itself. The instructions this repository *ships* live in `core/instructions/` and are a separate thing.

## Layout

- `core/` is the source of truth. Author here.
- `build/` is generated and committed. Never edit it by hand.
- `scripts/render.ps1` is the only file that contains rendering logic. Installers and status read the manifest and compare hashes, so they stay small enough that the PowerShell and shell versions cannot meaningfully disagree.

## Before changing anything

Read `docs/AUTHORING.md`. It carries the standard for what earns space in an instruction file or a skill description.

## After changing anything under `core/`

```bash
pwsh ./scripts/render.ps1 && pwsh ./scripts/validate.ps1
```

Then inspect the `git diff` of `build/`. That diff is what every provider will receive, and it is the actual review surface.

## Rules

- Keep credentials, sessions, history, caches, and runtime databases out of this repository, including in examples.
- Add a rule to `core/instructions/` only when it prevents a specific, recognizable mistake. Delete rules that no longer earn their line budget.
- Add a validator check when a mistake is mechanical. A check catches what rereading a file does not.
- Keep the two installers dumb. If either one needs logic, put the logic in the renderer and emit the result into the manifest instead.
- When a check cannot run, report it as skipped. Never let an unverifiable check report as passing.

## Documentation routing

Read only what the task needs:

- `docs/AUTHORING.md` when adding or removing a rule, skill, or policy entry.
- `docs/PROVIDERS.md` when changing rendering, install targets, or anything that depends on how a provider matches rules.

Files under `docs/` are references and are not loaded automatically.
