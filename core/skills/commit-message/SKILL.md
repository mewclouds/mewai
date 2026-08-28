---
name: commit-message
description: Write a commit message for the current changes, grounded in the real diff and status, following Conventional Commits 1.0.0. Returns the message only and never stages or commits. Use only when explicitly invoked with $commit-message or /commit-message.
---

# Commit message

A commit message written from the actual working tree, not from memory of what the change was supposed to do. It reads the full diff, asks about anything ambiguous, and returns exactly the message.

## Workflow

1. Inspect first: run `git status` and `git diff HEAD` so the message covers staged and unstaged changes together. Untracked files show in status but not in diff, so read any that belong to the change.
2. Clarify ambiguities with the user before writing. If the diff mixes unrelated changes, or the intent behind something is unclear, ask rather than guess.
3. Write the subject line: imperative mood, aim for 50 characters or fewer, no trailing punctuation, prefixed with a Conventional Commits 1.0.0 type (feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert).
4. Write the body only when it carries information the subject cannot. Never repeat the subject in the body, wrap lines at 72 characters, and omit the body entirely when the subject says it all.
5. Separate the subject from the body with a blank line.

## Output

The commit message and nothing else. No meta-commentary about the task, no diff output echoed back.

## Scope

- Read-only. Never runs `git add`, `git commit`, or anything else that changes state. The user runs the commit.
- General purpose for any repository, with no project-specific conventions.

## Validation

- Every claim in the message traces to something visible in the diff or status, not to an assumption about the change.
- Subject is imperative, 50 characters or fewer where possible, has no trailing punctuation, and carries a Conventional Commits 1.0.0 type.
- The response contains the message only.
- Nothing was staged or committed.
