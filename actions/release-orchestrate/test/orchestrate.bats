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

# Negated commands are exempt from errexit inside a test, so absence checks
# go through a function whose non-zero return does fail the test.
logged() { grep -q -- "$1" "$GH_LOG"; }
not_logged() { ! grep -q -- "$1" "$GH_LOG"; }
list_calls() { grep -c "^run list --workflow=$1 " "$GH_LOG" || true; }
sleeps() { grep -c '^sleep 10$' "$GH_LOG" || true; }

@test "creates the release once every language's push run has succeeded" {
  export LANGUAGES=go,typescript
  use_fixture release-go.yml success
  use_fixture release-typescript.yml success
  orchestrate
  [ "$status" -eq 0 ]
  logged '^release create v1.2.3 --title v1.2.3 --generate-notes --latest$'
  grep -q '^status=success$' "$GITHUB_OUTPUT"
  grep -q '^release-url=https://github.example/releases/tag/v1.2.3$' "$GITHUB_OUTPUT"
  [ "$(sleeps)" -eq 0 ]
}

@test "accepts the version with or without the v prefix" {
  export VERSION=1.2.3
  use_fixture release-go.yml success
  orchestrate
  [ "$status" -eq 0 ]
  logged '^release create v1.2.3 '
}

@test "accepts build metadata in the version" {
  export VERSION=1.2.3+build.7
  use_fixture release-go.yml success-build-metadata
  orchestrate
  [ "$status" -eq 0 ]
  logged '^release create v1.2.3+build.7 '
}

@test "polls only push-triggered runs and matches the tag by headBranch, not position" {
  use_fixture release-go.yml older-and-current
  orchestrate
  [ "$status" -eq 0 ]
  logged '--event=push'
  logged '--all'
  not_logged '--branch'
  [ "$(list_calls release-go.yml)" -eq 1 ]
}

@test "a newer tag's successful push run does not stand in for the requested one" {
  use_fixture release-go.yml other-tag-only
  orchestrate
  [ "$status" -eq 1 ]
  not_logged '^release create'
  [[ "$output" == *"go (no push-triggered run of release-go.yml for v1.2.3)"* ]]
}

@test "finds the tag's run behind ten newer pushes" {
  use_fixture release-go.yml buried-eleven-deep
  orchestrate
  [ "$status" -eq 0 ]
  logged '^release create v1.2.3 '
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
  [ "$(sleeps)" -eq 2 ]
  grep -q '^status=success$' "$GITHUB_OUTPUT"
}

@test "a failed run reports partial-failure with the in-place rerun command" {
  export LANGUAGES=go,typescript
  use_fixture release-go.yml success
  use_fixture release-typescript.yml failure
  orchestrate
  [ "$status" -eq 1 ]
  not_logged '^release create'
  grep -q '^status=partial-failure$' "$GITHUB_OUTPUT"
  grep -q '^release-url=$' "$GITHUB_OUTPUT"
  [[ "$output" == *"::error::Release v1.2.3 incomplete. Failed: typescript (failure, run 303)."* ]]
  [[ "$output" == *"gh run rerun 303 --failed"* ]]
  [[ "$output" == *"gh run rerun 777"* ]]
  [[ "$output" != *"gh workflow run release-typescript.yml"* ]]
}

@test "a cancelled run gets a full rerun, since --failed has no failed jobs to pick" {
  use_fixture release-go.yml cancelled
  orchestrate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed: go (cancelled, run 304)"* ]]
  [[ "$output" == *"  gh run rerun 304"$'\n'* ]]
  [[ "$output" != *"gh run rerun 304 --failed"* ]]
}

@test "a failure is final: no further polling once every language has completed" {
  use_fixture release-go.yml failure
  orchestrate
  [ "$status" -eq 1 ]
  [ "$(list_calls release-go.yml)" -eq 1 ]
  [ "$(sleeps)" -eq 0 ]
}

