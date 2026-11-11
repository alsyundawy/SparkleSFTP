# Changelog

All notable changes to **SparkleSFTP** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Planned (Post-MVP / External Infrastructure)

- Live Docker multi-server interop test execution (`Tools/TestServers/run-integration-tests.sh`).
- Universal 2 (`arm64` + `x86_64`) Apple Developer ID signing, notarization, and signed Sparkle Ed25519 appcast publishing (`Tools/Release/notarize.sh`).

---

## [0.2.0] - 2026-11-11

### Added & Fixed (14-Pillar Security, Runtime, CI & Release Hardening)

- **CI Compatibility & Tooling Alignment**:
  - Updated `TerminalViewRepresentable` to keep `@MainActor` on `Coordinator` with `nonisolated TerminalViewDelegate` methods forwarding safely onto `MainActor`, resolving Swift 6.0/6.1 Xcode compilation errors on GitHub Actions `macos-15` runners while preserving Swift 6.2 strict concurrency.
  - Harmonized `.swiftformat` (`--trailing-commas never`, `--exclude .build,.swiftpm,DerivedData,build,dist,.trunk`, disabling `trailingCommas` conflict & `wrapMultilineStatementBraces`) with `.swiftlint.yml`, and added build artifact `ignore:` rules to `.yamllint.yml`.
  - Added `.github/workflows/release.yml` to run `swift test -j 2`, build the Universal 2 (`arm64` + `x86_64`) `.app` and `.dmg` + `.sha256` checksum on GitHub Actions `macos-15` runners, and publish GitHub Releases on `v*` tags / manual dispatch.
- **Security & Networking Hardening (`SparkleSecurity` & `SparkleNetworking`)**:
  - Added `UpdateConfigurationValidator` + `SparkleUpdaterService` enforcement rejecting non-HTTPS appcast URLs and placeholder/invalid Ed25519 `SUPublicEDKey` values (`Info.plist`).
  - Hardened `PathValidator.safeLocalDestination` (`CWE-59`) to reject pre-existing symbolic links at local destination paths.
  - Hardened `SSHProxyChannelHandler` to reject whitespace/NUL/out-of-range ports and enforce exact `"200"` HTTP CONNECT status tokens (`HTTP/... 200`), and added IPv6 host bracketing plus integer-overflow guards in `FTPService` / `CurlClientHelper`.
  - Bounded `SFTPChannelBridge` initialization/request futures, `SSHClientService+Forwarding` remote `-R` forward requests with stall timeouts + cancellation handlers, `.name` packet decoded entry count validation (`SFTPPacketCodec+Decode`), and streamed 24KB chunked uploads in `SCPCompatibilityAdapter` (avoiding `ARG_MAX` limits).
- **Transfer Engine, State & UI Fixes (`SparkleTransferEngine`, `Packages/TransferEngine`, `Features/`)**:
  - Fixed `TransferQueue` `LOG-002` resume validation ordering so remote size/mtime changes are checked before updating checkpoint context, reset stale `.part` state cleanly, switched final overwrite moves to `FileManager.default.replaceItemAt`, wired `journal.pruneOldEntries(maxEntries: 10_000, maxAgeDays: 30)` on crash restore, and split checkpoint helpers into `TransferQueue+Checkpoint.swift`.
  - Guarded `AppState` against redundant local directory watcher teardowns (`watchedLocalURL`), ensured active sessions disconnect when deleted (`deleteProfile`), preserved `FilePaneTableView` selection across programmatic refreshes, and used `lastIndex(of: ":")` for IPv6-safe host-key revocation in `ConnectionSecuritySheets`.
- **Deep Audit Capabilities Completed**:
  - Pause/resume byte measurement, `ConflictResolver` remote upload enforcement (`.skip`/`.overwrite`/`.rename`), `SSHProxyChannelHandler` (SOCKS5 + HTTP CONNECT), SSH `ProxyJump` bastion chaining, 2FA interactive prompt (`CredentialPromptSheet`), `-L`/`-R` port forwarding, remote path sync + `PaneNavigationHistory`, `RenameItemSheet`, `FileInspectorSheet` (async SHA-256), `NSMenu` context menu, remote Quick Look, recursive folder upload/download, and `ServerGroup`/Recents management.
- **Verification**: All `45 tests in 11 suites` pass via `swift test -j 2` (with 5 new regression tests in `SecurityTests`, `NetworkingTests`, and `TransferEngineResumeTests`), `94` Swift files pass `swiftlint lint --strict` and `swiftformat --lint .` with `0` violations, and `markdownlint-cli2`, `yamllint`, `actionlint`, `shellcheck`, and `shfmt` report `0` errors.

---

## [0.2.0-mvp] - 2026-11-11

### Added

- **Architecture Reconciliation & Documentation**:
  - Added [`docs/ADR/0004`](docs/ADR/0004-direct-swift-nio-ssh-and-sftp-codec.md) (direct `apple/swift-nio-ssh 0.15.1` + custom RFC SFTP v3 binary codec superseding Citadel) and [`docs/ADR/0005`](docs/ADR/0005-macos13-sqlite3-journal-and-observable-object.md) (`Security.framework`, `SQLite3` WAL, `@MainActor ObservableObject` for macOS 13+ superseding GlasSecretStore & SwiftData).
  - Created [`docs/TECHNICAL_SPECIFICATION.md`](docs/TECHNICAL_SPECIFICATION.md), [`docs/SECURITY_MODEL.md`](docs/SECURITY_MODEL.md), [`docs/WORKGROUND.md`](docs/WORKGROUND.md), [`docs/TASK_LIST.md`](docs/TASK_LIST.md), [`DOCNOTE.md`](DOCNOTE.md), [`TODO.md`](TODO.md), [`tasks/plan.md`](tasks/plan.md), and [`tasks/todo.md`](tasks/todo.md).
