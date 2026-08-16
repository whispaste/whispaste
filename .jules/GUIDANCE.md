# Guidance for automated PRs (shared, all personas)

Two real PRs from this bot collided with work the maintainer had already done:

- A "dedicated clear-search string" PR contradicted a maintainer commit that had
  just gone the opposite direction (merging two search-clear keys into one).
- A "precompile RegExp for search filtering" PR duplicated a fix already merged
  days earlier under a different file/description.

Both cost real review time and produced CI noise. Before opening a PR:

1. **Check whether it's already done — and whether it's already been rejected.**
   `git log --oneline -20 -- <the file(s) you're about to touch>` only shows
   *merged* history; it will never show you that the exact same idea was
   proposed and closed 10 times before, because rejected PRs never touch
   `dev`. Also run `gh pr list --state closed --search "<widget/file/topic>"`
   and skim the closing comments before opening a new PR on that topic. If a
   commit already touches the exact function/behavior you're about to
   "improve," or a closed PR was rejected for reasons that still apply, stop.
2. **Target `dev`, not `main`.** `main` is a periodic squash-sync of `dev` and
   can be weeks stale; diffing against it produces phantom "missing" fixes
   that already exist on `dev`. If your run configuration lets you pick a base
   branch, it should be `dev`.
3. **Read your own persona's memory file first** (this directory) — check it
   before repeating an already-flagged non-issue or a suggestion the
   maintainer already declined. These files are maintained by the human
   maintainer directly on `dev`, independent of whether any given PR gets
   merged — so a "REJECTED, do not resubmit" entry here is authoritative even
   for a topic where you can't find a matching merged commit. Treat the
   entries as caveated, not just additive: a later entry correcting or
   narrowing an earlier one supersedes it for that specific case.
4. **One targeted change per PR**, scoped to what your persona's mandate
   covers (performance / a11y / security / small feature). No drive-by
   refactors.
5. **Verify before pushing, or say you couldn't.** Run this repo's actual gate
   commands (see root `CLAUDE.md` — `flutter analyze --fatal-infos
   --fatal-warnings`, `flutter test`) before opening or updating a PR. If your
   sandbox can't run them (SDK mismatch, missing toolchain), say so explicitly
   in the PR body and stop after one attempt — don't push a second guess-fix
   commit for a CI failure you can't reproduce locally. (Concretely: `skip` on
   `testWidgets` is `bool?`, not a reason string — `skip: 'some reason'` is a
   compile error, not a working skip.)

(This repo's top-level `AGENTS.md` is committed and un-gitignored specifically
so it reaches this file — see `git log` on `AGENTS.md` for why. Read it first;
it just points here.)
