## OpenCode specifics

<important if="you are considering or using a skill">
- Skills live in `~/.agents/skills/`, the same directory Codex reads. OpenCode
  loads one through its built-in `skill` tool rather than a typed sigil, and picks
  it from the description alone, so a description without a stated trigger gets
  selected for adjacent work it was never written for.
</important>

<important if="you are about to edit provider settings or this instruction file">
- Command rules live in `~/.config/opencode/opencode.jsonc` and are rendered from
  `mewai`. Do not hand-edit that file. Change `core/policy/policy.json` and
  re-render, otherwise the next install overwrites the edit.
</important>

- A `deny` decision is final.
- Anything the policy does not name runs without a prompt. OpenCode has no
  classifier behind the rules the way Claude Code's auto mode does, so the Autonomy
  section above is the only thing covering an unlisted destructive command.
- OpenCode reads `AGENTS.md` from the repository root down to the working
  directory.
