---
name: session-recap
description: Close out substantive work with a recap that leaves the user able to explain the change themselves. Use only when explicitly invoked with $session-recap or /session-recap.
---

# Session recap

Produce a short account of what happened that the user could repeat to a colleague without rereading the transcript. This is the closing half of the explainability contract, not a status report.

## Scope

Use this after substantive work. Skip it for trivial mechanical edits, where a recap teaches nothing and costs attention.

## Structure

Write these five, in order, and keep the whole thing under roughly 200 words.

1. **What changed.** The files and the behavior, not the process. Name each file
   once, with a path.
2. **Why it was needed.** The cause, stated so it would still make sense to someone
   who never saw the failure.
3. **The mechanism.** How the fix actually works. This is the part that transfers to
   the next problem and the part most often skipped.
4. **How it was verified.** The exact commands or observations, and honestly what
   was not verified.
5. **What to watch for.** The thing most likely to break next, or the assumption
   most likely to stop holding.

## Rules

- Report only what actually ran. Never present an expected result as an observed one.
- Name what remains unverified rather than rounding it up to done.
- Point at real locations as `path/to/file.ts:42`.
- Skip anything the user demonstrated they already know during the session.
- Do not restate the diff in prose. If a line is only readable as an English
  translation of the code, cut it.
- No new work in a recap. If something needs doing, say so and stop.

## Optional close

When the session covered unfamiliar ground, add one question the user could answer to check their own understanding. One, not a quiz.
