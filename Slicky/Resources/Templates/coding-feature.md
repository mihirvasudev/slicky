Transform this feature request into a complete, structured implementation prompt for an AI coding agent (Cursor, Claude Code, Codex).

The rewritten prompt MUST contain all of the following sections:

## Goal
One sentence describing the user-visible outcome. Start with a verb.

## Context
- Files and modules most likely involved (infer from the prompt)
- Relevant existing patterns, APIs, or libraries implied
- Known constraints or non-negotiables

## Acceptance Criteria
- [ ] 4–7 concrete, independently testable criteria
- [ ] Cover the happy path, at least one edge case, and error states
- [ ] Each criterion should be verifiable by looking at code or running a test

## Phased Execution
**Phase 1 — [descriptive name]:** What to build first. Must compile and have a clean stopping point.
**Phase 2 — [descriptive name]:** Next layer. Clean stopping point.
**Phase 3 — [descriptive name]:** (Add phases as the complexity warrants.)
Keep each phase small enough to complete in one focused session.

## Test Plan
- Manual verification steps per phase
- Unit or integration tests to write
- Edge cases: empty input, large payloads, network failure, concurrent calls, etc.
- Regression: what existing behavior must not break

## Safety & Risk Notes
- What existing code could break
- What NOT to touch or refactor in this PR
- Rollback plan if this breaks something in production
- Performance implications if any

## Out of Scope
- Explicit non-goals (what this PR will NOT do)
- Future follow-up work to track separately

---
Original prompt:
<<<{{ORIGINAL}}>>>

Frontmost app / context: {{APP}}
Surrounding text (for file/module hints): {{SURROUNDING}}
