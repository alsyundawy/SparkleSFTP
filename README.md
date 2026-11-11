<p align="center">
  <img src="App/Resources/AppIcon.png" width="144" height="144" alt="SparkleSFTP Logo">
</p>

<h1 align="center">SparkleSFTP</h1>

<p align="center">
  <b>Native macOS Dual-Pane SFTP, FTP/FTPS, SCP &amp; SSH Commander — Built with Swift 6 &amp; SwiftUI</b><br>
  <i>High-performance file management, Keychain + Touch ID security, integrated SwiftTerm PTY terminal, and crash-resilient atomic transfers without Electron bloat</i>
</p>

<p align="center">
  <b>English</b> &nbsp;|&nbsp; <a href="README-id.md"><b>Bahasa Indonesia</b></a>
</p>

<p align="center">
  <a href="docs/ROADMAP.md"><img src="https://img.shields.io/badge/Stage-Full_MVP_Implemented-16a34a?style=for-the-badge&logo=github&logoColor=white" alt="Stage: Full MVP Implemented"></a>
  <a href="https://apple.com/macos"><img src="https://img.shields.io/badge/Platform-macOS_13%2B_(Universal_2)-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Platform: macOS 13+ Universal 2"></a>
  <a href="https://developer.apple.com/swift/"><img src="https://img.shields.io/badge/Language-Swift_6-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Language: Swift 6"></a>
  <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/UI-SwiftUI_%2B_AppKit-007AFF?style=for-the-badge&logo=apple&logoColor=white" alt="UI: SwiftUI and AppKit"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-2ea44f?style=for-the-badge" alt="License: MIT"></a>
  <a href="https://github.com/alsyundawy/SparkleSFTP/actions"><img src="https://img.shields.io/badge/CI%2FCD-GitHub_Actions-2088FF?style=for-the-badge&logo=githubactions&logoColor=white" alt="CI/CD GitHub Actions"></a>
</p>

