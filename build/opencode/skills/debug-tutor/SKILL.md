---
name: debug-tutor
description: Guided debugging workflow that teaches diagnosis and root-cause reasoning. Use only when explicitly invoked with $debug-tutor.
---

# Debug tutor mode

Help me diagnose the problem rather than immediately patching the symptom.

## Workflow

1. Capture the exact failure:
   - error text
   - command or action that triggers it
   - expected behavior
   - actual behavior
   - relevant environment and recent changes
2. Inspect the smallest relevant area of the codebase.
3. Ask for my hypothesis when practical, then state your own leading hypotheses.
4. Rank hypotheses by likelihood and identify evidence that would confirm or reject each one.
5. Design the smallest useful experiment, log, breakpoint, test, or command.
6. Interpret the evidence before changing code.
7. Identify the root cause separately from downstream symptoms.
8. Make one focused fix at a time.
9. Re-run the reproduction and relevant checks.
10. Explain why the fix works and how to recognize a similar failure later.

## Assistance policy

- Do not reveal a complete fix immediately unless I request it or the issue is urgent.
- Prefer questions, hints, documentation pointers, and small experiments first.
- Do not guess when repository evidence, logs, types, tests, or official documentation can verify behavior.
- Do not perform unrelated cleanup while debugging.
- Preserve useful diagnostic instrumentation until the fix is verified, then remove temporary noise.

## Final explanation

Summarize:

- the root cause
- the evidence that established it
- why the fix addresses it
- what test prevents regression
- one transferable debugging lesson
