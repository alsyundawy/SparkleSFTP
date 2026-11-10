# Changelog

All notable changes to **SparkleSFTP** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Planned

- Phase 01–02: Swift 6 / Xcode project scaffold, SPM pinned dependencies (`Citadel`, `swift-nio-ssh >= 0.14.1`, `SwiftTerm`, native `KeychainService`), DesignSystem, and SwiftData / JSON persistence models.
- Phase 03–04: Connection Manager, TOFU Host Key Verification, TLS validation (`SecTrustEvaluateWithError`), SFTP / SSH / FTP / FTPS protocol engines.
- Phase 05–06: Dual-pane Commander (`NSTableView`), drag-and-drop, and actor-isolated `TransferQueue` with durable `TransferJournal` recovery.
- Phase 07–08: Integrated `SwiftTerm` PTY terminal, directory sync preview, notarized Universal 2 macOS distribution, and Sparkle auto-updates.

---

## [0.1.0-bootstrap] - 2026-11-11

### Added

- **Repository Foundation & Rebranding**: Initialized `SparkleSFTP` repository (evolved from the initial `MacSFTP` architecture design).
- **Bilingual Project Documentation**: Created English [`README.md`](README.md) and Indonesian [`README-id.md`](README-id.md).
- **Open-Source Governance**: Added MIT [`LICENSE`](LICENSE), [`SECURITY.md`](SECURITY.md), [`CONTRIBUTING.md`](CONTRIBUTING.md), [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md), and [`CHANGELOG.md`](CHANGELOG.md).
- **Architecture & Review Specifications**:
  - [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) — full 8-phase, 125-task implementation blueprint rebranded for SparkleSFTP with critical fixes applied.
  - [`docs/CODE_REVIEW_14_PILLARS.md`](docs/CODE_REVIEW_14_PILLARS.md) — 55-finding evidence-based code review across 14 engineering & security pillars.
  - [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`docs/ROADMAP.md`](docs/ROADMAP.md).
  - Initial Architecture Decision Records (`docs/ADR/0001`–`0003`).
- **Quality, Linter & CI Automation**:
  - `.swiftlint.yml` with security & concurrency custom rules (`no_password_in_logs`, `no_accept_any_host_key`, `no_unchecked_sendable_without_comment`, `no_icloud_keychain_sync`).
  - `.swiftformat`, `.markdownlint.json`, `.yamllint.yml`, `.editorconfig`, `.gitignore`, and `.gitattributes`.
  - `.github/` issue templates, pull request template, Dependabot config, funding metadata, and staged CI workflow (`.github/workflows/ci.yml`).
