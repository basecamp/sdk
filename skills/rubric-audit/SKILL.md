---
name: rubric-audit
description: Score an SDK repo against the rubric, producing a scorecard and rubric-audit.json artifact
---

# Rubric Audit

Evaluate the current SDK repository against the SDK Rubric and produce:
1. A scorecard summary (printed to stdout)
2. A `rubric-audit.json` artifact in the repo root

## Procedure

### 1. Determine Profile

Check for multiple language directories to determine the profile:
- If 2+ of `go/`, `typescript/`, `ruby/`, `kotlin/`, `swift/` exist: **full-sdk** (90 criteria)
- Otherwise: **single-language** (76 criteria)

### 2. Score Static Criteria

Run the equivalent of `rubric-check` locally:
- Check file existence (Smithy spec, OpenAPI, behavior model, provenance, etc.)
- Grep for required patterns (error codes, auth strategies, hooks, etc.)
- Validate Makefile targets exist
- Check CI workflow files exist

Record each criterion as pass/fail with notes.

### 3. Score Conformance Criteria

Run `make conformance` (or language-specific targets) and record results:
- Each conformance test file maps to specific rubric criteria
- `retry.json` -- 2B.1, 2B.2, 2B.3
- `idempotency.json` -- 2B.4, 2B.5
- `pagination.json` -- 2C.1, 2C.2
- `status-codes.json` -- 2A.3, 2A.4
- `paths.json` -- 1C.2
- `error-mapping.json` -- 2A.1, 2A.2, 2A.7
- `auth.json` -- 3A.1, 3A.3
- `security.json` -- 2C.5, 3C.1, 3C.6

### 4. Score Manual Criteria

Review each manual criterion by inspecting the codebase:
- 1A.6: Check that all API methods are generated (compare operation count vs service methods)
- 1B.2: Verify request/response types are generated, not hand-built
- 1B.4: Check optional fields across languages
- 1B.5: Check date handling
- 1C.1: Spot-check API paths against upstream docs
- 1C.3: Search for manual path construction (`fmt.Sprintf` with URL paths, template literals with paths)
- 2A.6: Check error body truncation
- 2D.5: Check resilience scope isolation
- 3A.4-3A.6: Review OAuth implementation
- 3C.2-3C.4: Review security measures
- 4B.5: Check test coverage for recent operations
- 4C.4: Check release idempotency

### 5. Produce Scorecard

Print the scorecard to stdout:

```
## Scorecard: <SDK Name> (<Profile>)

| Tier | Score | Max | Critical |
|------|-------|-----|----------|
| T1: API Fidelity | X/Y | Y | A/B |
| T2: Behavioral Contracts | X/Y | Y | A/B |
| T3: Developer Experience | X/Y | Y | A/B |
| T4: Infrastructure | X/Y | Y | A/B |
| **Total** | **X/Y** | **Y** | **A/B** |

Evidence: X/52 static, X/22 conformance, X/16 manual
Audit artifact: rubric-audit.json [present] [fresh]
```

### 6. Write rubric-audit.json

Write the artifact to the repo root:

```json
{
  "profile": "<full-sdk|single-language>",
  "date": "<YYYY-MM-DD>",
  "reviewer": "agent:rubric-audit",
  "criteria": {
    "<ID>": { "pass": true, "note": "<optional note>" }
  }
}
```

Include ALL manual criteria in the artifact. Static and conformance criteria
are verified by their respective actions and do not need to appear in the
audit artifact.
