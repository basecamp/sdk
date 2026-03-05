# Close Gap

Close one specific rubric criterion gap. Use this prompt when the rubric audit
identifies a failing criterion that needs to be addressed.

## Usage

Provide the criterion ID (e.g., `2A.1`, `3B.5`, `4C.3`) and this prompt
guides you through closing the gap.

## Workflow

1. **Identify the criterion** from RUBRIC.md:
   - Read the criterion description, profile, and evidence type
   - Determine what "passing" looks like

2. **Check evidence type** to determine verification method:

   | Evidence | Verification |
   |----------|-------------|
   | `static` | File existence, pattern grep, or structural check via `rubric-check` action |
   | `conformance` | Behavioral test must pass via `conformance-run` action |
   | `manual` | Human or agent review, updates `rubric-audit.json` |

3. **Implement the fix** (see criterion-specific guidance below)

4. **Verify locally** (see verification commands below)

5. **Update rubric-audit.json** if the criterion is manual:
   ```json
   {
     "criteria": {
       "<ID>": { "pass": true, "note": "<what was done>" }
     }
   }
   ```

6. **Commit** with message: `Close rubric gap <ID>: <criterion name>`

## Criterion-Specific Guidance by Evidence Type

### Static criteria

Static checks verify file existence, pattern presence, or structural properties. The `rubric-check` action runs these automatically.

**What to fix:** Add the missing file, code pattern, or structural element.

| Category | What's checked | Common fix |
|----------|---------------|------------|
| 1A (Spec) | Smithy files exist, OpenAPI generated, provenance | Add missing spec files, run `make smithy-build` |
| 1B (Types) | Generated type files match schema | Re-run `make {lang}-generate-services` |
| 2A.1-2 (Errors) | Structured error type with required fields and codes | Add/fix error type definition in each language |
| 2A.8 (Exit codes) | Exit code mapping exists | Add exit code constants |
| 2B.6 (Max retry) | Configurable retry count | Add config field for max retries |
| 2D.1-3 (Resilience) | Circuit breaker, bulkhead, rate limiter files exist | Implement resilience patterns |
| 3A (Auth) | Auth strategy files, env var handling | Implement auth module |
| 3B (Observability) | Hooks interface files | Implement hooks module |
| 3C.5 (Webhooks) | Webhook signature verification | Add HMAC-SHA256 verifier |
| 4A (Pipeline) | Makefile targets, generation scripts | Add missing targets |
| 4D (DX) | README, CONTRIBUTING, AGENTS, CI files | Create missing files |

**Verification:**
```bash
make check                    # Full suite
make smithy-check             # Spec freshness only
make {lang}-check             # Language-specific checks
```

### Conformance criteria

Conformance tests are JSON-defined behavioral tests run by per-language runners. The test file, criterion mapping, and assertion types are all defined in `conformance/`.

**What to fix:** The SDK's runtime behavior -- how it handles HTTP responses, retries, pagination, errors.

| Test file | Criteria covered | What the SDK must do |
|-----------|-----------------|---------------------|
| `auth.json` | 3A.1, 3A.3 | Inject bearer token in Authorization header |
| `error-mapping.json` | 2A.1, 2A.2, 2A.7 | Map HTTP status to error codes, extract request ID |
| `status-codes.json` | 2A.3, 2A.4 | Map status to error code, set retryable flag |
| `retry.json` | 2B.1, 2B.2, 2B.3 | Retry GET/PUT/DELETE on 503/429, respect backoff |
| `idempotency.json` | 2B.4, 2B.5 | Never retry POST, never retry 4xx |
| `pagination.json` | 2C.1-2C.4, 2C.6 | Parse Link/X-Total-Count, auto-follow, cap, truncation metadata |
| `security.json` | 2C.5, 3C.1, 3C.6 | HTTPS enforcement, cross-origin rejection, same-origin validation |
| `paths.json` | 1C.2 | Correct account-scoped paths |

**Debugging a failing conformance test:**
1. Read the test JSON to understand the mock response sequence and assertions
2. Run the single test: `cd conformance/runner/{lang} && <run single test>`
3. Check that `dist/` is fresh for compiled languages (TypeScript especially)
4. Trace the SDK code path for the specific HTTP scenario

**Verification:**
```bash
make conformance              # All languages, all tests
make {lang}-conformance       # Single language
```

### Manual criteria

