# Guidance for automated PRs (shared, all personas)

Two real PRs from this bot collided with work the maintainer had already done:

- A "dedicated clear-search string" PR contradicted a maintainer commit that had
  just gone the opposite direction (merging two search-clear keys into one).
- A "precompile RegExp for search filtering" PR duplicated a fix already merged
  days earlier under a different file/description.

Both cost real review time and produced CI noise. Before opening a PR:

1. **Check whether it's already done.** `git log --oneline -20 -- <the file(s)
   you're about to touch>` and skim the last ~15 commit subjects on `dev` for
   the area. If a commit already touches the exact function/behavior you're
   about to "improve," stop — don't propose a second fix for the same issue,
   and don't propose the inverse of a change that just landed on purpose.
2. **Target `dev`, not `main`.** `main` is a periodic squash-sync of `dev` and
   can be weeks stale; diffing against it produces phantom "missing" fixes
   that already exist on `dev`. If your run configuration lets you pick a base
   branch, it should be `dev`.
3. **Read your own persona's memory file first** (this directory) — check it
   before repeating an already-flagged non-issue or a suggestion the
   maintainer already declined.
4. **One targeted change per PR**, scoped to what your persona's mandate
   covers (performance / a11y / security / small feature). No drive-by
   refactors.

(Note: this repo keeps a top-level `AGENTS.md` deliberately local-only —
see `.gitignore`'s PROTECTED block — so this file is the actual guidance
surface visible in a clone.)