> Lead Developer & Maintainer:<br>
> **[`HARRY DERTIN SUTISNA ALSYUNDAWY (@alsyundawy)`](https://github.com/alsyundawy)** — [`ALSYUNDAWY IT SOLUTION`](https://alsyundawy.com)<br>
>
> 📋 **[`Implementation Plan`](docs/IMPLEMENTATION_PLAN.md)** &nbsp;|&nbsp;
> 🔍 **[`14-Pillar Code Review`](docs/CODE_REVIEW_14_PILLARS.md)** &nbsp;|&nbsp;
> 📐 **[`Architecture`](docs/ARCHITECTURE.md)** &nbsp;|&nbsp;
> 🗺️ **[`Roadmap & Release Gate`](docs/ROADMAP.md)** &nbsp;|&nbsp;
> 🔐 **[`Security Policy`](SECURITY.md)** &nbsp;|&nbsp;
> 📜 **[`Changelog`](CHANGELOG.md)** &nbsp;|&nbsp;
> 🤝 **[`Contributing`](CONTRIBUTING.md)** &nbsp;|&nbsp;
> 💖 **[`Support via PayPal`](https://www.paypal.me/alsyundawy)**

---

> [!IMPORTANT]
>
> ### Repository Status: Full MVP Implemented (Swift 6 + macOS 13+)
>
> All core SwiftPM modules (`Package.swift`, `App/`, `Packages/*`, `Features/`, `Tests/*`, `Tools/*`) are implemented and verified with `swift build` and `swift test`. See [`docs/TECHNICAL_SPECIFICATION.md`](docs/TECHNICAL_SPECIFICATION.md), [`DOCNOTE.md`](DOCNOTE.md), [`TODO.md`](TODO.md), and [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md).
>
> **Project Lineage:** Originally drafted under the working title `MacSFTP` and standardized as **SparkleSFTP** with all 55 findings from [`docs/CODE_REVIEW_14_PILLARS.md`](docs/CODE_REVIEW_14_PILLARS.md) integrated prior to coding.

---

## Navigation

- [Overview & Vision](#overview--vision)
- [Technology Stack](#technology-stack)
- [System Architecture](#system-architecture)
- [Security & Hardening Baseline](#security--hardening-baseline)
- [Repository Layout](#repository-layout)
- [Roadmap Summary](#roadmap-summary)
- [Documentation & ADRs](#documentation--adrs)
- [Contributing & Quality Gates](#contributing--quality-gates)
- [License](#license)

---

## Overview & Vision

**SparkleSFTP** is a native macOS file transfer and SSH Commander application designed for engineers, sysadmins, and DevOps workflows who want WinSCP-style dual-pane productivity with first-class macOS ergonomics:

- **Dual-Pane Commander Experience**: Local ↔ Remote and Remote ↔ Remote panes backed by AppKit `NSTableView` for smooth 100K+ file browsing, keyboard shortcuts (`Tab`, `F5`–`F8`), Quick Look (`QLPreviewPanel`), Finder drag-and-drop, and built-in multi-tab editing.
- **Minimalist Notepad2 Internal File Editor (`⌘E`)**: Embedded multi-tab AppKit `NSTextView` editor (`Features/Editor/`) with `NSRulerView` line numbers, active palette syntax highlighting, whitespace glyph overlay (`¶`), word wrap, zoom `+/-/%`, read-only lock, regex Find & Replace, Go-to-Line, text transforms (UPPER/lower/Title/Trim/Sort), `UTF-8`/`UTF-8 BOM`/`UTF-16 LE`/`ASCII` + `LF`/`CRLF` converters, and remote save + auto-upload.
- **Multi-Theme Engine (`SparkNotePad` Palettes) & Full Workspace Sync**: `28` curated themes across `15` developer families (`NotepadNext`, `Catppuccin`, `Dracula`, `Tokyo Night`, `Nord`, `One Dark`, `Gruvbox`, `Solarized`, `GitHub`, `Monokai`, `Rosé Pine`, `Night Owl`, `SynthWave '84`, `Cobalt2`, `Tomorrow`) with `Auto / Light / Dark` mode, WCAG 2.1 contrast validation, custom JSON theme import/export, and live propagation (`sparkleWorkspaceSurface`, `TerminalThemeColors`, AppKit tables, `NSApp.windows`) across Commander, Terminal, Transfers, Snippets, Sync, Preferences, and About dialogs.
- **Connection Manager, AppKit Cursor Focus & Keychain Password Memory**: Native AppKit `ConnectionListTableView` (`NSTableView` with unique row keys) + `InteractiveFileTableView` click/arrow-key focus navigation, double-click connect, atomic Edit Connection (`ConnectionEditorMode`), **Clone Connection**, `⌘A` Select All & batch Delete Selected, Keychain **Remember Password** / clear secret controls (`ConnectionEditorView`, `CredentialPromptSheet`, `FTPService`), and instant non-deadlocking quit via `applicationShouldTerminate`.
- **SparkNotePad-Style About Dialog & 1:1 Branded AppIcon**: 6-tab About window (`AboutView`, `AboutView+Tabs`, `AboutWindowController`) featuring system/theme/session copyable diagnostics, GitHub/maintainer/PayPal info, shortcuts, license, and a 1:1 squircle `AppIcon.png`/`.icns` styled in SparkNotePad's blue, white, and pastel yellow pencil palette.
- **Responsive Runtime Architecture**: Dedicated `TransferMonitor` isolating 10Hz transfer updates from whole-window SwiftUI re-renders, cached `AppStrings` & `SparkleThemePalette`, 2-second throttled SQLite WAL checkpoints during active transfers, and single-`lstat` POSIX local directory enumeration.
- **Maintainable JSON i18n & Importers**: JSON locale catalogs (`en.json` & `id.json`, `285` synchronized keys) + runtime override directory (`~/Library/Application Support/SparkleSFTP/Locales/`), live coverage inspector, and preview-based FileZilla XML (`<Folder>`, `base64`, `crypt` protection) & WinSCP INI (UTF-16LE/BE BOM, `FSProtocol`, proxies, nested folders) importer (`ImportConnectionsSheet`).
- **Auto-Update Controls & Bidirectional Sync**: Configurable `AutoUpdateSettings` (auto-check/download, `Hourly`/`Daily`/`Weekly`/`Manual` frequency, `Stable`/`Beta` channel, HTTPS feed validation, community GitHub Releases API fallback check) and full `SyncDirection` (`Local -> Remote`, `Remote -> Local`, `Bidirectional Newest Wins`).
- **Complete Protocol Coverage**: SFTP, SSH Terminal (PTY), Explicit/Implicit FTPS, Plain FTP (with explicit security warnings), and isolated SCP fallback (`SCPCompatibilityAdapter`).
- **Actor-Isolated Transfer Engine**: Bounded global and per-host concurrency, checkpointed pause/resume with remote metadata revalidation, durable `TransferJournal` crash recovery, and atomic temporary-write + SHA-256 verification.
- **Security from Day One**: Device-locked Apple Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), optional Touch ID unlock, strict TOFU host key state machine, `SecTrust` TLS validation, and zero-secret `OSLog` privacy redaction.

---

## Technology Stack

| Layer | Technology | Purpose & Security Baseline |
| :--- | :--- | :--- |
| **Language** | Swift 6 | Strict concurrency, actor isolation, `Sendable` safety |
| **UI Framework** | SwiftUI + AppKit (`NSTableView`) | Native macOS HIG with cell-reused high-volume tables (`ObservableObject` for macOS 13+) |
| **SSH & SFTP** | `apple/swift-nio-ssh` (`0.15.1` >= `0.14.1`) + SFTP v3 Codec | Async/await SFTP v3, PTY, port forwarding; mitigates CVE-2026-43798 & supports macOS 13+ |
| **FTP & FTPS** | System `libcurl` (`Clibcurl` + `SecTrust`) | Explicit/implicit TLS FTP locked to `ftp,ftps` (no `libssh` / CVE-2025-15224) |
| **SSH Terminal** | `SwiftTerm` (`1.20.0`) | VT100/xterm emulation via `NSViewRepresentable` + explicit PTY cleanup |
| **Secrets & Trust** | Apple `Security.framework` | Native Keychain ACLs (`WhenUnlockedThisDeviceOnly`), Touch ID (`LAContext`), `SecTrustEvaluateWithError` |
| **Persistence** | JSON (`Codable`) + `SQLite3` WAL | Atomic profile JSON (`ConnectionStore`) + ACID `TransferJournal` (macOS 13+) |
| **Testing** | Swift Testing + Docker Compose | Deterministic OpenSSH, vsftpd, and ProFTPD test fixtures |
| **Distribution** | Universal 2 DMG + Sparkle | `arm64` + `x86_64`, Developer ID notarized, Ed25519 signed updates |

---

## System Architecture

```mermaid
flowchart TD
    UI["UI Layer (SwiftUI + NSTableView + SwiftTerm)"]
    VM["ViewModels (@MainActor ObservableObject)"]
    APP["Application Core (AppState · TransferQueue · TransferScheduler)"]
    DOM["Domain Layer (RemoteConnection · RemoteFileSystem · AppError)"]
    PA["Protocol Adapters (SFTP · SSH · FTP/FTPS · SCP)"]
    SEC["Security Layer (KeychainService · HostTrustStore · SecTrust)"]
    PERS["Persistence (ConnectionStore JSON · TransferJournal SQLite3)"]

    UI --> VM
    VM --> APP
    APP --> DOM
    PA --> DOM
    SEC --> DOM
    PERS --> DOM
    APP --> PA
    APP --> SEC
    APP --> PERS
    PA --> SEC
```

### Non-Negotiable Layering Invariants

1. `App -> SparkleFeatures -> Packages/*`; `ProtocolAdapters -> Domain`, `Security -> Domain`, `Persistence -> Domain`.
2. Views and ViewModels must **never** invoke `NIOSSH`, `Clibcurl`, `SQLite3`, or Keychain directly.
3. `Packages/` modules must **never** import from `Features/`.
4. Transfer lifecycles live inside the actor-isolated `TransferQueue` — completely independent of window/tab lifecycles.

---

## Security & Hardening Baseline

Every design decision in SparkleSFTP enforces the remediation outcomes documented in [`docs/CODE_REVIEW_14_PILLARS.md`](docs/CODE_REVIEW_14_PILLARS.md):

| Control | Standard / Reference | Enforcement |
| :--- | :--- | :--- |
| **SSH Pre-Auth Safety** | CVE-2026-43798 | Pin `apple/swift-nio-ssh >= 0.15.1` (`>= 0.14.1`) in `Package.swift` |
| **libcurl SSH Auth Safety** | CVE-2025-15224 | Lock `Clibcurl` to `ftp,ftps` (`CURLOPT_PROTOCOLS_STR`); zero `libssh` surface |
| **Keychain Device Lock** | CWE-312 / CWE-522 | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + SwiftLint rule |
| **TLS Verification** | CWE-295 | `SecTrustEvaluateWithError` + OCSP + zero silent FTPS downgrade |
| **Host Key Trust** | TOFU State Machine | 6-state lifecycle; changed keys hard-block connection |
| **Path & Symlink Safety** | CWE-22 / CWE-59 | Canonical path containment + symlink destination & loop guards |
| **Update Integrity** | Ed25519 + TLS | `UpdateConfigurationValidator` blocks non-HTTPS feeds & placeholder keys |
| **Log Redaction** | CWE-532 | `OSLog` privacy labels + SwiftLint `no_password_in_logs` |

---

## Repository Layout

### Implemented Swift 6 Repository Structure (Full MVP)

```text
SparkleSFTP/
├── Package.swift              # Swift 6.0 manifest (.macOS(.v13), pinned SPM dependencies)
├── App/                       # Executable entry, AppDelegate, SparkleUpdaterService, Info.plist, Entitlements
├── Packages/
│   ├── Clibcurl/              # Non-variadic C helper bridge over system libcurl
│   ├── Core/                  # Domain models, RemotePath, AppError, Protocols, FeatureFlags, UpdateModels
│   ├── DesignSystem/          # SparkNotePad theme palettes (28 themes / 15 families), components, EN/ID JSON Locales (285 keys)
│   ├── FileManager/           # LocalFileService, LocalDirectoryWatcher, POSIXPermissions, DualPaneState
│   ├── Networking/            # SFTPPacketCodec, SFTPService, SSHClientService, SCP, FTPService, Proxy
│   ├── Persistence/           # ConnectionStore (JSON), TransferJournal (SQLite3 WAL), FileZilla/WinSCP & SSH Importers
│   ├── Security/              # KeychainService, HostTrustStore, SecTrust, PathValidator, KeyParser, UpdateValidator
│   ├── Synchronization/       # DirectoryScanner, SyncPlanner (One-Way & Bidirectional, 60s TTL), SyncExecutor
│   ├── Terminal/              # SwiftTerm TerminalViewRepresentable, SessionManager, PortForwardingManager
│   └── TransferEngine/        # TransferQueue actor, TransferScheduler, ResumeValidator, SHA256Verifier
├── Features/                  # SwiftUI + AppKit Views (Commander, ConnectionListTableView, About, Notepad2 Editor, Terminal, Transfers, Sync, Settings)
├── Tests/                     # 8 test targets (64 tests across 17 Swift Testing suites, incl. live loopback SSH/SFTP)
├── Tools/
│   ├── Release/               # Universal 2 build-universal.sh, create-dmg.sh, notarize.sh
│   └── TestServers/           # Docker Compose fixtures (OpenSSH, vsftpd, ProFTPD) & smoke runner
├── .github/workflows/         # ci.yml, release.yml, mega-linter.yml, codeql.yml, jekyll-gh-pages.yml
└── docs/                      # Architecture, Technical Spec, Security Model, Workground, 14-Pillar Review, ADRs 0001–0006
```

---

## Roadmap Summary

| Phase | Milestone | Focus & Status |
| :--- | :--- | :--- |
| **Phase 00** | Repository Bootstrap | Governance, specs, 14-pillar fixes, ADRs, CI & lint guardrails *(Done)* |
| **Phase 01–02** | Research & Foundation | Audited SPM graph ([ADR-004](docs/ADR/0004-direct-swift-nio-ssh-and-sftp-codec.md), [ADR-005](docs/ADR/0005-macos13-sqlite3-journal-and-observable-object.md)), `Package.swift`, `Core`, `DesignSystem` *(Done)* |
| **Phase 03** | Connection & Security | `ConnectionStore`, `KeychainService`, TOFU `HostTrustStore`, `SecTrust`, Touch ID *(Done)* |
| **Phase 04** | Protocol Engines | `SSHClientService` (`swift-nio-ssh 0.15.1`), SFTP v3 codec, SCP, `Clibcurl` FTP/FTPS *(Done)* |
| **Phase 05** | Commander UI | Dual-pane `NSTableView`, F5–F8 shortcuts, Quick Look, Finder drag-drop *(Done)* |
| **Phase 06** | Transfer Engine | Actor `TransferQueue`, per-host throttling, `SQLite3` `TransferJournal`, SHA-256 atomic write *(Done)* |
| **Phase 07** | Terminal & Sync | `SwiftTerm` multi-tab/split PTY, `-L`/`-R` port forwarding, dry-run sync, EN/ID *(Done)* |
| **Phase 08** | QA & Release | 64 tests in 17 suites (129 Swift files), Full Workspace Themes + 6-Tab About + 1:1 Logo + Keychain Remember Password + AppKit Cursor Navigation + C11 IDE config, Universal 2 DMG (`release.yml`), CI/lint green; production notarization pending Developer ID *(In Progress)* |

---

## Documentation & ADRs

- **[Implementation Plan (`docs/IMPLEMENTATION_PLAN.md`)](docs/IMPLEMENTATION_PLAN.md)** — Full blueprint, interfaces, workgrounds, 125 tasks, and Docker test matrix.
- **[Technical Specification (`docs/TECHNICAL_SPECIFICATION.md`)](docs/TECHNICAL_SPECIFICATION.md)** — Target graph, toolchain contracts, and milestone acceptance gates.
- **[Security Model (`docs/SECURITY_MODEL.md`)](docs/SECURITY_MODEL.md)** — Threat controls, TOFU state machine, Keychain ACLs, and TLS rules.
- **[Workground Breakdown (`docs/WORKGROUND.md`)](docs/WORKGROUND.md)** — Domain workstreams (`WG-1`–`WG-9`) and module dependency graph.
- **[Task List (`docs/TASK_LIST.md`)](docs/TASK_LIST.md)** — Executable checklist across Milestones M1–M6.
- **[Engineering Notes (`DOCNOTE.md`)](DOCNOTE.md)** — Verified dependency findings and SDK compatibility resolutions.
- **[14-Pillar Code Review (`docs/CODE_REVIEW_14_PILLARS.md`)](docs/CODE_REVIEW_14_PILLARS.md)** — 55 findings across bugs, concurrency, memory, security CVEs, scalability, and linting.
- **[Post-Completion Long-Term Review (`docs/LONG_TERM_REVIEW_2026_11.md`)](docs/LONG_TERM_REVIEW_2026_11.md)** — 14-pillar architectural health report, technical debt register, CVE/CWE posture, SwiftUI/Swift 6 audit, and 90-day / 12-month roadmap.
- **[System Architecture (`docs/ARCHITECTURE.md`)](docs/ARCHITECTURE.md)** — Module boundaries and concurrency invariants.
- **[Roadmap & Release Gate (`docs/ROADMAP.md`)](docs/ROADMAP.md)** — Delivery milestones and MVP gate criteria.
- **[ADR-001: Tech Stack & Protocols](docs/ADR/0001-tech-stack-and-protocols.md)**
- **[ADR-002: Keychain Isolation & Host Trust](docs/ADR/0002-security-keychain-and-host-trust.md)**
- **[ADR-003: Metadata Persistence (JSON vs SwiftData)](docs/ADR/0003-metadata-persistence-swiftdata-vs-json.md)**
- **[ADR-004: Direct `swift-nio-ssh` & Native SFTP v3](docs/ADR/0004-direct-swift-nio-ssh-and-sftp-codec.md)**
- **[ADR-005: macOS 13+ SQLite3 Journal & `ObservableObject`](docs/ADR/0005-macos13-sqlite3-journal-and-observable-object.md)**
- **[ADR-006: Multi-Themes, JSON i18n, Notepad2 Editor & Auto-Update Fallback](docs/ADR/0006-post-mvp-theming-i18n-notepad2-and-updater.md)**

---

## Contributing & Quality Gates

Contributions are welcome! Please review [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) before opening a pull request.

Repository build, test, and linter gates can be run locally:

```bash
swiftlint lint --strict
swiftformat --lint .
swift build -j 2
swift test -j 2
markdownlint-cli2 "**/*.md" "#.build" "#DerivedData" "#.trunk"
yamllint -c .yamllint.yml .
shellcheck -s bash Tools/**/*.sh
actionlint
```

---

## License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for the full text.

---

<p align="center">
  Made for macOS engineers by <a href="https://github.com/alsyundawy"><b>@alsyundawy</b></a>
</p>
