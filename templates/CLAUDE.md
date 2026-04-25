# CLAUDE.md

This file is loaded automatically at the start of every Claude Code session. Keep it tight, roughly 200 lines, because every line is in context for the entire conversation.

The goal is to give every session a shared starting point: what this project is, how it is structured, what conventions to follow, and what gotchas to avoid.

---

## Project overview

**One paragraph.** What this project does, who it serves, and the current development phase. Replace this with your real description.

Example: "A Progressive Web App for personal task management. Single-user, offline-first, syncs to a hosted backend over WebSocket. Currently in active development on the v3 branch."

---

## Stack

Replace these with your actual stack. Be specific about versions when version-specific behavior matters.

- **Language:** TypeScript 5.4
- **Framework:** Next.js 15 (App Router)
- **Database:** PostgreSQL 16 via Prisma
- **Test runner:** Vitest
- **Package manager:** Bun
- **Lint and format:** ESLint, Biome
- **Deployment:** Vercel

---

## Project structure

Map the top-level directories. Keep this current. Drift here causes more confusion than any other section.

```
src/
├── app/              Next.js App Router pages and layouts
├── components/       React components
├── lib/              Pure functions, utilities
├── server/           Server actions and route handlers
├── db/
│   ├── schema.prisma Prisma schema
│   └── migrations/   SQL migrations
└── types/            Shared TypeScript types
tasks/
├── lessons.md        Project-specific gotchas (read at session start)
├── todo.md           In-flight work
└── spec.md           Current feature spec (when active)
.claude/
├── settings.json     Team baseline permissions and hooks
├── agents/           Specialist subagents
└── commands/         Slash commands
```

---

## Conventions

### Naming

- Files: kebab-case (`user-profile.tsx`, not `UserProfile.tsx`).
- Components: PascalCase exports.
- Functions and variables: camelCase.
- Constants: SCREAMING_SNAKE_CASE.
- Types and interfaces: PascalCase, no `I` prefix.

### Imports

- Absolute imports via path aliases (`@/lib/foo`), not relative paths beyond one level.
- Order: React, third-party, project, relative, types.

### Tests

- Co-located with source: `foo.ts` and `foo.test.ts` in the same directory.
- One behavior per test. Test names describe the behavior, not the implementation.
- Use `safeParse` for any user input. Never `parse`.

### Commits

- Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`.
- One logical change per commit. Squash before merge if needed.

---

## Commands

The exact commands to run for common tasks. Use these, not the package manager defaults.

- `bun run test` (not `bun test`, which runs Bun's built-in runner instead of Vitest).
- `bun typecheck` for the type check.
- `bun lint` for linting.
- `bun run dev` for the dev server.
- `bun run build` for the production build.
- `bunx prisma migrate dev` for local migrations.
- `bunx prisma migrate deploy` for production migrations.

---

## What not to do

These are the patterns that have bitten this project before. The full list lives in `tasks/lessons.md`. The high-frequency ones live here.

- **Do not use `parse` on user input.** Use `safeParse` and handle the error case explicitly.
- **Do not edit `.env` files.** They contain secrets and are gitignored. Ask the human to update them.
- **Do not edit lockfiles.** Run the package manager command instead.
- **Do not create new top-level directories without confirmation.** The structure above is intentional.
- **Do not write `console.log` in committed code.** Use the project's logger.
- **Do not bypass the migration framework.** All schema changes go through Prisma.

---

## Gotchas

Project-specific quirks that aren't bugs but will surprise you.

- The dev server runs on port 3000. The test runner spawns its own on 3001.
- Prisma migrations require the database to be reachable. The CI sandbox does not have one. Tests that touch the schema use `fake-prisma` instead.
- The build process strips `console.log` calls in production. Do not rely on them for production debugging.

Add to this list as you find new ones. When something bites you twice, it goes in `tasks/lessons.md`.

---

## Subagents

Two specialist reviewers are configured under `.claude/agents/`:

- `a11y-reviewer` reviews React components against WCAG AA. Read-only.
- `pg-migration-reviewer` reviews changes under `db/migrations/**` against PostgreSQL gotchas. Read-only.

Invoke them explicitly when relevant, or rely on the auto-invoke rules in `/tdd` and `/qcheck`.

---

## Slash commands

Three project commands are configured under `.claude/commands/`:

- `/qspec <feature>` generates a Spec-Driven Development spec.
- `/tdd <behavior>` runs a strict red, green, refactor cycle.
- `/qcheck` runs a skeptical staff-engineer review of changed files.

The flow is `/qspec` to think, `/tdd` to build, `/qcheck` to ship.

---

## Coding standards

The long-form rules live in `coding-standards.md` at the repo root. Read it when a slash command or subagent references it. Do not duplicate its content here.

---

## When to update this file

- A new top-level directory or major dependency.
- A new convention the team agreed on.
- A new gotcha that is high-frequency enough to belong here rather than in `lessons.md`.

Treat updates to this file as engineering work. Open a PR. Get a review.

When this file passes 250 lines, look for content that should move to `coding-standards.md` or `tasks/lessons.md` instead.
