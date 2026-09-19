---
name: code-review
description: Perform an independent, read-only review of completed code for correctness, scope, maintainability, tests, and human-readable quality. Use only when explicitly invoked with $code-review.
---

# Code Review

## Purpose

Review completed work before it is committed or used as a foundation for later changes.

Focus on correctness, scope, maintainability, test quality, and code that reads like deliberate human-written production code.

## Workflow

1. Identify what was implemented.
2. Read the relevant task, specification, or requirements.
3. Review the exact diff, files, commit, or Git range.
4. Use a fresh reviewer subagent unless specified otherwise. This also respects the caller deciding to use another model to review.
5. Give the reviewer focused context, not the full implementation history.
6. Keep the review read-only unless fixes are explicitly requested.

## Review areas

### Requirements and scope

- Does the implementation satisfy the requirements?
- Is required behavior missing?
- Was unrelated or later-phase work added?
- Were existing behaviors changed unintentionally?

### Correctness

- Are success, failure, empty, invalid, and ambiguous cases handled?
- Are errors specific and useful?
- Are platform and compatibility assumptions correct?
- Is behavior deterministic where required?
- Could partial failure leave inconsistent state?

### Architecture

- Are responsibilities separated clearly?
- Does domain logic leak into UI or framework code?
- Do abstractions solve real problems?
- Is simple behavior wrapped in unnecessary layers?
- Does the change fit existing repository patterns?

### Tests

- Do tests verify observable behavior?
- Would they fail if the implementation were meaningfully broken?
- Are important edge cases covered?
- Are real temporary resources preferred over unnecessary mocks?
- Do tests clean up after themselves?

### Readability and maintainability

Check for:

- Comments that narrate code instead of explaining why
- Numbered-step comments, decorative banners, or artificial section dividers
- Vague names or hidden behavior
- Unexplained domain values, limits, timeouts, flags, or filename rules
- Meaningless constants for obvious literals
- Clever or compressed control flow
- Oversized functions with multiple responsibilities
- Premature helpers, wrappers, interfaces, or abstractions
- Generic errors that omit useful context

Do not demand comments where clear names and structure already explain the code.

### Follow-up reviews

This is a general code review, not a security audit.

Recommend a separate security review when changes meaningfully affect untrusted input, archive handling, filesystem mutation, process execution, network access, persistence, dependencies, privileges, or another trust boundary.

Do not report speculative vulnerabilities as confirmed findings.

## Severity

- **Critical:** Data loss, broken core behavior, severe regression, or unsafe behavior
- **Important:** Correctness gaps, missing requirements, weak recovery, major test gaps, or maintainability problems likely to spread
- **Minor:** Contained clarity, naming, duplication, or documentation improvements

Do not inflate severity.

## Output

### Strengths

List specific things done well.

### Findings

Group findings by severity.

For each finding include:

- **Location:** File and line
- **Problem:** What is wrong
- **Impact:** Why it matters
- **Recommendation:** How to fix it

Omit empty severity sections.

### Verification gaps

List anything that could not be verified and why.

### Follow-up reviews

State whether a specialized review is recommended.

### Assessment

**Ready to proceed:** Yes | With fixes | No

Give a concise technical reason.

## Rules

- Review only code and behavior actually inspected.
- Never fabricate files, line references, test results, or command output.
- Keep findings tied to requirements and real impact.
- Distinguish implementation problems from problems in the plan.
- Acknowledge strengths.
- Do not turn personal style preferences into blocking findings.
- Do not modify code unless remediation is explicitly requested.