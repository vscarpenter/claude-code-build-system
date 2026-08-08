---
name: triage-prs
description: Run deterministic, provenance-bound diagnosis of failing controller PRs. This workflow never edits, pushes, or opens a PR.
---

# Triage PRs

Run this exact read-only controller entry point from the repository root:

```bash
node scripts/build-system.cjs triage --json
```

Report the controller JSON. Do not reproduce failures, edit files, change labels, run Git/GitHub delivery commands, or infer trust from a branch prefix. A PR is included only when its repository, number, branch, and current head SHA match controller-authored provenance.
