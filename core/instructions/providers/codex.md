## Codex specifics

- Skills live in `~/.agents/skills/` and are invoked with a leading `$`. Codex also
  selects them automatically from their descriptions, so a skill description states
  its trigger and its boundaries.
- Command rules live in `~/.codex/rules/default.rules` and are rendered from `mewai`.
  Do not hand-edit them. Change `core/policy/policy.json` and re-render.
- A `forbidden` decision is final. Do not retry the command through a wrapper such as
  `rtk`, a shell invocation, or a script that hides it.
- `~/.codex/config.toml` is rendered from `mewai` too. Codex writes project trust
  entries into it directly, which then show up as drift. Fold a trust entry into
  `core/providers/codex/config.toml` to keep it, or reinstall to discard it.
- Codex reads `AGENTS.md` from the repository root down to the working directory.
  Files under `docs/` are references and are not loaded automatically, so link them
  from an `AGENTS.md`, a skill, or the prompt.
