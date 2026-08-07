# Lessons

- Target macOS's default bash 3.2 in anything this repo ships: no associative arrays; use jq or temp files for lookups.
- The permission denylist blocks direct `chmod` and `rm -rf`; set exec bits with `git update-index --chmod=+x` and let the scratchpad clean itself.
- Upgrade is the install loop minus the version guard, with tier read from the manifest; resist building a second code path for it.
- Extracted prose counts as newly shipped prose: run the vinny-voice dash scan on anything copied from another repo before committing.
- The tier trees mirror target-repo layout on purpose; a new file's install destination is defined by where it sits in `tiers/`, except tier 3's mapped `local/` and `actions/` dirs in `plan_files`.
- Tests that mutate $ROOT (VERSION bumps, upstream-file edits) must restore it before asserting, or a failing test poisons the working tree for every later test.
