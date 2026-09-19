# mewai

This is my workflow for AI-assisted development: one source for agent
instructions, command boundaries, and skills. Rendered into the different
harnesses I tinker with.

I author in `core/`. `build/` is generated and committed, so a `git diff` shows
me exactly what a change did before I install it.

```powershell
pwsh ./scripts/render.ps1
pwsh ./scripts/validate.ps1
pwsh ./scripts/install.ps1
pwsh ./scripts/status.ps1
```

On Unix the same jobs are `install.sh`, `status.sh`, `uninstall.sh`, and
`reverse.sh`. Install and uninstall take `--dry-run`. Uninstall needs `--confirm`
to actually delete anything. `reverse` pulls settings I changed in a harness
back into `core/providers/`.

PowerShell 7 for render and validate. `jq` for the shell scripts.

`docs/AUTHORING.md` when adding a rule, skill, or policy entry.
`docs/PROVIDERS.md` when a provider's matching behavior matters.
