# SDK Rubric

Standards for Basecamp SDK repositories. Every SDK — whether multi-language or single-language — is scored against this rubric.

## Profiles

| Profile | Criteria | Critical | Static | Conformance | Manual |
|---------|----------|----------|--------|-------------|--------|
| **Full SDK** | 91 | 10 | 53 | 22 | 16 |
| **Single-language** | 76 | 9 | 42 | 20 | 14 |

## Evidence Types

| Type | Verified by |
|------|-------------|
| `static` | `rubric-check` action — file existence, pattern grep, structural check |
| `conformance` | `conformance-run` action — behavioral test must pass |
| `manual` | `rubric-audit` skill or human review. Produces `rubric-audit.json` artifact |

## Must-Pass Criteria

Non-negotiable gates. `make release` checks `rubric-audit.json` for manual must-pass criteria.

| # | Criterion | Profile | Evidence |
|---|-----------|---------|----------|
| 1A.1 | Smithy validates | all | static |
| 1A.2 | OpenAPI derived from Smithy | all | static |
| 1A.6 | No hand-written API methods | multi | manual |
| 1C.3 | No manual path construction | all | manual |
| 2A.1 | Structured error type | all | static |
| 2A.3 | HTTP→error code mapping | all | conformance |
| 2B.4 | POST not retried | all | conformance |
| 2C.5 | Cross-origin pagination rejection | all | conformance |
| 3C.1 | HTTPS enforcement | all | conformance |
| 4A.1 | Smithy→OpenAPI freshness check | all | static |

Full SDK: 10 critical (4 static, 4 conformance, 2 manual). Single-language: 9 (1A.6 excluded; 4 static, 4 conformance, 1 manual).

## Manual Audit Artifact

`rubric-audit.json` is a required file in the repo root, produced by the `rubric-audit` skill or human review.

```json
{
  "profile": "full-sdk",
  "date": "2026-03-04",
  "reviewer": "agent:rubric-audit",
  "criteria": {
    "1A.6": { "pass": true, "note": "All 175 operations generated" },
    "1B.2": { "pass": true },
    "1C.3": { "pass": true, "note": "No fmt.Sprintf with paths found" }
  }
}
```

`make release` validates: (1) file exists, (2) all must-pass manual criteria present and passing, (3) date within 30 days.

## Conformance Skip & Waiver Policy

Conformance runners may skip tests where an SDK's architecture intentionally diverges from the tested behavior. Skips affect scoring mechanically:

**Critical criteria:** A skip on a critical criterion counts as a **fail**. Critical criteria cannot be waived. The test must either pass or the SDK must be fixed. `make release` blocks on any critical skip.

**Non-critical criteria:** A skip on a non-critical criterion counts as a **0** (not scored) unless a waiver is recorded. A waiver converts the skip to a **pass with note** for scoring purposes.

### Recording a waiver

Waivers are recorded in `rubric-audit.json` alongside manual criteria:

```json
{
  "2B.3": {
    "pass": true,
    "waiver": true,
    "note": "Ruby SDK only retries GET; PUT/DELETE retry omitted by design",
    "language": "ruby"
  }
}
```

Requirements for a valid waiver:
1. The criterion is **not** critical (critical criteria cannot be waived)
2. The `note` field explains the architectural reason for the divergence
3. The `language` field identifies which SDK(s) the waiver applies to
4. A human reviewer has approved the waiver (reviewer field in rubric-audit.json)

### Current known skips

