## Codex specifics

<important if="you are considering or using a skill">
- Skills live in `~/.agents/skills/` and are invoked with a leading `$`. Codex also
  selects them automatically from their descriptions, so a skill description states
  its trigger and its boundaries.
</important>

<important if="you are about to edit provider settings or this instruction file">
- Command rules live in `~/.codex/rules/default.rules` and are rendered from `mewai`.
  Do not hand-edit them. Change `core/policy/policy.json` and re-render.
</important>

- A `forbidden` decision is final.
- Codex reads `AGENTS.md` from the repository root down to the working directory.
  Files under `docs/` are references and are not loaded automatically, so link them
  from an `AGENTS.md`, a skill, or the prompt.