- **Swift 6 Acyclic Package & Executable Implementation (`Package.swift`, `.macOS(.v13)`)**:
  - `Clibcurl` (`Packages/Clibcurl`): non-variadic typed C helpers wrapping `curl_easy_setopt` for Swift 6 over system `libcurl`.
  - `SparkleCore` & `SparkleDesignSystem`: `Sendable` domain models/protocols (`RemotePath`, `AppError`, `TransferModels`, `ConnectionModels`, `FeatureFlags`), semantic theme tokens, reusable SwiftUI badges/bars, and EN/ID localization (`AppStrings`).
  - `SparkleSecurity`: `KeychainService` (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + `LAContext` Touch ID gate), 6-state TOFU `HostTrustStore`, `TLSCertificateValidator` (`SecTrustEvaluateWithError` + `NWProtocolTLS` preflight), `PathValidator` (`CWE-22` / `CWE-59`), `PrivateKeyParser` (OpenSSH Ed25519 / ECDSA P-256/384/521 + SHA-256 fingerprint), `SecurityScopedBookmarkManager`, and privacy-redacted `DiagnosticsLogger`.
  - `SparklePersistence`: `ConnectionStore` (atomic versioned JSON, zero secrets), `TransferJournal` (`SQLite3` WAL ACID journal with crash reconciliation and bounded retention), `SSHConfigParser`, and `ExternalImporters` (FileZilla XML + WinSCP INI).
  - `SparkleNetworking`: `SFTPPacketModels`, `SFTPPacketCodec` (`+Decode`), `SFTPChannelBridge`, `SSHClientService` (`+Helpers`) over `apple/swift-nio-ssh 0.15.1`, `SFTPService` (`+Helpers`), `SCPCompatibilityAdapter`, `FTPService`, `CurlClientHelper`, `FTPListingParser`, and `RemoteServiceFactory`.
  - `SparkleTransferEngine`: `TransferQueue` (`+Execution`) actor with post-`await` reentrancy guards, bounded retry/non-retryable security & integrity errors, `TransferScheduler` (global=3, per-host=2), `ResumeValidator`, `SHA256Verifier`, `ProgressThrottler`, and `ConflictResolver`.
  - `SparkleFileManager` & `SparkleSynchronization`: `LocalFileService`, `LocalDirectoryWatcher`, `FileSortDescriptor`, `POSIXPermissions`, `DualPaneState`, `DirectoryScanner` (circular symlink loop protection), `SyncPlanner` (60s TTL), and `SyncExecutor` (pre-mutation remote revalidation).
  - `SparkleTerminal`: `TerminalViewRepresentable` (`SwiftTerm 1.20.0`), `TerminalSessionManager` (100-tab teardown safety), `CommandSnippetStore`, and `PortForwardingManager` (`DirectTCPIP`).
  - `SparkleFeatures` & `SparkleSFTP` (`Features/`, `App/`): `AppState` (`+Connections`, `+Operations`, `+Imports`), SwiftUI + AppKit `FilePaneTableView` (`NSTableView`), `QuickLookCoordinator`, `ConnectionViews`, `TransferQueueView`, `TerminalWorkspaceView`, `SyncPreviewSheet`, `PreferencesView`, `MainWindowView`, `SparkleUpdaterService` (`Sparkle 2.10.1`), `Info.plist`, and App Sandbox entitlements.
  - `Tools/`: Docker SSH/SFTP/FTP test fixture (`Tools/TestServers/`) and Universal 2 release/notarization/DMG scripts (`Tools/Release/`).
  - **Verification**: Full `swift build` executable build, Universal 2 (`x86_64 arm64`) `.app` + `.dmg` packaging (`Tools/Release/build-universal.sh` & `create-dmg.sh`, ad-hoc `codesign`), `35 tests in 9 suites` passing via `swift test` (including live encrypted loopback SSH/SFTP, Ed25519 + `DirectTCPIP` port forwarding, host-key rotation `.hostKeyMismatch` block, X.509 TLS rejection, `100MB` off-MainActor SHA-256 verification, mid-transfer cancel reentrancy, and FTP CWE-93 CRLF sanitizer), `0` violations on `swiftlint lint --strict` (81 Swift files), `0` issues on `markdownlint-cli2`, `shellcheck -s bash`, and `actionlint`.
  - **Security & Runtime Fixes Verified**: Added `UserAuthSuccessEvent` handshake gate in `SSHClientService.connect()` via `SSHErrorTrackerHandler`/`SSHHandshakeStateBox`, UTF-8 byte-level CRLF guard in `FTPService.sanitizeControlPath`, child channel lifecycle cleanup in `PortForwardingManager`, and dynamic concurrency stepper updates (`TransferQueue.updateConcurrencyLimits`) plus `UNUserNotificationCenter` completion alerts.

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
