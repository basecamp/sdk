# 37signals SDKs

Official API clients for Basecamp, HEY, and Fizzy. Generated from [Smithy](https://smithy.io/) specifications with consistent authentication, retry, pagination, and error handling. Basecamp ships today in five languages; HEY and Fizzy SDKs are planned. These libraries power our [CLIs](https://github.com/basecamp/cli) and agent skills.

| SDK | What it does | Repo | Status |
|-----|-------------|------|--------|
| Basecamp | Projects, to-dos, messages, schedules, campfires, card tables, and more | [basecamp/basecamp-sdk](https://github.com/basecamp/basecamp-sdk) | Available |
| HEY | Email triage, contacts, screening, and search | [basecamp/hey-sdk](https://github.com/basecamp/hey-sdk) | Available |
| Fizzy | Boards, cards, columns, and workflows | [basecamp/fizzy-sdk](https://github.com/basecamp/fizzy-sdk) | Available |

## Languages

| Language | Package format | Basecamp | HEY | Fizzy |
|----------|---------------|:--------:|:---:|:-----:|
| Go | Go module | ✓ | ✓ | ✓ |
| TypeScript | npm | ✓ | | ✓ |
| Ruby | gem | ✓ | | ✓ |
| Swift | SPM | ✓ | | ✓ |
| Kotlin | GitHub Packages | ✓ | | ✓ |

## Related tools

**CLIs** — [basecamp/cli](https://github.com/basecamp/cli) ships `basecamp`, `hey`, and `fizzy` command-line tools built on these SDKs. Structured JSON output, shell completion, and full API coverage.

**Agent skills** — Each CLI embeds Claude Code skills for AI-agent integration. The SDKs themselves are the runtime layer those skills call into.

---

This repo is the shared infrastructure that all SDK repositories consume via subtree. Everything language-agnostic or cross-language lives here; individual SDK repos pull it in as `common/`.

## Directory structure

```
actions/
  conformance-run/      Run cross-language conformance tests in CI
  rubric-check/         Static rubric criteria verification
  release-orchestrate/  Poll per-language release workflows, create GitHub Release
  smithy-verify/        Validate Smithy spec and OpenAPI freshness
  service-drift/        Detect drift between generated services and spec

conformance/
  schema.json           JSON schema for conformance test definitions
  tests/                Test case files (auth, retry, pagination, error-mapping, etc.)
  runner/               Per-language runners (go, typescript, ruby, swift, kotlin)

prompts/
  seed-sdk.md           Bootstrap a new SDK repository from templates
  close-gap.md          Close one specific rubric criterion gap

seed/                   Template files for new SDK repos (.tmpl extension)
  spec/                 Smithy model templates
  go/ ts/ ruby/         Per-language scaffolding
  swift/ kotlin/
  scripts/ .github/
  Makefile.tmpl, AGENTS.md.tmpl, README.md.tmpl, etc.

skills/
  rubric-audit/         Score an SDK repo against the rubric, produce scorecard + artifact

smithy-bare-arrays/     Smithy plugin for bare array (non-wrapped) responses
```

## Consuming sdk/common

Add as a git subtree in an SDK repo:

```bash
git subtree add --prefix common https://github.com/basecamp/sdk.git main --squash
```

Update later:

```bash
git subtree pull --prefix common https://github.com/basecamp/sdk.git main --squash
```

Actions are referenced from CI workflows. Conformance tests and runners live under `common/conformance/` in the consuming repo.

Conformance runners reference the SDK via relative paths (e.g., `../../../typescript`, `../../../kotlin`) and are designed to build within a consuming repo, not standalone.

## Bootstrapping a new SDK repo

Use the [seed-sdk prompt](prompts/seed-sdk.md) to walk through the full bootstrap process:

1. Copy `seed/*` into the new repo
2. Replace template placeholders (`{{.AppName}}`, `{{.AppTitle}}`, etc.)
3. Rename `.tmpl` files to their final names
4. Initialize Smithy spec, language toolchains, and conformance runners
5. Run `make check` to verify clean state

## Quality criteria

All SDK repos are scored against [RUBRIC.md](RUBRIC.md) (91 criteria for full SDK, 76 for single-language). The rubric covers:

- **Tier 1** -- API fidelity (spec conformance, type fidelity, path correctness)
- **Tier 2** -- Behavioral contracts (errors, retry, pagination, resilience)
- **Tier 3** -- Developer experience (auth, observability, security)
- **Tier 4** -- Infrastructure (generation pipeline, testing, release, DX)

See also [MAKEFILE-CONVENTION.md](MAKEFILE-CONVENTION.md) for required Makefile targets and release architecture.
