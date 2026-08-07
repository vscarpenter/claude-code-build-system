# Implementation notes (ledger)

- 2026-08-07: Spec amended before execution: tier-3 'night-shift command' corrected to a durable operating-spec doc (docs/night-shift.md in targets); the per-run command is tier 2's triage-prs.md. Matches how gsd-taskmanager actually splits the two artifacts.
- 2026-08-07: Plan T5 deviation: apply_labels + cumulative tier planning were implemented in T3's installer (ahead of the plan's sequence), so T5's tests landed green as regression coverage instead of red/green. Behavior verified via gh PATH-shim mock (15 creates logged; MANUAL fallback on unauthed gh).