@test "the same push run, re-run in place, satisfies a second orchestrator invocation" {
  use_fixture release-go.yml failure
  orchestrate
  [ "$status" -eq 1 ]
  [[ "$output" == *"gh run rerun 303 --failed"* ]]
  rm -rf "$GH_STATE" && mkdir -p "$GH_STATE"
  use_fixture release-go.yml failure-rerun-succeeded
  orchestrate
  [ "$status" -eq 0 ]
  logged '^release create v1.2.3 '
}

@test "a failed run that is re-run while another language is pending goes back to pending" {
  export LANGUAGES=go,ruby
  use_fixture release-go.yml failure 0
  use_fixture release-go.yml in-progress-303 1
  use_fixture release-go.yml failure-rerun-succeeded 2
  use_fixture release-ruby.yml in-progress 0
  use_fixture release-ruby.yml in-progress 1
  use_fixture release-ruby.yml success 2
  orchestrate
  [ "$status" -eq 0 ]
  logged '^release create v1.2.3 '
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
  not_logged '^release create'
}

@test "polls while elapsed time is below TIMEOUT, then gives up" {
  use_fixture release-go.yml none
  orchestrate
  [ "$status" -eq 1 ]
  [ "$(list_calls release-go.yml)" -eq 3 ]
  [ "$(sleeps)" -eq 3 ]
  grep -q '^status=partial-failure$' "$GITHUB_OUTPUT"
  [[ "$output" == *"Timed out after 30s"* ]]
}

@test "a still-running run at timeout is reported with its id and status" {
  use_fixture release-go.yml in-progress
  orchestrate
  [ "$status" -eq 1 ]
  [[ "$output" == *"go (run 404 still in_progress)"* ]]
}

@test "a transient gh failure is retried, not treated as a result" {
  export GH_LIST_FAIL_ONCE=1
  use_fixture release-go.yml success
  orchestrate
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::gh run list failed for release-go.yml; will retry: HTTP 502: bad gateway"* ]]
  [ "$(list_calls release-go.yml)" -eq 2 ]
}

@test "a transient gh failure keeps the last observation for the recovery message" {
  export LANGUAGES=go,ruby TIMEOUT=20
  use_fixture release-go.yml failure 0
  use_fixture release-ruby.yml none
  export GH_LIST_FAIL_AFTER=2
  orchestrate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed: go (failure, run 303)"* ]]
  [[ "$output" == *"gh run rerun 303 --failed"* ]]
  [[ "$output" != *"gh run rerun  --failed"* ]]
}

@test "diagnostics on stderr from a successful gh call do not break parsing" {
  export GH_STDERR_NOISE=1
  use_fixture release-go.yml success
  orchestrate
  [ "$status" -eq 0 ]
  logged '^release create v1.2.3 '
}

@test "trims whitespace in the languages list" {
  export LANGUAGES="go, rust"
  use_fixture release-go.yml success
  use_fixture release-rust.yml success
  orchestrate
  [ "$status" -eq 0 ]
  logged '--workflow=release-rust.yml'
}

@test "trims only the edges: internal whitespace is still invalid" {
  export LANGUAGES="go, type script"
  orchestrate
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::Invalid language ' type script'"* ]]
  [ ! -s "$GH_LOG" ]
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

@test "rejects a version that could not be a tag name" {
  export VERSION='1.2.3") | .[0] | (.'
  orchestrate
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::Invalid version"* ]]
  [ ! -s "$GH_LOG" ]
}

@test "rejects a zero or non-numeric poll interval and timeout" {
  export POLL_INTERVAL=0
  orchestrate
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::Invalid poll-interval '0'"* ]]
  export POLL_INTERVAL=10 TIMEOUT=08
  orchestrate
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::Invalid timeout '08'"* ]]
  [ ! -s "$GH_LOG" ]
}

@test "a release-create failure fails the step" {
  export GH_RELEASE_FAIL=1
  use_fixture release-go.yml success
  orchestrate
  [ "$status" -ne 0 ]
  ! grep -q '^status=' "$GITHUB_OUTPUT" || false
}

@test "a release-view failure fails the step after the release exists" {
  export GH_VIEW_FAIL=1
  use_fixture release-go.yml success
  orchestrate
  [ "$status" -ne 0 ]
  logged '^release create v1.2.3 '
  ! grep -q '^status=' "$GITHUB_OUTPUT" || false
}
