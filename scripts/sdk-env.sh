# shellcheck shell=bash
# sdk-env.sh — sourced by scripts/check.sh and the git hooks.
#
# Git hands its hooks GIT_DIR, GIT_INDEX_FILE, GIT_WORK_TREE and GIT_PREFIX.
# Flutter reads its own version with `git describe` in the SDK checkout;
# with these set, that runs against this repository instead and the SDK
# reports 0.0.0-unknown, so `pub get` fails the SDK constraint. The git
# calls of the hooks need the variables (a commit of named paths uses a
# temporary index), so only flutter and dart run without them.

flutter() { env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_PREFIX flutter "$@"; }
dart() { env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_PREFIX dart "$@"; }
