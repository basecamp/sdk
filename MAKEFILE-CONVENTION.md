# SDK Makefile Convention

Required Makefile targets and release architecture for SDK repositories.

## Required Targets

| Target | Default? | Contract |
|--------|----------|----------|
| `check` | **Yes** | CI gate. Comprehensive: smithy-check + behavior-model-check + url-routes-check + provenance-check + sync-api-version-check + {lang}-check + conformance + audit-check. Not fast — use `check-mvp` or `{lang}-check` for inner-loop. |
| `check-mvp` | | Fast iteration target: smithy-check + behavior-model-check + url-routes-check + sync-api-version-check + go-check. Skips conformance. |
| `smithy-mapper` | | Build Smithy plugin to local Maven |
| `smithy-build` | | Build OpenAPI from Smithy. Prerequisites: `behavior-model smithy-mapper`. Post-step: `sync-api-version`. |
| `smithy-check` | | Verify openapi.json freshness |
| `behavior-model` | | Generate behavior-model.json from Smithy AST |
| `behavior-model-check` | | Verify behavior-model.json freshness (script `--check` flag) |
| `url-routes` | | Generate url-routes.json from OpenAPI |
| `url-routes-check` | | Verify url-routes.json freshness (script `--check` flag) |
| `provenance-sync` | | Copy provenance file into Go package for go:embed |
| `provenance-check` | | Verify Go embedded provenance matches spec |
| `sync-api-version` | | Sync API_VERSION constants from openapi.json to all SDKs |
| `sync-api-version-check` | | Verify API_VERSION constants match openapi.json |
| `{lang}-test` | | Tests for one language |
| `{lang}-check` | | All checks for one language. Must include lint + test (+ typecheck where applicable). |
| `{lang}-check-drift` | | Verify generated services match spec for one language |
| `{lang}-generate-services` | | Generate service classes from OpenAPI |
| `conformance` | | All cross-language conformance tests |
| `audit-check` | | Validate rubric-audit.json: exists, must-pass manual criteria pass, date within 30 days |
| `bump VERSION=x.y.z` | | Atomic version bump across all languages |
| `release VERSION=x.y.z` | | Sole release authority (see below) |
| `generate-services` | | Aggregate: regenerate services for all languages |

## Naming Conventions

- **Language prefixes**: `go-*`, `ts-*`, `rb-*`, `swift-*`, `kt-*`
- **Sub-make delegation**: Use `$(MAKE) -C go` / `$(MAKE) -C swift` when a sub-Makefile exists. Keep `{lang}-generate-services` and `{lang}-check-drift` in the root Makefile (they need root-level context).
- **Section dividers**: `#---` comment blocks between sections
- **TypeScript stamp file**: Use `typescript/node_modules/.install-stamp` to skip redundant `npm ci`:
  ```makefile
  TS_NODE_STAMP := typescript/node_modules/.install-stamp
  $(TS_NODE_STAMP): typescript/package-lock.json typescript/package.json
  	cd typescript && npm ci
  	@touch $(TS_NODE_STAMP)
  ts-install: $(TS_NODE_STAMP)
  ```
  Declare dependency-only lines before recipes: `ts-test: ts-install` then `ts-test:` with recipe.
- **Script `--check` flag**: Freshness-check scripts own their diff logic. The Makefile calls `./scripts/generate-foo --check` which exits 1 if stale. No inline temp-file wrangling in Make.
- **Help**: Manual `@echo` blocks (not grep-parsed `## ` comments)
- **Version guard**: `ifndef VERSION` / `$(error ...)` (not `test -n`)

## `{lang}-check` Content Requirements

| Language | Must include |
|----------|-------------|
| Go | fmt-check + vet + lint + test (via sub-Makefile `check` target) |
| TypeScript | typecheck + test |
| Ruby | test + rubocop |
| Swift | build + test |
| Kotlin | test (via `./gradlew :{app}-sdk:check`) |

## Release Architecture

One path, no ambiguity:

1. **Human runs:** `make release VERSION=x.y.z`
2. **`make release` does:** Verify preconditions (clean tree, main branch, version constants match across all languages including Kotlin Gradle, `make check` passes including `audit-check`). Create annotated tag. Push tag only to origin.
3. **CI triggers:** Tag push triggers per-language release workflows (`release-go.yml`, `release-typescript.yml`, etc.) which publish to registries independently.
4. **CI finishes:** `release-github.yml` uses `release-orchestrate` action to poll per-language workflows. When all succeed, creates the GitHub Release.

### Failure Recovery (Partial Publish)

Registry artifacts (npm packages, gems, Go modules) are immutable once published. Tag deletion is not a recovery strategy.

- **All workflows failed before any publish:** Safe to delete tag, fix, re-tag with same version.
- **Some registries published, others failed:** Do NOT delete tag. Fix the failing workflow. Re-run it manually (`gh workflow run release-<lang>.yml`). The orchestrator detects completed workflows and only waits for remaining ones.
- **Fundamentally broken release (wrong code shipped):** Bump to next patch version (`x.y.(z+1)`). Release again. The partially published version is orphaned but harmless — no GitHub Release points to it, CHANGELOG notes the skip.

`make release` is the sole entry point. CI workflows are triggered consequences, not peers.

### Go Sub-Tag Policy

If the SDK has a Go submodule at `go/`, `release-go.yml` MUST auto-derive a `go/v{VERSION}` tag from the global `v{VERSION}` tag's SHA. Requirements:

- Extract version from the global tag (`GITHUB_REF`)
- Create `go/v{VERSION}` pointing to the same `GITHUB_SHA`
- If `go/v{VERSION}` already exists and points to a **different** SHA, the workflow MUST fail (never force-move an existing tag)
- The `git tag` command MUST NOT contain `--force` or `-f`
- Fix requires a new patch release (`x.y.(z+1)`)

## audit-check Target

The `audit-check` target validates `rubric-audit.json`:

```makefile
audit-check:
	@echo "==> Checking rubric audit..."
	@test -f rubric-audit.json || \
		{ echo "ERROR: rubric-audit.json not found. Run rubric-audit skill."; exit 1; }
	@for c in 1A.6 1B.2 1C.3; do \
		pass=$$(jq -r --arg c "$$c" '.criteria[$$c].pass // empty' rubric-audit.json); \
		if [ "$$pass" != "true" ]; then \
			echo "ERROR: Must-pass criterion $$c is not passing in rubric-audit.json" && exit 1; \
		fi; \
	done
	@audit_date=$$(jq -r '.date' rubric-audit.json); \
		days_old=$$(( ( $$(date +%s) - $$(date -j -f '%Y-%m-%d' "$$audit_date" +%s 2>/dev/null || date -d "$$audit_date" +%s) ) / 86400 )); \
		if [ "$$days_old" -gt 30 ]; then \
			echo "ERROR: rubric-audit.json is $$days_old days old (max 30)" && exit 1; \
		fi
	@echo "  rubric-audit.json is fresh and must-pass criteria verified"
```
