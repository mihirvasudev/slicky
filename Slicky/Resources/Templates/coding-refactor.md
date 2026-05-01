Transform this refactoring or cleanup request into a structured, safe-migration prompt for an AI coding agent.

The rewritten prompt MUST contain all of the following sections:

## Goal
One sentence on what the codebase looks like after this refactor and why it's better.

## Scope
- Files and modules in scope (list them explicitly)
- Files and modules explicitly OUT of scope (do not touch)
- The interface/API contract that must remain unchanged after refactoring

## Current State
- What exists now (fill in what's implied)
- Why it's a problem (coupling, duplication, performance, readability, type safety, etc.)

## Target State
- What the code should look like after
- New structure, naming conventions, or patterns to use
- Any new abstractions to introduce

## Migration Plan
**Step 1 — [name]:** Smallest safe change. No behavior change. Commit.
**Step 2 — [name]:** Next extraction or rename. Commit.
**Step 3 — [name]:** Wire it all together. Commit.
Each step must leave the codebase in a working, compilable, test-passing state.

## Preservation Requirements
- Public API/interface must remain identical (or changes must be explicitly listed)
- All existing tests must pass after each step
- No performance regressions
- TypeScript/type safety must improve or stay the same

## Verification
- Run existing test suite after each step
- Specific behavior to manually verify end-to-end
- Before/after comparison of key files if helpful

---
Original prompt:
<<<{{ORIGINAL}}>>>

Frontmost app / context: {{APP}}
Surrounding text: {{SURROUNDING}}
