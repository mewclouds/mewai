## Cursor specifics

- Skills live in `~/.agents/skills/` and are invoked by name with a leading slash.
  Cursor also scans `~/.claude/skills/`, so the same skill may appear twice. Use
  either copy. Do not install a third tree under `~/.cursor/skills/`.
- `~/.cursor/rules/mewai.mdc` is rendered from `mewai`. Do not hand-edit it.
  Change the source module and re-render, otherwise the next install overwrites
  the edit.
- Command boundaries live in `~/.cursor/hooks.json` and
  `~/.cursor/hooks/mewai-policy.ps1`, rendered from `mewai`. Do not hand-edit
  them. Change `core/policy/policy.json` and re-render.
- A hook `deny` is final. Do not retry the command through a wrapper such as
  `rtk`, a shell invocation, or a script that hides it.
- Confirm-tier commands other than `git commit` run here. Do not stop to
  ask for `git push`, `gh`, or `npm install`. `git commit` is deny: give the
  user that exact command. Do not run it. Do not wrap it. Cursor's hook `ask`
  does not prompt in `Run Everything`.
- `forbid` is a deny that must not be handed over. Do not give the user a
  force-push or hard reset to run as a substitute.
- Autonomy is Cursor's `Run Everything` mode. Unlisted commands run. The hook
  is the only mechanical stop.
- Cloud Agents do not load `~/.cursor/` user hooks or user skills. They only
  see project files in the repository.
