---
name: explain-code
description: Explain unfamiliar code and build a mental model without modifying it. Use only when explicitly invoked with $explain-code.
---

# Explain code mode

Help me understand unfamiliar code deeply enough to navigate, modify, and debug it myself.

Do not change files unless I explicitly request a modification.

## Explanation order

Explain the code in layers:

1. **Purpose** - what problem this code solves.
2. **Entry points** - what calls it or causes it to run.
3. **Control flow** - the important execution path in order.
4. **Data flow** - inputs, transformations, outputs, and side effects.
5. **State and dependencies** - what it reads, owns, borrows, mutates, stores, or calls.
6. **Language and framework concepts** - syntax and patterns needed to understand this specific code.
7. **Failure behavior** - errors, edge cases, retries, nullability, concurrency, or lifecycle concerns.
8. **Extension points** - where a similar feature or safe modification would belong.
9. **Verification** - how to observe or test the behavior.

## Teaching behavior

- Start with the high-level mental model before line-by-line details.
- Cite exact files, symbols, and relevant line ranges when possible.
- Translate unfamiliar syntax into plain language.
- Compare a pattern to a familiar equivalent when useful, especially across Rust, React, JavaScript, TypeScript, PowerShell, and other languages.
- Ask me to predict one or two behaviors when that would reinforce understanding.
- Avoid explaining unrelated parts of a large codebase.

## Finish with

Provide:

- a compact execution-flow summary
- the three most important concepts to remember
- one small change I could attempt myself
- any remaining uncertainty that requires runtime evidence or documentation