Manual criteria require human or agent judgment. They cannot be verified automatically.

**What to fix:** The codebase property being evaluated -- then record the assessment.

| Criterion | What to verify | How to verify |
|-----------|---------------|---------------|
| 1A.6 | All ops generated | Compare operation count in spec vs generated service methods |
| 1B.2 | Types generated | Check that request/response types come from generator, not hand-written |
| 1B.4 | Optional fields nullable | Inspect generated types for optional/nullable markers per language |
| 1B.5 | Date types ISO 8601 | Search for date fields, verify format handling |
| 1C.1 | Paths match upstream | Spot-check generated paths against API documentation |
| 1C.3 | No manual paths | `grep -r 'fmt.Sprintf.*/' go/`, `grep -r 'template literal.*/' typescript/` |
| 2A.6 | Error body truncation | Check error construction for size limits |
| 2D.5 | Resilience scoped | Verify circuit breaker/bulkhead are per-service.operation |
| 3A.4-6 | OAuth PKCE flow | Review discovery, exchange, and refresh implementation |
| 3C.2-4 | Security measures | Check response size limits, error truncation, header redaction |
| 4B.5 | Test coverage | Verify recent operations have tests |
| 4C.4 | Release idempotent | Verify `make release` can re-run safely |

**Verification:**
```bash
# Re-run the rubric-audit skill to re-assess all manual criteria
# Or update rubric-audit.json directly:
```
```json
{ "<ID>": { "pass": true, "note": "<explanation of what was verified>" } }
```

## Cross-Language Coordination

Some fixes must land in multiple languages simultaneously to maintain consistency.

**When to coordinate across languages:**
- Error type changes (2A.*) -- all languages must expose the same fields and codes
- Retry policy changes (2B.*) -- behavior must match across SDKs
- Pagination contract changes (2C.*) -- same Link header parsing logic everywhere
- Security properties (3C.*) -- HTTPS enforcement, origin checks must be uniform

**Approach:**
1. Fix one language first as the reference implementation
2. Port the fix to remaining languages
3. Run `make conformance` to verify all languages pass the same tests
4. Commit all language changes together

**When a single-language fix is acceptable:**
- Language-specific static checks (type annotations, linting rules)
- Runner-specific conformance plumbing
- Waivered criteria (already recorded in rubric-audit.json for that language)

## Common Patterns by Rubric Category

### Tier 1 (API Fidelity) gaps
The fix is almost always in the generation pipeline, not hand-written code. Re-run generators after fixing the spec or generator template.

### Tier 2 (Behavioral Contracts) gaps
These require changes to the SDK's HTTP client layer -- retry logic, error mapping, pagination handling. The conformance tests define the exact behavior expected. Read the test JSON first, then implement to satisfy it.

### Tier 3 (Developer Experience) gaps
Auth, hooks, and security patterns are per-language implementations. Follow the existing pattern in languages that already pass, then port to the failing language.

### Tier 4 (Infrastructure) gaps
Makefile targets, CI workflows, and release plumbing. These are typically file-existence checks -- create the missing file following the convention in MAKEFILE-CONVENTION.md.

## Troubleshooting

**Conformance test passes locally but fails in CI:**
- Check that CI rebuilds from source (`make {lang}-check` includes build step)
- Verify CI has the same test runner version as local
- Check for timing-sensitive assertions (retry delays) that may flake in CI

**Static check fails but the file exists:**
- The check may grep for a specific pattern, not just file existence
- Read the `rubric-check` action to see the exact grep pattern expected
- Ensure the pattern matches (e.g., exact field names in error type struct)

**Conformance runner can't find SDK:**
- TypeScript: `dist/` stale -- rebuild with `npm run build`
- Go: module path mismatch -- check `go.mod` replace directives in runner
- Ruby: Gemfile path wrong -- check `path:` in runner's Gemfile

**Manual criterion unclear:**
- Re-read RUBRIC.md for the criterion description
- Check SKILL.md in `skills/rubric-audit/` for detailed assessment guidance
- When genuinely ambiguous, record a note explaining your interpretation

## Tips

- Address critical criteria first (marked in RUBRIC.md)
- One criterion per commit for clean history
- If a criterion requires changes across multiple languages, make all changes in the same commit
- Run `make check` after every gap closure to catch regressions
- Use `rubric-audit` skill periodically to track overall score progression
