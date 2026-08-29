---
name: reply-draft
description: Draft a reply to send to whoever the user just diagnosed an issue with or reviewed a PR for, in plain human language instead of the default robotic tone. Use only when explicitly invoked with $reply-draft or /reply-draft.
---

# Reply draft

Turns the diagnosis or review the user just finished in this conversation into a reply they can paste straight to the other person. The default reply style reads robotic and harsh: backticks around every term, em dashes, semicolons, technical detail dumped on someone who didn't ask for it. This produces the version a person would actually send.

## Scope

- General purpose. Applies after any diagnosis, PR review, or troubleshooting discussion in the current conversation, not only `gh-issue` threads.
- Drafting only. Never posts, comments, or sends anything. The user always pastes it themselves.

## Workflow

1. Take the diagnosis or finding as discussed earlier in this conversation as the basis for the reply. If the user also gives rough notes or a bullet draft alongside the invocation, treat those as the content to polish rather than writing from scratch.
2. Determine the recipient's technical level from context already established in the conversation (how they were described, how they wrote, what kind of report they filed). If it genuinely isn't clear, ask the user directly rather than guessing.
3. If what was actually resolved or found is itself unclear or the conversation didn't land on a concrete cause or fix, stop and ask the user what to say rather than drafting around a guess.
4. Draft the reply:
   - Lead with why it's happening, then what fixes it. No preamble, no throat-clearing.
   - For a non-technical recipient: plain words only, no backtick-formatted terms, no internal implementation detail they didn't ask for.
   - For a technical recipient: technical detail and code blocks are fine where they carry real information.
   - No em dashes, no semicolons joining clauses.
   - Warm, direct, like a person wrote it. Not blunt, not corporate, not padded with hedging.
5. Output the reply in Markdown so code blocks or commands render correctly when pasted, followed by one line stating the tone/audience call made (e.g. "kept this non-technical, no mention of a dev background").

## Output

A Markdown reply block ready to copy-paste, followed by a single-line rationale for the tone and audience choice. Nothing else.

## Validation

- The draft contains no em dashes, no clause-joining semicolons, and no backtick-wrapped terms when written for a non-technical recipient.
- The reply states the cause and the fix before anything else.
- If the underlying finding or the recipient's technical level was unclear, the skill asked instead of guessing.
