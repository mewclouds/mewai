---
name: rule-tender
description: Route a correction into the narrowest durable rule that prevents it recurring, and delete rules that no longer earn their place. Use only when explicitly invoked with $rule-tender or /rule-tender.
---

# Rule tender

Instruction files rot in one direction. Every correction adds a bullet, nothing ever removes one, and eventually the file is too long to read and too vague to follow. This workflow makes adding a rule deliberate and removing one routine.

## When a correction arrives

1. State the actual mistake in one sentence. Not the topic, the mistake. "Used a
   subagent for a two-file search" rather than "subagent usage".
2. Decide whether it is durable. A rule is durable when the same mistake could
   happen next week in a different repository. A one-time misunderstanding is not a
   rule, it is a correction that already worked.
3. Route it to exactly one scope:

   | The mistake would recur | Put the rule in |
   | --- | --- |
   | in any repository, with any provider | `core/instructions/base.md` |
   | only with one provider or its tooling | `core/instructions/providers/<name>.md` |
   | as a command that should have been blocked or confirmed | `core/policy/policy.json` |
   | inside one repeatable workflow | that workflow's skill |
   | only in one project | that project's own `AGENTS.md` |

4. Write the narrowest rule that prevents it. Tighten an existing rule if one
   already covers the area. Do not append a second bullet that says the same thing
   more emphatically. Leave a rule bare when it applies to almost every task.
   Wrap it in `<important if>` when it only matters for a kind of work.
5. Re-render and validate.

## The test a rule must pass

Both of these, or it is a preference rather than a rule:

- **It names a specific mistake.** "Be careful with git" names nothing.
- **A violation would be recognizable.** If you cannot describe what breaking the
  rule looks like, an agent cannot tell whether it is complying.

Preferences belong in the commit message, not the instruction file.

## Removing rules

Run a removal pass whenever a module approaches its line budget. For each rule ask:

- Has this fired in real work, or was it added speculatively?
- Is it already implied by a more general rule in the same file?
- Is it enforced somewhere stronger, such as the policy or the validator? A rule
  enforced by a check does not also need to be prose.

Delete rather than reword. A shorter file that is actually read beats a complete one that is skimmed.

## Validation

- The new or changed rule appears in exactly one module.
- `scripts/validate.ps1` passes, including the duplicate and line-budget checks.
- The rendered output changed only where intended.
