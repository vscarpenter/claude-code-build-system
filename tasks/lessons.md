# Lessons

- Target macOS's default bash 3.2 in anything this repo ships: no associative arrays; use jq or temp files for lookups.
- The permission denylist blocks direct `chmod` and `rm -rf`; set exec bits with `git update-index --chmod=+x` and let the scratchpad clean itself.
- Upgrade is the install loop minus the version guard, with tier read from the manifest; resist building a second code path for it.
- Extracted prose counts as newly shipped prose: run the vinny-voice dash scan on anything copied from another repo before committing.
- The tier trees mirror target-repo layout on purpose; a new file's install destination is defined by where it sits in `tiers/`, except tier 3's mapped `local/` and `actions/` dirs in `plan_files` and the out-of-tree `standards/coding-standards.md`.
- A file the docs call canonical is only canonical if `install.sh` reads it; a "canonical copy" plus a `cp` into the tier tree is two files to edit and a silent drift waiting to happen. Pin single-source arrangements with a test that fails when a duplicate reappears.
- Emit out-of-tree sources ahead of the tree walk in `plan_files`. As a trailing `[ "$1" = N ] && printf`, a false test returns 1, and `set -e` + `pipefail` aborts the whole install for every other tier.
- Tests that mutate $ROOT (VERSION bumps, upstream-file edits) must restore it before asserting, or a failing test poisons the working tree for every later test.
- Config that the agent commands read at runtime is not automatically reaching the ops drivers: the commands parse `.build-system.json` themselves, the drivers did not, so `branchPrefix` was honored everywhere except the one pre-check that gates the night shift. When adding a config key, trace it to every consumer.
- A fixture where the buggy and fixed code produce the same answer is not a test. The first driver prefix test asserted a count of 1, which the hardcoded-`claude/` helper also returned; it took two renamed-fleet PRs to make the expected count differ from the buggy one.
