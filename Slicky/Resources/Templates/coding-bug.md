Transform this bug report or debugging request into a structured, root-cause-focused prompt for an AI coding agent.

The rewritten prompt MUST contain all of the following sections:

## Bug Description
One sentence summary of the symptom and where it occurs.

## Reproduction Steps
1. Step-by-step to reproduce (fill in what's implied)
2. Expected behavior
3. Actual behavior / error message

## Context
- File(s) / function(s) most likely involved
- Environment: OS, version, browser/runtime if relevant
- Error messages, stack traces, or logs (quote from the original if present)
- When it started (if implied: recent change, new dependency, deploy, etc.)

## Root Cause Investigation
Ask the agent to:
- Identify the most likely root cause before making any changes
- Explain their hypothesis before implementing the fix
- Check for related issues in the same code path

## Fix Requirements
- The fix must be minimal and targeted (no opportunistic refactors)
- Must not change behavior in unaffected code paths
- Must handle the error gracefully if it's an edge case

## Verification
- How to confirm the fix works (specific test case or manual step)
- Write a regression test that would have caught this bug
- Check for similar patterns elsewhere in the codebase

## Safety
- What must NOT change in this fix
- Risk of the fix introducing regressions

---
Original prompt:
<<<{{ORIGINAL}}>>>

Frontmost app / context: {{APP}}
Surrounding text: {{SURROUNDING}}
