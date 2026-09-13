#!/usr/bin/env bats
# Pins scripts/check-generate-targets.sh against a rendered seed: the pristine seed
# must fail for every language (no generator ships in the seed), stubbed generator
# artifacts must pass, and a target that exits 0 having done nothing must fail.
# Only `make` is needed: the dry run never executes a generator, and the run-mode
# cases use a Swift sub-Makefile whose `generate` recipe is a shell one-liner.

setup() {
  tmp="$(mktemp -d)"
  "$BATS_TEST_DIRNAME/../render-seed.sh" "$tmp" > /dev/null
  cd "$tmp" || exit 1
}

teardown() {
  rm -rf "$tmp"
}

# The artifacts the rendered Makefile's recipes invoke, as the scaffold step leaves
# them; package-lock.json because ts-generate-services depends on the install stamp.
stub_generators() {
  mkdir -p go/cmd/generate-services typescript/scripts ruby/scripts kotlin/generator rust/generator swift
  touch go/cmd/generate-services/main.go typescript/scripts/generate-services.ts \
    typescript/package-lock.json ruby/scripts/generate-services.rb \
    kotlin/generator/build.gradle.kts rust/generator/Cargo.toml
  printf 'generate:\n\tswift run FizzyGenerator --output Sources/Fizzy/Generated\n' > swift/Makefile
}

set_profile() {
  perl -pi -e "s/^SDK_LANGUAGES := .*/SDK_LANGUAGES := $1/" Makefile
}

@test "pristine seed: every generate target in the profile is unwired" {
  run scripts/check-generate-targets.sh --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"go/cmd/generate-services missing"* ]]
  [[ "$output" == *"swift-generate-services does not expand"* ]]
  [[ "$output" == *"ERROR: generate targets not wired: go ts rb swift kt rs"* ]]
}

@test "make generate-services-check fails on the pristine seed" {
  run make generate-services-check
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: generate targets not wired: go ts rb swift kt rs"* ]]
}

@test "stubbed generators pass the dry run, Swift through its sub-Makefile" {
  stub_generators
  run scripts/check-generate-targets.sh --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"swift run FizzyGenerator"* ]]
  [[ "$output" == *"generate targets wired: go ts rb swift kt rs"* ]]
}

@test "a sub-Makefile generate target with no recipe is vacuous" {
  stub_generators
  printf 'generate:\n' > swift/Makefile
  run scripts/check-generate-targets.sh --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"swift-generate-services expands to no command"* ]]
  [[ "$output" == *"ERROR: generate targets not wired: swift"* ]]
}

@test "a root alias that lost its prerequisite is vacuous" {
  stub_generators
  perl -pi -e 's/^swift-generate-services: swift-generate$/swift-generate-services:/' Makefile
  run scripts/check-generate-targets.sh --dry-run swift
  [ "$status" -eq 1 ]
  [[ "$output" == *"swift-generate-services expands to no command"* ]]
}

@test "a narrowed profile is checked for its own languages only" {
  set_profile "go rs"
  run scripts/check-generate-targets.sh --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: generate targets not wired: go rs"* ]]
  [[ "$output" != *"ts-generate-services"* ]]
}

@test "run mode executes the target and reports its exit status" {
  stub_generators
  printf 'generate:\n\ttouch generated.marker\n' > swift/Makefile
  run scripts/check-generate-targets.sh swift
  [ "$status" -eq 0 ]
  [ -f swift/generated.marker ]
  [[ "$output" == *"make swift-generate-services exited 0"* ]]

  printf 'generate:\n\texit 3\n' > swift/Makefile
  run scripts/check-generate-targets.sh swift
  [ "$status" -eq 1 ]
  [[ "$output" == *"make swift-generate-services exited non-zero"* ]]
}

@test "an unknown prefix is rejected" {
  run scripts/check-generate-targets.sh --dry-run py
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown language prefix 'py'"* ]]
}
