# Night shift: deterministic diagnosis

Version 3 deliberately removes autonomous model-authored PR repair. The nightly driver calls `build-system.cjs triage`, which reads the pause switch, queries open PR checks, and matches every candidate against controller-authored provenance.

```text
scheduler → triage-run.sh → controller triage
  triage:paused or unavailable? → stop
  failing same-repo PR?          → compare repo + PR + branch + head SHA
  exact provenance?              → report attention-required
  mismatch?                      → reject from automation
```

No harness is invoked. No worktree is created. No label, branch, comment, commit, push, or PR is mutated. A prefix alone is never trusted, because fork and human branch names are attacker-controlled and same-repository branches can be changed after verification.

When diagnosis reports a failing trusted PR, inspect the CI failure. Move the linked issue to `agent:retryable` only when a new controller run is the right response; otherwise use `ready-for-human`. A future automated repair loop must reuse the same lease, worktree, controller policy, delivery, provenance, and conformance contract before it can ship.

Add `triage:paused` to any open issue to stop diagnosis. Remove it to resume.
