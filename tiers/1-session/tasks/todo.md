# Todo

In-flight work for this project. Updated continuously during a session.

Discipline: never end a session with this file out of sync with reality.

---

## Resuming From Here

The single most important section. A fresh Claude Code session reads this first to pick up where the last one left off, without you re-explaining context.

Replace the example with your real state.

**Example:**

> Working on the user profile feature (spec at `tasks/spec.md`).
>
> Phase 2 (Green) is complete for AC1 and AC2. AC3 (validation errors) needs:
> - Test in `src/components/profile/profile-form.test.tsx`
> - Implementation that wires the validation error state to `<FormError>` from `@/components/ui/form-error`
>
> Blocked on a question for the human: should AC4 (avatar upload) be in this PR or split? Default to splitting unless told otherwise.
>
> Last commit: `feat: profile form skeleton with AC1 and AC2 coverage`

---

## Active

The current task. One thing.

- [ ] Implement AC3: validation errors

## Up next

The next two or three things, in order.

- [ ] Specialist review with `a11y-reviewer`
- [ ] `/qcheck` before opening the PR
- [ ] Open the PR with the spec link

## Blocked

Things waiting on a human, an external system, or another piece of work.

- [ ] AC4 (avatar upload): waiting on the decision about scope
- [ ] Backend endpoint for profile: waiting on the API team

## Done (this session)

Move items here as you complete them. Clear at session end or after the merge.

- [x] AC1: Display existing profile data on load
- [x] AC2: Submit form persists changes

---

## When to update this file

- After every significant action: file edit, test pass, decision, blocker found.
- Before stopping for the day, however briefly.
- Before invoking `/qcheck`, so the reviewer has context.

## When to clear this file

- After the feature merges.
- When you start a new feature (move the contents to a feature-specific archive if you want history).

## Format

Use checkboxes. They render in most markdown previews and read clearly in plain text.
