## Claude Code specifics

- Skills live in `~/.claude/skills/` and are invoked by name with a leading slash.
  A skill marked "only when explicitly invoked" must not be triggered on its own.
- The permission rules in `~/.claude/settings.json` are rendered from `mewai`. Do not
  hand-edit that file. Change `core/policy/policy.json` and re-render,
  otherwise the next install overwrites the edit.
- Deny and ask rules apply in every permission mode, including `bypassPermissions`.
  A denied command is a boundary, not a prompt that failed to appear.
- Use subagents only when the user asks for them or a skill calls for one. They start
  without the current context and re-derive what this session already established.
- Reference files as `path/to/file.ts:42` so they are clickable.
