# Repository instructions

Rules for maintaining mewai itself. The instructions this repository ships live in `core/instructions/` and are a separate thing.

- Author in `core/`. Never edit `build/` by hand.
- Rendering logic lives only in `scripts/render.ps1`. Keep the installers dumb.
- After changing `core/`: `pwsh ./scripts/render.ps1`, then `pwsh ./scripts/validate.ps1`. Review the `build/` diff.
- Read `docs/AUTHORING.md` before adding or removing a rule, skill, or policy entry.
- Read `docs/PROVIDERS.md` before changing rendering, install targets, or how a provider matches rules.
- Keep credentials, sessions, history, caches, and runtime databases out of this repository.
- Add a rule only when it prevents a specific, recognizable mistake.
- Add a validator check when a mistake is mechanical.
- When a check cannot run, report it as skipped. Never let an unverifiable check report as passing.
