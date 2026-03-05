# SDK Makefile Convention

Required Makefile targets and release architecture for SDK repositories.

## Required Targets

| Target | Default? | Contract |
|--------|----------|----------|
| `check` | **Yes** | CI gate. Comprehensive: smithy-check + behavior-model-check + provenance-check + sync-api-version-check + {lang}-check + conformance + audit-check. Not fast — use `{lang}-check` for inner-loop. |
| `smithy-build` | | Build OpenAPI from Smithy |
| `smithy-check` | | Verify openapi.json freshness |
| `{lang}-test` | | Tests for one language |
| `{lang}-check` | | All checks for one language (format + vet/typecheck + lint + test) |
| `{lang}-generate-services` | | Generate service classes from OpenAPI |
| `conformance` | | All cross-language conformance tests |
| `audit-check` | | Validate rubric-audit.json: exists, must-pass manual criteria pass, date within 30 days |
| `bump VERSION=x.y.z` | | Atomic version bump across all languages |
| `release VERSION=x.y.z` | | Sole release authority (see below) |

## Release Architecture

One path, no ambiguity:

1. **Human runs:** `make release VERSION=x.y.z`
2. **`make release` does:** Verify preconditions (clean tree, main branch, version constants match, `make check` passes including `audit-check`). Create annotated tag. Push tag to origin.
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
	@AUDIT_DATE=$$(jq -r .date rubric-audit.json); \
	AUDIT_EPOCH=$$(python3 -c "import datetime,sys; print(int(datetime.datetime.strptime(sys.argv[1],'%Y-%m-%d').timestamp()))" "$$AUDIT_DATE"); \
	NOW_EPOCH=$$(date +%s); \
	DAYS=$$(( (NOW_EPOCH - AUDIT_EPOCH) / 86400 )); \
	[ "$$DAYS" -le 30 ] || \
		{ echo "ERROR: rubric-audit.json is $$DAYS days old (max 30). Re-run audit."; exit 1; }
	@jq -e '.criteria["1C.3"].pass and .criteria["1A.6"].pass' rubric-audit.json > /dev/null 2>&1 || \
		{ echo "ERROR: Must-pass manual criteria failing. See rubric-audit.json."; exit 1; }
	@echo "rubric-audit.json is valid and fresh"
```
