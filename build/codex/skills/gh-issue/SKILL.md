---
name: gh-issue
description: Investigate a GitHub issue end to end using the gh CLI. Pulls the full thread, cross-references related issues and PRs in the same repository, searches the web for corroborating reports, and reasons about root cause in the codebase. Produces a plain-language summary, and asks clarifying questions instead of guessing when the report is thin. Read-only, scoped to one repository. Use only when explicitly invoked with $gh-issue or /gh-issue <number>.
---

# GitHub issue decoder

Turns a raw GitHub issue into something a non-technical reporter and the user can both act on: what's actually being reported, what's known about it, and what's still unclear. This is investigation, not triage automation. It never writes to GitHub.

## Scope

- Read-only. Never comment on, label, close, or edit the issue, and never push or open a PR as part of this workflow.
- Confined to the one repository the issue belongs to. Related issues and PRs are searched within that repository only, not across the org.
- Web search is for corroboration and hints, not for taking any action.

## Workflow

1. Identify the repository the issue number belongs to from context. If it is not obvious, ask rather than guess.
2. Pull the full thread with `gh issue view <number> --json title,body,comments,labels,state,author,createdAt,closedAt`. Read every comment, not just the opening body, and note any logs, screenshots, or attachments referenced in the text.
3. Search the same repository for related material: `gh issue list`, `gh pr list`, and any issues or PRs linked from the thread. Flag likely duplicates or issues that already answer this one.
4. Investigate root cause by searching the codebase for the described behavior. A miss in the codebase is never proof the cause isn't there: also search the web for the error text, symptom, or repo name, since upstream bugs and prior discussion often explain what a local search alone misses.
5. If the report is vague, missing repro steps, or the evidence points more than one way, stop and say exactly what's missing. Propose a way to test a hypothesis rather than asserting one. Prefer a back-and-forth over jumping to a conclusion.
6. State a cause as confirmed only when something backs it: a reproduced behavior, a matching code path, a corroborating report. Otherwise state it as a labeled hypothesis, not a fix.

## Output

A summary in plain, explanatory language, clear to a non-technical reporter without being dumbed down:

- What's being reported, in your own words.
- What was found: relevant code, related issues or PRs, related discussion elsewhere.
- Root cause, confirmed only with evidence behind it, otherwise a labeled hypothesis with what would confirm or rule it out.
- Open questions aimed at getting whatever is missing from the reporter or the user.

## Validation

- Nothing was written to GitHub: no comment, label, or state change.
- Every "not in the codebase" claim was paired with a web check, not asserted alone.
- No root cause is stated as fact without evidence backing it.
