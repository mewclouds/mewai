# Authoring

More context is not better context. Everything in `core/instructions/` and every skill description is loaded before the agent has read a single line of your code, and it competes for attention with the actual task. This file is the standard for what earns that space.

## The test a rule must pass

Both of these, or it is a preference:

1. **It names a specific mistake.** "Be careful with migrations" names nothing. "Do
   not edit a migration that has already run" names something.
2. **A violation would be recognizable.** If you cannot say what breaking the rule
   looks like, an agent cannot tell whether it is complying, and you cannot tell
   whether the rule ever helped.

Preferences go in the commit message.

## Write rules that constrain, not rules that encourage

Encouragement produces agreement, not behavior. "Strive for high quality code" is agreed with and ignored. "Return a non-zero exit code when the operation fails" is either done or not done.

Prefer the form: do this specific thing, or never do this specific thing, in this identifiable situation.

## Where a rule goes

One rule lives in exactly one place. The validator fails the build on duplicates across modules, because a rule stated twice will eventually be edited once.

| The mistake would recur | Put it in |
| --- | --- |
| in any repository, with any provider | `core/instructions/base.md` |
| only with one provider or its tooling | `core/instructions/providers/<name>.md` |
| as a command that should be blocked or confirmed | `core/policy/policy.json` |
| inside one repeatable workflow | that workflow's skill |
| only in one project | that project's own `AGENTS.md` |

If a rule is enforced by the policy or by the validator, it does not also need to be prose. Enforcement beats instruction, and the prose copy is what goes stale.

## Line budgets

Enforced by `scripts/validate.ps1`:

| File | Budget |
| --- | --- |
| `base.md` | 120 lines |
| every other instruction module | 60 lines |
| any rendered instruction file | 400 lines |

Exceeding one is a signal to cut something, not to raise the number. Raising a budget is a decision that belongs in a commit message with a reason.

## Style

Also enforced. No em dashes, no en dashes, no smart quotes, no clause-joining semicolons, no emoji, no TODO placeholders. Semicolons inside backtick code spans are fine, since those are shell and code syntax rather than prose.

These exist because the instructions tell agents to write that way. A file that breaks its own rule teaches the agent that the rules are decorative.

## Writing a skill

A skill is a workflow you would otherwise re-explain. It is not a place to park knowledge that has no trigger.

Requirements, all enforced:

- Front matter with `name` matching the directory name, and a `description`.
- The description states when to use it. Providers select skills from descriptions
  alone, so a description that only names a topic gets selected for adjacent tasks it
  was never meant for.
- No TODO placeholders.

Beyond that: write imperative steps with explicit inputs and outputs, say what validation proves the work is done, and keep project-specific knowledge out of it. A skill that only applies to one repository belongs in that repository.

## Adding a policy rule

Every rule needs an `id`, a `decision`, a `why`, and its commands. The `why` is required because it renders into the Codex `justification` field, which is what the agent is shown when the command is blocked. A justification that explains the reason prevents the agent from looking for a way around the rule.

Choose the decision by what happens if the command runs when it should not have:

- Recoverable in seconds: `allow`
- Visible to other people, or annoying to undo: `confirm`
- Unrecoverable, or destroys work: `forbid`

Before adding a `forbid`, check that the prefix actually matches the form you are worried about. See the flag-position and wrapper sections in `PROVIDERS.md`.

## After any change

```bash
pwsh ./scripts/render.ps1 && pwsh ./scripts/validate.ps1
```

Then read the `git diff` of `build/`. That diff is the real review: it shows what every provider will actually receive.
