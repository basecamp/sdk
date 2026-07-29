# Seed SDK

Bootstrap a new SDK repository from seed templates.

## Prerequisites

- Smithy CLI installed
- Target language toolchains installed
- `basecamp/sdk` repo available locally

## Language Selection

Decide which languages to include based on the target audience:

| Platform target | Languages | Profile |
|-----------------|-----------|---------|
| Web + server + mobile | Go, TypeScript, Ruby, Swift, Kotlin | full-sdk |
| Web + server | Go, TypeScript, Ruby | full-sdk |
| Single platform (e.g., CLI tool) | One of the above | single-language |

The profile determines which rubric criteria apply (91 for full-sdk, 76 for single-language). Choose the minimal set that covers your deployment surface, then add languages later if needed.

## Template Variable Reference

All `.tmpl` files use Go template syntax. Replace these placeholders before renaming:

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{{.AppName}}` | Lowercase app identifier, used in code namespaces and paths | `hey`, `fizzy`, `bc4` |
| `{{.AppTitle}}` | Title-case app name for display, class prefixes, README | `HEY`, `Fizzy`, `Basecamp` |
| `{{.ModulePath}}` | Go module import path | `github.com/basecamp/hey-sdk` |
| `{{.NpmScope}}` | npm scope for TypeScript package | `@basecamp` |
| `{{.NpmPackage}}` | Full npm package name | `@basecamp/hey` |
| `{{.RubyGem}}` | Ruby gem name | `hey-sdk` |
| `{{.RubyModule}}` | Ruby module name | `Hey` |
| `{{.SwiftPackage}}` | Swift package name | `Hey` |
| `{{.KotlinPackage}}` | Kotlin Gradle module name | `hey-sdk` |
| `{{.GithubOrg}}` | GitHub organization | `basecamp` |
| `{{.GithubRepo}}` | GitHub repository name | `hey-sdk` |
| `{{.AccountId}}` | Default account ID used in path templates | `12345` |

Verify every placeholder is replaced: `grep -r '{{\..*}}' .` should return zero results after substitution.

## Generation Order

Files have dependencies. Follow this order to avoid broken intermediate states.

### Phase 1: Repository skeleton

These files have no inter-dependencies.

1. `.editorconfig` -- copy directly (no `.tmpl`)
2. `.gitignore.tmpl` -> `.gitignore`
3. `AGENTS.md.tmpl` -> `AGENTS.md`
4. `CONTRIBUTING.md.tmpl` -> `CONTRIBUTING.md`
5. `README.md.tmpl` -> `README.md`

**Checkpoint:** `git init && git add -A` succeeds. No template syntax in any file.

### Phase 2: Smithy spec

The spec drives everything downstream.

1. `spec/smithy-build.json` -- copy directly
2. `spec/traits.smithy.tmpl` -> `spec/model/traits.smithy`
3. Add your service model to `spec/model/` (operations, shapes)

**Checkpoint:** `cd spec && smithy validate` exits 0.

### Phase 3: Build pipeline

1. `Makefile.tmpl` -> `Makefile`
2. `scripts/` -- copy build helper scripts

**Checkpoint:** `make smithy-build` produces `openapi.json`.

### Phase 4: Per-language SDKs

Initialize each language in parallel -- they are independent of each other.

#### Go
1. Copy `seed/go/` into `go/`
2. `cd go && go mod init {{.ModulePath}}`
3. Scaffold client, error types, service base
4. `make go-generate-services`

**Checkpoint:** `make go-check` passes (format + vet + test).

#### TypeScript
1. Copy `seed/typescript/` into `typescript/`
2. `cd typescript && npm init --scope={{.NpmScope}}`
3. Scaffold client, error types, service base
4. `make ts-generate-services`

**Checkpoint:** `make ts-check` passes (tsc + lint + test).

#### Ruby
1. Copy `seed/ruby/` into `ruby/`
2. `cd ruby && bundle init`
3. Scaffold client, error types, service base
4. `make rb-generate-services`

**Checkpoint:** `make rb-check` passes (rubocop + test).

#### Swift
1. Copy `seed/swift/` into `swift/`
2. Initialize `Package.swift`
3. Scaffold client, error types, service base
4. `make swift-generate`

**Checkpoint:** `swift build && swift test` pass.

#### Kotlin
1. Copy `seed/kotlin/` into `kotlin/`
2. Initialize `build.gradle.kts`
3. Scaffold client, error types, service base
4. `make kt-generate-services`

**Checkpoint:** `./gradlew build` passes.

### Phase 5: Conformance & CI

1. Copy `conformance/` from sdk/common (tests + schema)
2. Initialize per-language conformance runners
3. Copy `.github/` workflow templates
4. `rubric-audit.json` -- create initial audit with profile and date

**Checkpoint:** `make conformance` runs (tests may fail -- that's the gap to close).

### Phase 6: Full verification

```bash
make check       # smithy-check + all lang checks + conformance + audit-check
```

All checks must pass before the first commit to main.

## Post-Bootstrap Verification

Run these per-language to confirm the SDK is functional end-to-end:

| Language | Smoke test |
|----------|------------|
| Go | `cd go && go build ./... && go test ./...` |
| TypeScript | `cd typescript && npm run build && npm test` |
| Ruby | `cd ruby && bundle exec rake` |
| Swift | `cd swift && swift build && swift test` |
| Kotlin | `cd kotlin && ./gradlew build` |

Then cross-language:

```bash
make conformance        # All conformance tests
make audit-check        # rubric-audit.json exists, fresh, must-pass criteria met
```

Finally, run the `rubric-audit` skill to establish a baseline score and identify gaps to close.

## Post-Bootstrap Setup

- Set up GitHub repository secrets for publishing
- Enable branch protection on main
- Configure Dependabot via `.github/dependabot.yml`
- Run `rubric-audit` skill to establish baseline score
- Use [close-gap.md](close-gap.md) to systematically address failing criteria
