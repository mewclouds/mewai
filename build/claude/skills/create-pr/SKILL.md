---
name: create-pr
description: Draft a pull request title and body from the current branch's changes, match an existing PULL_REQUEST_TEMPLATE if the repository has one, get the user's approval on the draft, then open the PR. Use only when explicitly invoked with $create-pr or /create-pr.
---

# Create PR

A PR description written from the diff, not from memory of what the branch was supposed to do. This workflow drafts it, shows the user the exact title and body before anything is created, and only opens the PR once they approve.

## Workflow

1. Look at what actually changed: `git log` and `git diff` against the base branch, not just the most recent commit. The description has to match the real diff.
2. Check for a template: `.github/PULL_REQUEST_TEMPLATE.md`, `.github/PULL_REQUEST_TEMPLATE/*.md`, or `PULL_REQUEST_TEMPLATE.md` at the repo root. If one exists, match its section structure. If not, use the shape in Body below.
3. Write a plain title describing the change, not a commit-convention prefix. "Add retry to the sync worker", not "feat: add retry to the sync worker".
4. Write the body: why this PR exists, what it solves, and a Verification section every time, regardless of what the template does or doesn't include. Verification shows how the change was tested, or how a reviewer can test it themselves. For a bug fix, show before and after. For a feature, describe how it works.
5. If the change looks like it would benefit from a screenshot, gif, or short video (anything visual or UI-facing), ask the user if they have one to include before finalizing the draft. Don't ask for changes that are purely internal or non-visual.
6. Show the draft before touching GitHub. Present it plainly, something like:

   TITLE
   <the title, no wrapping code block, it's one line>

   DESCRIPTION
   ```
   <the full body, in a single code block so it's easy to copy>
   ```

7. Wait for approval or edits. Revise and show it again if the user asks for changes.
8. Once approved, ask whether this should be a draft PR or a regular one, unless the user already said which. Then run `gh pr create` with the approved title and body, adding `--draft` if that's what was chosen.

## Style

Write like the rest of this repository: no em dashes, no semicolons joining clauses, no robotic or templated-sounding phrasing. Use inline code and code blocks only where they clarify something concrete, like a command, a file path, or an error message, not as decoration. A body that's all backticks reads as generated, not written.

## Scope

- Operates on the current repository and the current branch only.
- Does not push commits. If the branch isn't pushed yet, say so before trying to open the PR.
- Does not create or edit anything on GitHub until the user has approved the draft.

## Validation

- The title has no commit-convention prefix.
- The body has a Verification section, whether or not the template did.
- The user approved the exact title and body before `gh pr create` ran.
- `gh pr create` was called as a draft or a regular PR, matching what the user chose.
