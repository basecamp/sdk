#!/usr/bin/env bash
# Waits for the per-language release workflows that a tag push triggered, then
# creates the GitHub Release once every one of them has succeeded.
#
# Inputs arrive as environment variables (set by action.yml):
#   VERSION        release version, with or without the leading "v"
#   LANGUAGES      comma-separated languages; each needs a release-<lang>.yml
#   POLL_INTERVAL  seconds between polls
#   TIMEOUT        seconds to wait before giving up
#   GH_TOKEN       token for gh
#
# Only runs with event=push are considered. A `gh workflow run release-<lang>.yml`
# dispatch starts a separate rehearsal run that never publishes, so it is deliberately
# invisible here; the recovery for a failed publish is `gh run rerun <id> --failed` on
# the push-triggered run, which keeps its id and event.
set -euo pipefail

# shellcheck disable=SC2153  # VERSION is an action input
version="${VERSION#v}"
tag="v${version}"
timeout="${TIMEOUT:-1800}"
interval="${POLL_INTERVAL:-30}"

if [[ ! "$version" =~ ^[0-9A-Za-z._-]+$ ]]; then
  echo "::error::Invalid version '${VERSION}' (expected a tag name such as 1.2.3 or v1.2.3)"
  exit 1
fi
for n in "timeout=$timeout" "poll-interval=$interval"; do
  if [[ ! "${n#*=}" =~ ^[1-9][0-9]*$ ]]; then
    echo "::error::Invalid ${n%%=*} '${n#*=}' (expected a positive integer of seconds)"
    exit 1
  fi
done

langs=()
IFS=',' read -ra raw_langs <<< "${LANGUAGES:-}"
for raw in "${raw_langs[@]}"; do
  lang="${raw#"${raw%%[![:space:]]*}"}"
  lang="${lang%"${lang##*[![:space:]]}"}"
  [ -n "$lang" ] || continue
  if [[ ! "$lang" =~ ^[a-z0-9-]+$ ]]; then
    echo "::error::Invalid language '$raw' in languages input (expected e.g. go,typescript,rust)"
    exit 1
  fi
  langs+=("$lang")
done
if [ "${#langs[@]}" -eq 0 ]; then
  echo "::error::languages input is empty"
  exit 1
fi

# Parallel arrays: state is pending | success | failed; run_id / run_url are
# filled in once the tag's push run has been seen.
states=()
run_ids=()
run_urls=()
conclusions=()
statuses=()
for _ in "${langs[@]}"; do
  states+=("pending")
  run_ids+=("")
  run_urls+=("")
  conclusions+=("")
  statuses+=("")
done

gh_stderr=$(mktemp)
trap 'rm -f "$gh_stderr"' EXIT

echo "Waiting for release workflows for $tag..."

elapsed=0
while [ "$elapsed" -lt "$timeout" ]; do
  all_done=true

  for i in "${!langs[@]}"; do
    lang="${langs[$i]}"
    [ "${states[$i]}" = "success" ] && continue

    workflow="release-${lang}.yml"
    # --event push: only the run the tag push started can publish. Filter by
    # headBranch because --branch does not reliably resolve tag-triggered runs.
    # A transient gh failure keeps the previous observation and is retried.
    if ! result=$(gh run list \
      --workflow="$workflow" \
      --event=push \
      --limit=20 \
      --json databaseId,status,conclusion,headBranch,url \
      -q "[.[] | select(.headBranch == \"$tag\")] | .[0]" 2> "$gh_stderr"); then
      echo "::warning::gh run list failed for $workflow; will retry: $(cat "$gh_stderr")"
      all_done=false
      continue
    fi
    [ -n "$result" ] || result='{}'
    run_status=$(jq -r '.status // "not_found"' <<< "$result")
    run_conclusion=$(jq -r '.conclusion // "none"' <<< "$result")
    run_ids[i]=$(jq -r '.databaseId // empty' <<< "$result")
    run_urls[i]=$(jq -r '.url // empty' <<< "$result")
    conclusions[i]="$run_conclusion"
    statuses[i]="$run_status"

    if [ "$run_status" = "completed" ]; then
      if [ "$run_conclusion" = "success" ]; then
        states[i]="success"
        echo "  $lang: success"
      else
        states[i]="failed"
        echo "::error::$lang release workflow failed ($run_conclusion): ${run_urls[$i]}"
      fi
    else
      # Covers a failed run that was re-run while another language was still pending.
      states[i]="pending"
      all_done=false
    fi
  done

  [ "$all_done" = true ] && break

  sleep "$interval"
  elapsed=$((elapsed + interval))
  echo "  Waiting... ($elapsed/${timeout}s)"
done

failed=()
unseen=()
rerun_cmds=()
for i in "${!langs[@]}"; do
  case "${states[$i]}" in
    success) ;;
    failed)
      failed+=("${langs[$i]} (${conclusions[$i]}, run ${run_ids[$i]})")
      # --failed re-runs failed jobs only; a cancelled or skipped run has none.
      if [ "${conclusions[$i]}" = "failure" ]; then
        rerun_cmds+=("gh run rerun ${run_ids[$i]} --failed")
      else
        rerun_cmds+=("gh run rerun ${run_ids[$i]}")
      fi
      ;;
    *)
      if [ -n "${run_ids[$i]}" ]; then
        unseen+=("${langs[$i]} (run ${run_ids[$i]} still ${statuses[$i]})")
      else
        unseen+=("${langs[$i]} (no push-triggered run of release-${langs[$i]}.yml for $tag)")
      fi
      ;;
  esac
done

if [ "${#failed[@]}" -eq 0 ] && [ "${#unseen[@]}" -eq 0 ]; then
  echo "All release workflows succeeded. Creating GitHub Release..."

  gh release create "$tag" \
    --title "$tag" \
    --generate-notes \
    --latest

  release_url=$(gh release view "$tag" --json url -q '.url')

  echo "release-url=$release_url" >> "$GITHUB_OUTPUT"
  echo "status=success" >> "$GITHUB_OUTPUT"
  echo "GitHub Release created: $release_url"
  exit 0
fi

echo "status=partial-failure" >> "$GITHUB_OUTPUT"
echo "release-url=" >> "$GITHUB_OUTPUT"

summary="Release $tag incomplete."
[ "${#failed[@]}" -eq 0 ] || summary="$summary Failed: $(IFS='; '; echo "${failed[*]}")."
[ "${#unseen[@]}" -eq 0 ] || summary="$summary Timed out after ${elapsed}s waiting for: $(IFS='; '; echo "${unseen[*]}")."
echo "::error::$summary"

echo "Recovery: fix the cause, then re-run the failed run in place so it keeps its push event and id:"
for cmd in "${rerun_cmds[@]}"; do
  echo "  $cmd"
done
echo "  gh run rerun ${GITHUB_RUN_ID:-<this-run-id>}   # once those succeed, re-run this orchestrator"
echo "This orchestrator only sees runs the tag push triggered. A 'gh workflow run release-<lang>.yml'"
echo "dispatch is a dry-run rehearsal on a separate run that it will never detect. A re-run builds the"
echo "tagged commit, so a fix that changes any checked-in file (workflow, source, lockfile) needs the"
echo "next patch release instead. A language with no push-triggered run at all had its workflow missing"
echo "or disabled at the tag: that also means the next patch."
exit 1
