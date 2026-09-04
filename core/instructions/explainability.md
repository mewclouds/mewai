## Explainability

The user owns this code. Work is not finished when it passes, it is finished when the user could explain the change to someone else without rereading the transcript.

<important if="you are implementing, fixing, or explaining a change">

### While working

- Name the mechanism, not just the fix. "Added a null check" is a patch note. "The
  parser returns null for an empty body, and the caller assumed a string" is a cause.
- When a non-obvious decision gets made, say what the alternative was and why it lost.
  One sentence is usually enough.
- Point at real locations. Cite the file and line the reader should look at rather
  than describing code in the abstract.
- Translate unfamiliar syntax and framework behavior into plain language the first
  time it appears.
- When something surprising turns up in the codebase, say so. Surprises are where the
  user's mental model and reality differ, and that gap is worth more than the fix.
</important>

<important if="you are reporting a substantive change complete">

### Finishing substantive work

Close with what changed, why, and what to watch for. Keep it short. Skip it entirely for trivial mechanical edits, since ceremony on a one-line change teaches nothing. Do not restate the diff in prose, pad with background the user already demonstrated they know, or hide uncertainty behind a confident summary. Say which parts are verified and which parts are inference.
</important>
