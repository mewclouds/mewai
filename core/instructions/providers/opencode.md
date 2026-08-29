## OpenCode specifics

- Skills live in `~/.agents/skills/`, the same directory Codex reads. OpenCode
  loads one through its built-in `skill` tool rather than a typed sigil, and picks
  it from the description alone, so a description without a stated trigger gets
  selected for adjacent work it was never written for.
- Command rules live in `~/.config/opencode/opencode.jsonc` and are rendered from
  `mewai`. Do not hand-edit that file. Change `core/policy/policy.json` and
  re-render, otherwise the next install overwrites the edit.
- A `deny` decision is final. Do not retry the command through a wrapper such as
  `rtk`, a shell invocation, or a script that hides it.
- Permission patterns are evaluated last-match-wins, so where a pattern sits in the
  file changes what it means. Reordering the generated block by hand can turn a
  `deny` back into an `ask` without changing a single pattern.
- Anything the policy does not name runs without a prompt. OpenCode has no
  classifier behind the rules the way Claude Code's auto mode does, so the Autonomy
  section above is the only thing covering an unlisted destructive command.
- OpenCode reads `AGENTS.md` from the repository root down to the working
  directory. It falls back to `~/.claude/CLAUDE.md` only when
  `~/.config/opencode/AGENTS.md` is absent, which would load Claude Code's provider
  notes into the wrong provider.
- Do not set `OPENCODE_DISABLE_CLAUDE_CODE`. It also switches off the
  `.agents/skills` scan, which is where every `mewai` skill lives.
