#!/usr/bin/env bats
# Behaviour of orchestrate.sh against a stubbed gh (test/stubs/gh). Run with
# `bats actions/release-orchestrate/test`.

setup() {
  ACTION_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
  export GH_STATE="$BATS_TEST_TMPDIR/state"
  export GH_FIXTURES="$BATS_TEST_TMPDIR/fixtures"
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  export GITHUB_RUN_ID=777
  mkdir -p "$GH_STATE" "$GH_FIXTURES"
  : > "$GH_LOG"
  : > "$GITHUB_OUTPUT"
  export PATH="$ACTION_DIR/test/stubs:$PATH"
  export VERSION=v1.2.3 LANGUAGES=go POLL_INTERVAL=10 TIMEOUT=30
}

# use_fixture <workflow> <scenario> [poll-index]
use_fixture() {
  local name="$1.json"
  [ -z "${3:-}" ] || name="$1.$3.json"
  cp "$ACTION_DIR/test/fixtures/$2.json" "$GH_FIXTURES/$name"
}

orchestrate() {
  run "$ACTION_DIR/orchestrate.sh"
}

list_calls() {
  grep -c "^run list --workflow=$1 " "$GH_LOG" || true
}

@test "creates the release once every language's push run has succeeded" {
  export LANGUAGES=go,typescript
  use_fixture release-go.yml success
  use_fixture release-typescript.yml success
  orchestrate
  [ "$status" -eq 0 ]
  grep -q '^release create v1.2.3 --title v1.2.3 --generate-notes --latest$' "$GH_LOG"
  grep -q '^status=success$' "$GITHUB_OUTPUT"
  grep -q '^release-url=https://github.example/releases/tag/v1.2.3$' "$GITHUB_OUTPUT"
  ! grep -q '^sleep' "$GH_LOG"
}

@test "accepts the version with or without the v prefix" {
  export VERSION=1.2.3
  use_fixture release-go.yml success
  orchestrate
  [ "$status" -eq 0 ]
  grep -q '^release create v1.2.3 ' "$GH_LOG"
}

@test "polls only push-triggered runs and matches the tag by headBranch" {
  use_fixture release-go.yml older-and-current
  orchestrate
  [ "$status" -eq 0 ]
  grep -q -- '--event=push' "$GH_LOG"
  ! grep -q -- '--branch' "$GH_LOG"
  [ "$(grep -c '^run list ' "$GH_LOG")" -eq 1 ]
}

@test "keeps polling while a run is in progress and stops asking about languages that already succeeded" {
  export LANGUAGES=go,ruby
  use_fixture release-go.yml success
  use_fixture release-ruby.yml in-progress 0
  use_fixture release-ruby.yml in-progress 1
  use_fixture release-ruby.yml success 2
  orchestrate
  [ "$status" -eq 0 ]
  [ "$(list_calls release-go.yml)" -eq 1 ]
  [ "$(list_calls release-ruby.yml)" -eq 3 ]
  [ "$(grep -c '^sleep 10$' "$GH_LOG")" -eq 2 ]
  grep -q '^status=success$' "$GITHUB_OUTPUT"
}

@test "a failed run reports partial-failure with the in-place rerun command" {
  export LANGUAGES=go,typescript
  use_fixture release-go.yml success
  use_fixture release-typescript.yml failure
  orchestrate
  [ "$status" -eq 1 ]
  ! grep -q '^release create' "$GH_LOG"
  grep -q '^status=partial-failure$' "$GITHUB_OUTPUT"
  grep -q '^release-url=$' "$GITHUB_OUTPUT"
  [[ "$output" == *"::error::Release v1.2.3 incomplete. Failed: typescript (failure, run 303)."* ]]
  [[ "$output" == *"gh run rerun 303 --failed"* ]]
  [[ "$output" == *"gh run rerun 777"* ]]
  [[ "$output" != *"gh workflow run release-typescript.yml"* ]]
}

@test "a failure is final: no further polling once every language has completed" {
  use_fixture release-go.yml failure
  orchestrate
  [ "$status" -eq 1 ]
  [ "$(list_calls release-go.yml)" -eq 1 ]
  ! grep -q '^sleep' "$GH_LOG"
}

@test "a workflow_dispatch rerun is invisible: the push run's failure still stands" {
  use_fixture release-go.yml dispatch-after-failure
  orchestrate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed: go (failure, run 605)"* ]]
  [[ "$output" == *"gh run rerun 605 --failed"* ]]
  [[ "$output" == *"dispatch is a dry-run rehearsal on a separate run that it will never detect"* ]]
}

@test "a workflow_dispatch run alone never satisfies the wait" {
  use_fixture release-go.yml dispatch-only
  orchestrate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Timed out after 30s waiting for: go (no push-triggered run of release-go.yml for v1.2.3)"* ]]
  ! grep -q '^release create' "$GH_LOG"
}

@test "times out after TIMEOUT seconds of polling at POLL_INTERVAL" {
  use_fixture release-go.yml none
  orchestrate
  [ "$status" -eq 1 ]
  [ "$(grep -c '^sleep 10$' "$GH_LOG")" -eq 3 ]
  [ "$(list_calls release-go.yml)" -eq 4 ]
  grep -q '^status=partial-failure$' "$GITHUB_OUTPUT"
  [[ "$output" == *"Timed out after 30s"* ]]
}

@test "a still-running run at timeout is reported with its id" {
  use_fixture release-go.yml in-progress
  orchestrate
  [ "$status" -eq 1 ]
  [[ "$output" == *"go (run 404 still running)"* ]]
}

@test "a transient gh failure is retried, not treated as a result" {
  export GH_LIST_FAIL_ONCE=1
  use_fixture release-go.yml success
  orchestrate
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::gh run list failed for release-go.yml; will retry: HTTP 502: bad gateway"* ]]
  [ "$(list_calls release-go.yml)" -eq 2 ]
}

@test "trims whitespace in the languages list" {
  export LANGUAGES="go, rust"
  use_fixture release-go.yml success
  use_fixture release-rust.yml success
  orchestrate
  [ "$status" -eq 0 ]
  grep -q -- '--workflow=release-rust.yml' "$GH_LOG"
}

@test "rejects an empty languages list without calling gh" {
  export LANGUAGES=" , "
  orchestrate
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::languages input is empty"* ]]
  [ ! -s "$GH_LOG" ]
}

@test "rejects a language that cannot name a workflow" {
  export LANGUAGES="go,release-go.yml"
  orchestrate
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::Invalid language 'release-go.yml'"* ]]
  [ ! -s "$GH_LOG" ]
}

@test "a release-create failure fails the step" {
  export GH_RELEASE_FAIL=1
  use_fixture release-go.yml success
  orchestrate
  [ "$status" -ne 0 ]
  ! grep -q '^status=' "$GITHUB_OUTPUT"
}
