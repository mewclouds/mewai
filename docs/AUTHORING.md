# Authoring

A rule earns its space when both are true:

1. It names a specific mistake.
2. A violation would be recognizable.

Otherwise it is a preference. Put it in the commit message.

One rule, one place. The validator fails on duplicates.

| Recurs | Put it in |
| --- | --- |
| any repo, any provider | `core/instructions/base.md` |
| a command to block or confirm | `core/policy/policy.json` |
| one workflow | that skill |
| one project | that project's `AGENTS.md` |

Do not also write a prose copy of something `policy.json` or `validate.ps1` already enforces.

`<important if>` is for rules that only matter for a kind of work. Do not wrap a prohibition in a condition that only matches after the prohibited action has started.

Line budgets live in `scripts/validate.ps1`. Exceeding one means cut, not raise.

## Skills

A skill is a workflow you would re-explain. It is not a knowledge dump.

`validate.ps1` requires front matter `name` matching the directory, and a `description` that states when to use it.

Keep project-specific knowledge in that project.

## Policy

Every rule needs `id`, `decision`, `why`, and commands.

- Visible to other people, or annoying to undo: `confirm`
- Unrecoverable, or destroys work: `forbid`
