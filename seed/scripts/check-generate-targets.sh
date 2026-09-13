#!/usr/bin/env bash
# Proves each <prefix>-generate-services target is wired to a real generator rather
# than exiting 0 vacuously. For every prefix it asserts that:
#   1. the generator artifact the root Makefile's recipe invokes exists;
#   2. the target's plan (`make -n`, which follows $(MAKE) -C into a sub-Makefile)
#      contains the invocation of that generator. Any command from a prerequisite
#      is not enough: `ts-install` still plans `npm ci` after the ts recipe is gone,
#      so a recipe that was tidied away, an alias that lost its prerequisite, or a
#      sub-Makefile `generate` with no recipe all fail here;
#   3. unless --dry-run, `make <prefix>-generate-services` runs and exits 0.
# Prefixes default to SDK_LANGUAGES in the Makefile. `make generate-services-check`
# runs the dry form as part of `make check`; the full form is the bootstrap
# checkpoint after each language is scaffolded.
#
# Usage: scripts/check-generate-targets.sh [--dry-run] [prefix...]
set -euo pipefail

dry_run=false
if [ "${1:-}" = "--dry-run" ]; then
  dry_run=true
  shift
fi

cd "$(dirname "$0")/.."
make="${MAKE:-make}"

if [ $# -gt 0 ]; then
  prefixes=("$@")
else
  read -ra prefixes <<< "$(sed -n 's/^SDK_LANGUAGES *:= *//p' Makefile)"
  if [ ${#prefixes[@]} -eq 0 ]; then
    echo "ERROR: no SDK_LANGUAGES line in Makefile; pass prefixes explicitly" >&2
    exit 2
  fi
fi

# The artifact each root recipe invokes. Swift's recipe is `$(MAKE) -C swift
# generate`, so its artifact is the sub-Makefile, and the invocation to find is
# the sub-Makefile's: the generator is a SwiftPM executable run with `swift run`.
artifact_for() {
  case "$1" in
    go)    echo "go/cmd/generate-services" ;;
    ts)    echo "typescript/scripts/generate-services.ts" ;;
    rb)    echo "ruby/scripts/generate-services.rb" ;;
    swift) echo "swift/Makefile" ;;
    kt)    echo "kotlin/generator/build.gradle.kts" ;;
    rs)    echo "rust/generator/Cargo.toml" ;;
    *)     return 1 ;;
  esac
}

# The command line, as `make -n` prints it, that runs the generator (grep -E).
invocation_for() {
  case "$1" in
    go)    echo 'go run \./cmd/generate-services' ;;
    ts)    echo 'scripts/generate-services\.ts' ;;
    rb)    echo 'ruby scripts/generate-services\.rb' ;;
    swift) echo '^swift run ' ;;
    kt)    echo 'gradlew :generator:run' ;;
    rs)    echo 'cargo run .*-generator' ;;
  esac
}

# The plan `make -n` prints, minus the lines that are not commands: echoes, shell
# comments (a commented-out recipe line is still printed), make's own recursion
# lines and its "Nothing to be done" notices. A generator named in any of those
# does not count.
commands_of() {
  grep -vE '^(#|echo |(.*/)?make(\[[0-9]+\])?[ :])' || true
}

failed=()
for prefix in "${prefixes[@]}"; do
  target="$prefix-generate-services"
  ok=true
  echo "==> $target"

  if ! artifact=$(artifact_for "$prefix"); then
    echo "  FAIL: unknown language prefix '$prefix' (expected one of go ts rb swift kt rs)"
    failed+=("$prefix")
    continue
  fi
  if [ -e "$artifact" ]; then
    echo "  ok: $artifact present"
  else
    echo "  FAIL: $artifact missing; the recipe has no generator to run (see CONTRIBUTING.md)"
    ok=false
  fi

  invocation=$(invocation_for "$prefix")
  if plan=$("$make" -n --no-print-directory "$target" 2>&1); then
    if run_line=$(printf '%s\n' "$plan" | commands_of | grep -E -m1 "$invocation"); then
      echo "  ok: invokes the generator: $run_line"
    else
      echo "  FAIL: $target never invokes the generator (no command matches /$invocation/); its plan is:"
      printf '%s\n' "$plan" | sed 's/^/        /'
      ok=false
    fi
  else
    echo "  FAIL: $target does not expand:"
    printf '%s\n' "$plan" | sed 's/^/        /'
    ok=false
  fi

  if [ "$ok" = true ] && [ "$dry_run" = false ]; then
    if "$make" "$target"; then
      echo "  ok: make $target exited 0"
    else
      echo "  FAIL: make $target exited non-zero"
      ok=false
    fi
  fi

  [ "$ok" = true ] || failed+=("$prefix")
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "ERROR: generate targets not wired: ${failed[*]}"
  exit 1
fi
echo "  generate targets wired: ${prefixes[*]}"
