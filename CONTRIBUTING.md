# Contributing to SparkleSFTP

Thank you for your interest in contributing to **SparkleSFTP**!

> [!NOTE]
> SparkleSFTP is currently in the **Repository & Architecture Foundation** phase. Before writing application code, please read [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md), [`docs/CODE_REVIEW_14_PILLARS.md`](docs/CODE_REVIEW_14_PILLARS.md), and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Development Workflow

1. **Fork & Clone** the repository:

   ```bash
   git clone https://github.com/alsyundawy/SparkleSFTP.git
   cd SparkleSFTP
   ```

2. **Branch from `main`** using short-lived, focused branches:
   - `feat/<short-description>` — new features or capabilities
   - `fix/<short-description>` — bug fixes
   - `docs/<short-description>` — documentation and ADR updates
   - `chore/<short-description>` — CI, tooling, and maintenance
   - `refactor/<short-description>` — non-behavioral structural improvements

3. **Keep Commits Atomic & Descriptive** using [Conventional Commits](https://www.conventionalcommits.org/):
   - `feat: add HostTrustState machine with TOFU mismatch guard`
   - `fix: re-verify TransferQueue state after await suspension`
   - `docs: add ADR-002 for Keychain accessibility attributes`

## Architectural & Coding Standards

All Swift code (once Phase 02 begins) must adhere to the following non-negotiable standards:

- **Swift 6 Strict Concurrency**: Full `Sendable` conformance and actor isolation; no data races.
- **`@unchecked Sendable` Guardrail**: Any `@unchecked Sendable` usage requires an inline `// JUSTIFICATION: ...` comment and passes SwiftLint review.
- **Strict Dependency Boundaries**:
  - `App -> ApplicationCore -> Domain`
  - `ProtocolAdapters -> Domain`
  - `Security -> Domain`
  - `Persistence -> Domain`
  - SwiftUI Views must never call Citadel, libcurl, or Keychain directly, and `Packages/` must never import from `Features/`.
- **Code Language**: All Swift identifiers, types, comments, and error keys must be written in clear English (`READ-001`). Documentation may include English and Indonesian translations.
- **14-Pillar Quality Gate**: Every non-trivial change is evaluated against the 14 pillars documented in [`docs/CODE_REVIEW_14_PILLARS.md`](docs/CODE_REVIEW_14_PILLARS.md).

## Local Checks Before Opening a Pull Request

Run all applicable checks locally before pushing:

```bash
# Markdown & YAML hygiene
markdownlint-cli2 "**/*.md" "#.build" "#DerivedData"
yamllint -c .yamllint.yml .

# GitHub Actions workflow validation
actionlint

# Once Swift sources are added:
swiftlint --strict
swiftformat --lint .
```

## Security Disclosures

Do **not** report security vulnerabilities via public issues or pull requests. Follow [`SECURITY.md`](SECURITY.md).
