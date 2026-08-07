# tasks/todo.md

## Resuming From Here (2026-08-07)

**Done:** v2 complete on `feat/v2-installable-pipeline`. Tiered source tree, installer with manifest + three-way upgrade, generalized pipeline commands and ops drivers, hosted Actions variant, five docs, README rewrite, 21-test suite green, tier-2 pilot verified against a kanban-todos clone. Blog draft at `~/Projects/VinnyThesis/2026-08-07-the-pipeline-becomes-a-package.md`.

Adoption pass (2026-08-07, on `main`): `docs/getting-started.md` walks the first run from install to merged PR, `install.sh` prints tier-specific next steps, the tier-1 Stop hook ships inert, and the tier-3 drivers install executable. 46 tests green.

**Next:**
- [x] Push branch and open the PR (merged as PR #2, 2026-08-07).
- [ ] Tag `v2.0.0`, set CHANGELOG date.
- [ ] Migrate gsd-taskmanager to consume the packaged system (the real generalization test; out of this spec's scope by design).
- [ ] Run blog-publish-verifier on the draft, then publish.
- [ ] Retire `~/Projects/AI-Build-System/` (its coding-standards.md now lives in `standards/`).

**Blockers:** none.

**Assumptions:** blog URLs for the two prior posts follow the site's `/blog/<slug>/` pattern (April URL verified from v1 README; verify the other two pre-publish). Night shift ships as an operating-spec doc plus the tier-2 `/triage-prs` command, mirroring gsd's split (spec amended before execution).
