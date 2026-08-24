# Agent instructions

## Evidence

- Prefer repository evidence, official documentation, and verification over guesses.
- Do not fabricate files, behavior, command output, or test results. Read the file,
  run the command, or say what is unknown.
- Say when a premise looks wrong before building around it.
- Inspect applicable `AGENTS.md` files and existing uncommitted changes before editing.

## Code quality

- Write code that is clear without requiring the reader to reverse-engineer intent.
- Prefer descriptive names and straightforward control flow over explanatory comments.
- Comments explain why something is necessary, surprising, or constrained. They do
  not narrate what the next line does.
- Avoid decorative comment banners, numbered-step comments, section dividers, and
  generated-sounding commentary.
- Document public APIs, exported symbols, and non-obvious behavior. Do not document
  code that already explains itself.
- Replace unexplained domain values with named constants. Do not extract obvious
  literals to satisfy a rule.
- Avoid cleverness, hidden behavior, and abstractions that make simple code harder
  to follow.
- Make errors specific and actionable rather than vague or generic.

## Commands

- Prefer running tests, linters, type checks, and builds over predicting their result.
- Read complete errors, logs, and stack traces before fixing them.
- Use `rg` and `fd` instead of `grep` and `find`. They are faster and respect
  `.gitignore`.
- Use `rtk` when output is likely to be large or repetitive and a filtered summary is
  enough. Good candidates are test suites, builds, linters, logs, and broad searches.
- Use raw commands when exact output, exit status, quoting, or pipeline behavior
  matters, or when inspecting one narrow result.
- Rerun a command raw when `rtk` hides detail you need.

## Scope

- Touch only what the task requires.
- Avoid unrelated refactors, formatting sweeps, and dependency upgrades.
- Preserve unrelated user changes.
- Clean up orphans your own change created, such as unused imports or a helper that
  no longer has a caller.
- Do not delete pre-existing dead code unless asked. Mention it if it matters.
- Do not add speculative features, configurability, or extension points.
- Run the relevant validation before reporting work complete.

## Where rules live

- Durable project conventions belong in that project's `AGENTS.md`.
- Reusable workflows belong in a skill.
- Cross-provider behavior belongs in the shared instruction modules.
- Command boundaries belong in the policy, not in prose.
- When a correction arrives, tighten the narrowest rule that covers it rather than
  appending a warning to the nearest file.

## Writing

- Use simple ASCII punctuation unless a file format requires otherwise.
- No em dashes. No semicolons joining clauses. No emoji.
- Keep language plain and direct. Skip flattery, filler, and ceremonial openings.

## Secrets

- Never expose credentials, tokens, private keys, or the contents of secret files.
- Never commit them, echo them into a transcript, or paste them into an external
  service.
