# Lessons

Project-specific gotchas. Reviewed at the start of every session via `CLAUDE.md`. When something bites you twice, it goes here.

Each entry is one or two lines. Each entry has saved at least an hour of debugging.

The format is intentionally flat. Do not over-organize.

---

## Examples

Replace these with your real gotchas as you find them.

- Use `bun run test`, not `bun test`. The latter runs Bun's built-in runner instead of Vitest, and our test files use Vitest syntax.
- Always `safeParse`, never `parse`, on user input. `parse` throws and turns boundary errors into 500s.
- The Prisma client must be a singleton in dev. Hot-reload otherwise leaks connections until the pool is exhausted.
- `toast.error()` for user-facing errors, not `alert()`. We rely on the toast for accessibility (live region) and for error tracking (the toast hook reports to Sentry).
- Do not edit migrations after they have been applied to any environment. Add a follow-up migration instead.
- The auth middleware does not protect API routes by default. Wrap them in `withAuth` explicitly.
- `Image` from `next/image` requires width and height when not using `fill`. Missing these causes layout shift.
- The dev server runs on port 3000. The Vitest UI runs on port 3001. The Storybook runs on 6006. Do not expect any of these to be free.
- Auto-generated Prisma columns (e.g., `updatedAt`) cannot be referenced in custom indexes via `@@index`. Use a migration with raw SQL instead.
- The import parser strips trailing whitespace before validation. If you need to preserve exact strings, escape them upstream.

---

## Format guidance

- One line where possible.
- Two lines when the *why* matters and isn't obvious.
- Lead with the rule. Follow with the reason.
- Use backticks for code. Use plain text for everything else.
- Newest entries at the top, or grouped by area. Pick one and stick with it.

---

## When to add an entry

- Something bit you twice.
- Something cost more than an hour the first time.
- Something would have been obvious to a senior engineer who was already in the codebase, but isn't documented anywhere else.

## When to remove an entry

- The underlying issue is fixed and won't recur.
- The convention has changed and the lesson is no longer accurate.
- The lesson has been superseded by a better-placed rule (in `coding-standards.md` or a code comment).
