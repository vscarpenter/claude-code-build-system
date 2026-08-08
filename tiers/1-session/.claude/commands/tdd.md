---
name: tdd
description: Run a strict red, green, refactor cycle continuously after the feature spec or design is approved. Auto-invokes specialist reviewers based on files touched.
argument-hint: <behavior description>
---

Run a strict red, green, refactor cycle for the behavior described by the
user's current request. In Claude slash-command mode, the supplied arguments
are: $ARGUMENTS

If `$ARGUMENTS` appears literally instead of being substituted, ignore that
marker and use the user's request. This keeps the same source usable as an
Agent Skill in harnesses that do not implement Claude's argument substitution.

## The cycle

### Phase 1: Red

1. Read the relevant `tasks/spec.md` if one exists for this feature. If no spec exists, ask whether to create one with `/qspec` first.
2. Read `CLAUDE.md`, `coding-standards.md`, and `tasks/lessons.md` for relevant context and gotchas.
3. Write a single failing test that covers the behavior. One test, not many. The test must:
   - Reference the specific acceptance criterion or behavior under test in a comment.
   - Use the project's test framework and conventions.
   - Fail for the right reason (the behavior does not exist yet), not for setup or compilation reasons.
4. Run the test. Confirm it fails. Capture the failure output.
5. Record the test code and failure output as the red-phase evidence, then continue to Phase 2. Stop only if the test fails for an unexpected reason or exposes a material ambiguity in the approved spec.

### Phase 2: Green

Proceed when the user has approved the feature spec/design or explicitly invoked this workflow for a well-scoped behavior. That approval covers the complete red-green-refactor pass; do not add a per-test approval gate.

1. Write the minimum implementation that makes the test pass. No extra features. No defensive code beyond what the test requires.
2. Run the test. Confirm it passes.
3. Run the full test suite. Confirm nothing else broke.
4. Output the implementation and the test results.

### Phase 3: Refactor

1. Look for duplication, unclear naming, or violations of the project's coding standards.
2. Refactor without changing behavior. Run the tests after each refactor step to confirm nothing breaks.
3. If the refactor would touch protected areas (see auto-invoke rules below), invoke the relevant specialist subagent before committing.

## Auto-invoke rules

Before completing Phase 3, check the changed files. If any of these patterns match, invoke the corresponding specialist subagent and address its findings:

- Files matching `db/migrations/**` or `migrations/**` or `prisma/migrations/**`: invoke `pg-migration-reviewer`.
- Files matching `**/*.tsx`, `**/*.jsx`, or component files: invoke `a11y-reviewer`.

The subagent runs read-only. You decide whether to act on its findings before completing the cycle.

## Discipline rules

- **Do not skip Phase 1.** The red step is the most commonly skipped and the most valuable. It proves the test is real and the behavior is genuinely missing.
- **One test per cycle.** If the behavior needs multiple tests, run the cycle multiple times.
- **Do not write implementation code in Phase 1.** Even tempting "while I'm here" changes belong in a separate cycle.
- **Run the full suite in Phase 2.** A passing new test is not enough. Confirm nothing else broke.

## Output format

Keep a compact evidence record for each phase and report it when the full cycle completes:

```
## Phase 1: Red

[test code]

[test failure output]

Red evidence captured; continuing to Green.
```

Run Phases 1 through 3 continuously. Pause only for a genuine blocker, a material change to the approved design, or a safety boundary that requires new authority.
