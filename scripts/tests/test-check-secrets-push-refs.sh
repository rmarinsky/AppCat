#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

export CHECK_SECRETS_TEST_LOG="$TEST_DIR/gitleaks.log"
export PATH="$REPO_ROOT/scripts/tests/fakes:$PATH"

old_update=1111111111111111111111111111111111111111
new_update=2222222222222222222222222222222222222222
new_branch=3333333333333333333333333333333333333333
deleted_ref=4444444444444444444444444444444444444444
zero=0000000000000000000000000000000000000000

printf '%s\n' \
    "refs/heads/main $new_update refs/heads/main $old_update" \
    "refs/heads/topic $new_branch refs/heads/topic $zero" \
    "(delete) $zero refs/heads/removed $deleted_ref" \
    | lefthook run pre-push --force

grep -Fx -- "git --redact --no-banner --log-opts=$old_update..$new_update" "$CHECK_SECRETS_TEST_LOG"
grep -Fx -- "git --redact --no-banner --log-opts=$new_branch" "$CHECK_SECRETS_TEST_LOG"
if grep -Fq -- "$deleted_ref" "$CHECK_SECRETS_TEST_LOG"; then
    echo 'Deleted refs must not trigger a commit scan.' >&2
    exit 1
fi