| Test | Language | Criterion | Critical | Status |
|------|----------|-----------|----------|--------|
| Same-origin pagination (consumer-driven) | Go | 3C.6 | no | waiver-eligible |
| GET retries on 503 (chained retry architecture) | TS | 2B.1 | no | waiver-eligible |
| PUT/DELETE retry (only retries GET) | Ruby | 2B.3 | no | waiver-eligible |
| X-Total-Count metadata (paginate doesn't expose) | Ruby | 2C.2 | no | waiver-eligible |

No critical criteria are skipped in any language.

---

## Tier 1: API Fidelity

16 criteria (single-language: 13)

### 1A. Spec Conformance (7; single-language: 5)

| # | Criterion | Profile | Critical | Evidence |
|---|-----------|---------|----------|----------|
| 1A.1 | Smithy spec exists and validates clean | all | yes | static |
| 1A.2 | OpenAPI generated from Smithy, not hand-edited | all | yes | static |
| 1A.3 | Behavior model generated from Smithy annotations | all | | static |
| 1A.4 | All operations tagged for service grouping | all | | static |
| 1A.5 | API provenance tracks upstream sync point | all | | static |
| 1A.6 | No hand-written API methods; all ops generated | multi | yes | manual |
| 1A.7 | Service generator mappings cover all tagged operations | multi | | static |

### 1B. Type Fidelity (6; single-language: 5)

| # | Criterion | Profile | Critical | Evidence |
|---|-----------|---------|----------|----------|
| 1B.1 | Generated types match OpenAPI schema | all | | static |
| 1B.2 | Request/response body types generated, not hand-constructed | all | | manual |
| 1B.3 | Path parameters use correct types (int64 for IDs) | all | | static |
| 1B.4 | Optional fields nullable/optional in all languages | multi | | manual |
| 1B.5 | Date types use ISO 8601 where spec declares date | all | | manual |
| 1B.6 | Large integer ID preservation (no float64 truncation) | all | | conformance |

### 1C. Path Correctness (3)

| # | Criterion | Profile | Critical | Evidence |
|---|-----------|---------|----------|----------|
| 1C.1 | All API paths match upstream documentation | all | | manual |
| 1C.2 | Account ID scoping applied correctly | all | | conformance |
| 1C.3 | No manual path construction | all | yes | manual |

---

## Tier 2: Behavioral Contracts

27 criteria (single-language: 25)

### 2A. Error Handling (8)

| # | Criterion | Profile | Critical | Evidence |
|---|-----------|---------|----------|----------|
| 2A.1 | Structured error type: code, message, hint, httpStatus, retryable | all | yes | static |
| 2A.2 | Error codes: auth_required, forbidden, not_found, rate_limit, validation, network, api_error, usage | all | | static |
| 2A.3 | HTTP status→error code mapping: 401→auth, 403→forbidden, 404→not_found, 422→validation, 429→rate_limit, 5xx→api_error | all | yes | conformance |
| 2A.4 | Retryable flag set for 429, 503, network errors | all | | conformance |
| 2A.5 | Retry-After header parsed (seconds + HTTP-date) | all | | conformance |
| 2A.6 | Error body truncated to prevent unbounded memory | all | | manual |
| 2A.7 | Request ID extracted from X-Request-Id header | all | | conformance |
| 2A.8 | Exit codes for CLI integration (0-8 mapping) | all | | static |

### 2B. Retry & Idempotency (7; single-language: 6)

| # | Criterion | Profile | Critical | Evidence |
|---|-----------|---------|----------|----------|
| 2B.1 | GET/HEAD retried on 503 with exponential backoff | all | | conformance |
| 2B.2 | GET/HEAD retried on 429 with Retry-After delay | all | | conformance |
| 2B.3 | PUT/DELETE retried (naturally idempotent) | all | | conformance |
| 2B.4 | POST NOT retried unless explicitly idempotent | all | yes | conformance |
| 2B.5 | 4xx client errors (401, 403, 404, 422) NOT retried | all | | conformance |
| 2B.6 | Max retry count configurable | all | | static |
| 2B.7 | Conformance tests pass for retry behavior | multi | | conformance |

### 2C. Pagination (7; single-language: 6)

| # | Criterion | Profile | Critical | Evidence |
|---|-----------|---------|----------|----------|
| 2C.1 | Link header `rel="next"` parsing | all | | conformance |
| 2C.2 | X-Total-Count header parsing | all | | conformance |
| 2C.3 | Automatic page following with safety cap | all | | conformance |
| 2C.4 | maxItems option to cap results | all | | conformance |
| 2C.5 | Cross-origin Link header rejection (SSRF prevention) | all | yes | conformance |
| 2C.6 | Truncation metadata exposed to caller | all | | conformance |
| 2C.7 | Conformance tests pass for pagination | multi | | conformance |

### 2D. Resilience (5)

| # | Criterion | Profile | Critical | Evidence |
|---|-----------|---------|----------|----------|
| 2D.1 | Circuit breaker with configurable thresholds | all | | static |
| 2D.2 | Bulkhead (concurrency limiter) | all | | static |
| 2D.3 | Client-side rate limiter (token bucket) | all | | static |
| 2D.4 | Retry-After header honored by rate limiter | all | | conformance |
| 2D.5 | Resilience patterns scope-isolated (per service.operation) | all | | manual |

---

## Tier 3: Developer Experience

21 criteria

### 3A. Authentication (8)

| # | Criterion | Profile | Critical | Evidence |
|---|-----------|---------|----------|----------|
| 3A.1 | APP_TOKEN env var bypasses OAuth | all | | static |
| 3A.2 | AuthStrategy interface (pluggable auth) | all | | static |
| 3A.3 | BearerAuth default strategy | all | | static |
| 3A.4 | OAuth PKCE discovery (well-known endpoint) | all | | manual |
| 3A.5 | OAuth PKCE code exchange | all | | manual |
| 3A.6 | Token auto-refresh with expiry buffer | all | | manual |
| 3A.7 | Credential storage (keyring preferred, file fallback 0600) | all | | static |
| 3A.8 | APP_NO_KEYRING env to disable keyring | all | | static |

### 3B. Observability (7)

| # | Criterion | Profile | Critical | Evidence |
|---|-----------|---------|----------|----------|
| 3B.1 | Hooks interface (operation + request level) | all | | static |
| 3B.2 | NoopHooks with zero overhead | all | | static |
| 3B.3 | ChainHooks combinator | all | | static |
| 3B.4 | slog/console hooks implementation | all | | static |
| 3B.5 | GatingHooks extension for resilience | all | | static |
| 3B.6 | OpenTelemetry hooks (optional add-on) | all | | static |
| 3B.7 | Prometheus hooks (optional add-on) | all | | static |

### 3C. Security (6)

| # | Criterion | Profile | Critical | Evidence |
|---|-----------|---------|----------|----------|
| 3C.1 | HTTPS enforcement for non-localhost | all | yes | conformance |
| 3C.2 | Response body size limits | all | | manual |
| 3C.3 | Error message truncation | all | | manual |
| 3C.4 | Sensitive header redaction for logging | all | | manual |
| 3C.5 | Webhook signature verification (HMAC-SHA256) | all | | static |
| 3C.6 | Same-origin validation for pagination URLs | all | | conformance |

---

## Tier 4: Infrastructure & Distribution

27 criteria (single-language: 17)

### 4A. Generation Pipeline (7; single-language: 4)

| # | Criterion | Profile | Critical | Evidence |
|---|-----------|---------|----------|----------|
| 4A.1 | Smithy→OpenAPI generation with freshness check | all | yes | static |
| 4A.2 | Behavior model generation with freshness check | all | | static |
| 4A.3 | Per-language service generation from OpenAPI | multi | | static |
| 4A.4 | Service drift detection (generated vs spec) | multi | | static |
| 4A.5 | API version sync across all language constants | multi | | static |
| 4A.6 | URL routes generation (Go route table) | all | | static |
| 4A.7 | Provenance sync to embedded artifacts | all | | static |

### 4B. Testing (7; single-language: 4)

| # | Criterion | Profile | Critical | Evidence |
|---|-----------|---------|----------|----------|
| 4B.1 | Unit tests per language with mock HTTP servers | all | | static |
| 4B.2 | Conformance tests defined in JSON | multi | | static |
| 4B.3 | Conformance runner per language | multi | | static |
| 4B.4 | Conformance tests in CI | multi | | static |
| 4B.5 | Every new operation requires tests (per AGENTS.md) | all | | manual |
| 4B.6 | Type checking per language (tsc, go vet, rubocop) | all | | static |
| 4B.7 | Linting per language | all | | static |

### 4C. Release & Distribution (7; single-language: 3)

| # | Criterion | Profile | Critical | Evidence |
|---|-----------|---------|----------|----------|
| 4C.1 | `make bump VERSION=x.y.z` bumps all languages atomically | multi | | static |
| 4C.2 | Per-language release workflows triggered by tag | multi | | static |
| 4C.3 | GitHub Release with auto-generated notes | all | | static |
| 4C.4 | Release idempotent (re-runnable) | all | | manual |
| 4C.5 | Version constants match across all SDKs | multi | | static |
| 4C.6 | Breaking change detection on PRs | all | | static |
| 4C.7 | Go sub-tag auto-derived from global tag, never force-moved | multi | | static |

### 4D. Developer Experience (6)

| # | Criterion | Profile | Critical | Evidence |
|---|-----------|---------|----------|----------|
| 4D.1 | README with quick-start, per-language examples | all | | static |
| 4D.2 | CONTRIBUTING.md with development workflow | all | | static |
| 4D.3 | AGENTS.md with hard rules, anti-patterns, pipeline | all | | static |
| 4D.4 | Makefile conforming to SDK Makefile convention | all | | static |
| 4D.5 | CI pipeline (test + lint + security + conformance + smithy-verify) | all | | static |
| 4D.6 | Dependabot configuration | all | | static |

---

## Totals

| Tier | All | Multi-only | Single-lang |
|------|-----|------------|-------------|
| T1: API Fidelity | 16 | 3 | 13 |
| T2: Behavioral Contracts | 27 | 2 | 25 |
| T3: Developer Experience | 21 | 0 | 21 |
| T4: Infrastructure | 27 | 10 | 17 |
| **Total** | **91** | **15** | **76** |

---

## Scoring

### Full SDK

```markdown
## Scorecard: [SDK Name] (Full SDK)

| Tier | Score | Max | Critical |
|------|-------|-----|----------|
| T1: API Fidelity | /16 | 16 | /4 |
| T2: Behavioral Contracts | /27 | 27 | /4 |
| T3: Developer Experience | /21 | 21 | /1 |
| T4: Infrastructure | /27 | 27 | /1 |
| **Total** | **/91** | **91** | **10/10** |

Evidence: /53 static, /22 conformance, /16 manual
Waivers: N (0 critical, N non-critical)
Audit artifact: rubric-audit.json [present|missing] [fresh|stale]
```

### Single-language SDK

```markdown
## Scorecard: [SDK Name] (Single-language)

| Tier | Score | Max | Critical |
|------|-------|-----|----------|
| T1: API Fidelity | /13 | 13 | /3 |
| T2: Behavioral Contracts | /25 | 25 | /4 |
| T3: Developer Experience | /21 | 21 | /1 |
| T4: Infrastructure | /17 | 17 | /1 |
| **Total** | **/76** | **76** | **9/9** |

Evidence: /42 static, /20 conformance, /14 manual
Waivers: N (0 critical, N non-critical)
Audit artifact: rubric-audit.json [present|missing] [fresh|stale]
```
