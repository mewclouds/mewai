## Antigravity CLI specifics

<important if="you are considering or using a skill">
- Skills live in `~/.gemini/skills/` and are invoked by name with a leading slash,
  the same convention as Claude Code.
</important>

<important if="you are about to edit provider settings or this instruction file">
- `~/.gemini/GEMINI.md` is rendered from `mewai`. Do not hand-edit it. Change the
  source module and re-render, otherwise the next install overwrites the edit.
</important>

- `~/.gemini/antigravity-cli/settings.json` is not managed by mewai and has no
  rendered allow, ask, or deny rules. `toolPermission` is set to
  `always-proceed`, which bypasses tool-level enforcement entirely: nothing
  mechanically stops `git push --force`, `rm -rf`, or reading a secret file the
  way it does for Claude Code and Codex. This was a deliberate tradeoff to
  avoid Antigravity's own review-prompt friction, not an oversight.
- Because nothing is enforced mechanically here, treat the Autonomy and
  Secrets sections above as the only boundary that exists on this provider.
  There is no deny rule behind them.
