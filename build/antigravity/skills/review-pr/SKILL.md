---
name: review-pr
description: Perform a focused, read-only review of a pull request against its diff, requirements, and linked issues. Evaluates whether reported issue fixes actually resolve the underlying problem, whether proposed improvements add unnecessary complexity, and audits code quality in ADHD-friendly output. Use only when explicitly invoked with $review-pr or /review-pr <number>.
---

# Review PR

Perform an independent, read-only code review of a GitHub pull request. Evaluates whether code fixes what it claims to fix, weeds out unneeded complexity, and presents findings in a concise, ADHD-friendly format. Subagents may be used depending on the scope of the PR.

## Scope

- Strictly read-only on GitHub. Never post review comments, submit reviews, approve, reject, label, or merge on GitHub. The user handles all GitHub interactions.
- Confined to the target repository and the pull request changes.
- Web search is for verifying external libraries, API contracts, or error patterns, not for taking actions.
- If requirements or linked issues are ambiguous or missing, do not guess. Stop and ask.

## Workflow

1. Identify the pull request number from the invocation argument or context.
2. Fetch the pull request metadata and discussion with `gh pr view <number> --json title,body,comments,labels,state,author,headRefName,baseRefName`. Read the full description and comments for context.
3. Inspect the pull request diff with `gh pr diff <number>`. If local testing or deeper workspace inspection is required, the branch can be checked out with `gh pr checkout <number>`.
4. If the pull request claims to resolve an issue, fetch the issue thread with `gh issue view <issue-number> --json title,body,comments,labels,state`. Compare the actual diff against the reported issue to confirm whether the code genuinely fixes the root cause rather than masking symptoms.
5. If the pull request introduces an improvement or refactor rather than addressing a documented issue, evaluate necessity: does this solve a concrete problem, or does it introduce unnecessary abstractions, configuration, and maintenance overhead?
6. Check for ambiguity or missing information. If requirements, acceptance criteria, or reproduction steps are unclear, stop immediately. Treat ambiguity as a hard stop to clarify with the maintainer or implementer rather than assuming intent.
7. Review the code changes across these areas:
   - **Requirements and scope:** Does the implementation satisfy requirements? Is required behavior missing? Was unrelated work added? Were existing behaviors changed unintentionally?
   - **Correctness:** Are edge cases handled (empty, invalid, failure)? Are errors specific and useful? Are compatibility assumptions sound? Is state consistent after partial failure?
   - **Architecture:** Are responsibilities cleanly separated? Does domain logic leak? Do abstractions earn their keep or add unnecessary layers? Does code match repository patterns?
   - **Tests:** Do tests verify observable behavior rather than implementation details? Would they fail if broken? Are edge cases covered? Do temporary resources clean up properly?
   - **Readability and maintainability:** Flag narrating comments, decorative banners, vague names, unexplained domain constants, clever control flow, oversized functions, or generic errors.
   - Search the web when external libraries, error signatures, or compatibility constraints need validation.
8. Format the output adhering to the rules in `/i-have-adhd` to keep the review focused and actionable.

## Output

Present the review in ADHD-friendly structure:

### Verdict

**Ready to merge:** Yes | With fixes | No

State the concise technical rationale in one or two sentences.

### Issue verification or necessity check

State whether the PR genuinely fixes the claimed issue, or whether the proposed improvement is justified versus adding unneeded complexity.

### Blockers

List high-priority findings only. Focus strictly on blockers and correctness problems, omitting minor style preferences. Cap the list at 5 items maximum.

For each finding include:

- **Location:** File and line number
- **Problem:** What is wrong
- **Impact:** Why it matters
- **Recommendation:** How to fix it

If there are no blockers, state that clearly in one line.

### Next action

End with exactly one concrete action that can be taken immediately in under two minutes.

## Validation

- Nothing was written to GitHub (no comments, reviews, or state changes).
- Ambiguity or missing requirements triggered a hard stop before proceeding.
- Output started directly with the verdict and omitted filler, preamble, and pleasantries.
- Findings focused strictly on blockers, capped at 5 items.
- The review concluded with a single concrete next action.
