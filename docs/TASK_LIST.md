# SparkleSFTP — Executable Task List (Full MVP)

This task list tracks every concrete engineering task required to deliver the **Full MVP** initial repository implementation of **SparkleSFTP** (`Swift 6`, `macOS 13+`, `SwiftUI + AppKit`, `Open-Source MIT`).

## Milestone 1: Foundation, Manifest & Design System (`WG-1`)

- [x] **T-001** Create `Package.swift` (`swift-tools-version: 6.0`, `.macOS(.v13)`) with pinned dependencies (`apple/swift-nio-ssh >= 0.15.1` resolved `0.15.1`, `apple/swift-nio` `2.105.0`, `apple/swift-crypto` `3.15.1`, `SwiftTerm 1.19.0 ..< 1.99.0` resolved `1.20.0`, `Sparkle 2.10.1 ..< 3.0.0` resolved `2.10.1`) and strict acyclic target layout.
- [x] **T-002** Create `Packages/Clibcurl` C wrapper target (`include/Clibcurl.h`, `ClibcurlHelpers.c`) wrapping variadic `curl_easy_setopt` safely for Swift 6.
- [x] **T-003** Implement `Packages/Core` (`RemotePath`, `AppError`, `TransferModels`, `RemoteFileModels`, `ConnectionModels`, `Protocols`, `FeatureFlags`).
- [x] **T-004** Implement `Packages/DesignSystem` (semantic colors/spacing tokens, typography, SF Symbols helpers, reusable badges/progress views, EN/ID localized strings).
- [x] **T-005** Write and pass `CoreTests` (`RemotePath`, `AppError`, `FeatureFlags`, `TransferProgress`, `AppStrings`).

## Milestone 2: Security Engine & Durable Persistence (`WG-7`)

- [x] **T-006** Implement `Packages/Security`: `DiagnosticsLogger`, `KeychainService` (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + optional Touch ID `LAContext`), `HostTrustStore` (6-state TOFU), `TLSCertificateValidator` (`SecTrustEvaluateWithError` + `NWProtocolTLS`), `PathValidator` (`CWE-22`/`CWE-59`), `PrivateKeyParser` (OpenSSH Ed25519/ECDSA + fingerprint), `SecurityScopedBookmarkManager`.
- [x] **T-007** Implement `Packages/Persistence`: `ConnectionStore` (atomic versioned JSON, zero secrets), `TransferJournal` (`SQLite3` WAL ACID checkpoints, crash reconciliation, 10,000-entry / 30-day retention), `SSHConfigParser`, `ExternalImporters` (FileZilla XML + WinSCP `.ini`).
- [x] **T-008** Write and pass `SecurityTests` and `PersistenceTests`.

## Milestone 3: Protocol Engines (`WG-2`, `WG-3`)

- [x] **T-009** Implement `SFTPPacketModels`, `SFTPPacketCodec` (`+Decode`), `SFTPChannelBridge`, and `SSHClientService` (`+Helpers`) on `apple/swift-nio-ssh 0.15.1` (TOFU host verification, password/public-key auth, keepalive & exec, PTY channels, `DirectTCPIP`).
- [x] **T-010** Implement `SFTPService` (`+Helpers`) (streaming `READ`/`WRITE`, resume offsets, `OPENDIR`/`READDIR`, `LSTAT`/`SETSTAT`, `MKDIR`, `REMOVE`, `RENAME`, `REALPATH`) and `SCPCompatibilityAdapter` (strict POSIX escaping).
- [x] **T-011** Implement `FTPService`, `CurlClientHelper`, and `FTPListingParser` over `Clibcurl` (Plain FTP with security warning flag, Explicit FTPS `CURLUSESSL_ALL`, Implicit FTPS port 990, TLS 1.2+, `SecTrust` preflight, resume offset, zero silent downgrade) + `RemoteServiceFactory`.
- [x] **T-012** Write and pass `NetworkingTests`.

## Milestone 4: Transfer Engine, Local File Manager & Synchronization (`WG-4`, `WG-6`, `WG-8`)

- [x] **T-013** Implement `Packages/TransferEngine`: `ProgressThrottler` (100ms / `.bufferingNewest(10)`), `SHA256Verifier` (background `FileHandle`), `ResumeValidator` (remote mtime+size+partial verify), `TransferScheduler` (global=3, per-host=2), `ConflictResolver`, `TransferQueue` actor (`+Execution`) (post-`await` reentrancy guard, weak Task handles, `deinit` cancel, atomic temp-write + verify + rename, crash reconciliation).
- [x] **T-014** Implement `Packages/FileManager`: `LocalFileService` (enumeration + `LocalDirectoryWatcher` with explicit cancel/`deinit`), `FileSortDescriptor`, `POSIXPermissions`, `DualPaneState`.
- [x] **T-015** Implement `Packages/Synchronization`: `DirectoryScanner` (circular symlink loop guard), `SyncPlanner` (tiered size -> mtime -> SHA-256 + `expiresAt` 60s), `SyncExecutor` (revalidation before destructive actions).
- [x] **T-016** Write and pass `TransferEngineTests`, `FileManagerTests`, and `SynchronizationTests`.

## Milestone 5: Terminal, SwiftUI + AppKit UI & App Entry (`WG-4`, `WG-5`)

- [x] **T-017** Implement `Packages/Terminal`: `TerminalViewRepresentable` (`SwiftTerm.TerminalView` + explicit cleanup), `TerminalSessionManager` (PTY lifecycle + `WindowChangeRequest` + 100-tab leak prevention), `CommandSnippetStore`, `PortForwardingManager`.
- [x] **T-018** Implement `Features/`: `AppState` (`+Connections`, `+Operations`, `+Imports`), `MainWindowView`, `ConnectionManagerView`, `ConnectionEditorView`, `HostKeyVerificationSheet`, `SecurityDiagnosticsView`, `DualPaneCommanderView`, `FilePaneTableView` (`NSTableView` with cell reuse), `PermissionsEditorSheet`, `QuickLookCoordinator`, `TransferQueueView`, `ConflictResolutionSheet`, `TerminalWorkspaceView` (tabs + splits), `PortForwardingSheet`, `SnippetsSheet`, `SyncPreviewSheet`, `PreferencesView`.
- [x] **T-019** Implement `App/`: `SparkleSFTPApp`, `AppDelegate`, `AppEnvironment`, `SparkleUpdaterService`, `Resources/Info.plist`, `SparkleSFTP.entitlements`.
- [x] **T-020** Write and pass `IntegrationTests` (end-to-end local/mocked transfer + sync + PTY session teardown + `swift build` executable).

## Milestone 6: Release Tooling, Documentation Reconciliation & Verification (`WG-9`)

- [x] **T-021** Create `Tools/TestServers/` (`docker-compose.test.yml`, fixture configs, `run-integration-tests.sh`) and `Tools/Release/` (`build-universal.sh`, `notarize.sh`, `create-dmg.sh`).
- [x] **T-022** Reconcile `README.md`, `README-id.md`, `docs/ARCHITECTURE.md`, `docs/IMPLEMENTATION_PLAN.md`, `docs/ROADMAP.md`, `CHANGELOG.md`, `DOCNOTE.md`, `TODO.md`, and `tasks/`.
- [x] **T-023** Run full verification gates: `swift build -j 2`, `swift test -j 2` (`71 tests in 18 suites` incl. live encrypted loopback SSH/SFTP, 8x pipelined 512 KB upload/download SHA-256 verification, `zlib`/`gzip` CWE-409 overflow checks, `ToolchainInspector`, `ExternalTerminalLauncher` CWE-78 check, FileZilla conflict policies & FIFO queue auto-drain, `ProxyJump`, `SOCKS5`/`HTTP` SSH proxy, `DirectTCPIP` + remote `-R` forwarding, TLS rejection, `UpdateConfigurationValidator`, 100MB SHA-256, disk-partial pause/resume, mid-transfer cancel, pre-existing destination symlink check, CRLF guard, strict HTTP proxy `200` status validation, SparkNotePad themes & full workspace propagation, 7-tab About diagnostics, Remember Password Keychain & `FTPService` prompt flows, JSON i18n `309`-key parity, FileZilla/WinSCP BOM importers, Notepad2 editor models, bidirectional sync, and AppKit row keys/cloning/batch deletion/performance invariants), `swiftlint lint --strict` (`0 violations` in `135` files), `swiftformat --lint .` (`0/135`), `yamllint -c .yamllint.yml .`, `shellcheck -s bash`, `shfmt -d -i 2 -ci`, `markdownlint-cli2`, `clang-format --dry-run --Werror`, `cppcheck`, `clang -fsyntax-only`, `actionlint` — 0 errors across every executed gate.
- [x] **T-024** Build and verify Universal 2 (`x86_64 arm64`) `.app` bundle (with embedded `Sparkle.framework` & entitlements) + `SparkleSFTP-0.2.0-universal.dmg` + `.sha256` locally via `Tools/Release/build-universal.sh` & `create-dmg.sh`, plus `.github/workflows/release.yml` CI/CD release automation.

## Milestone 7: Post-MVP Quality-of-Life, Multi-Themes, i18n & Notepad2 Editor (`WG-1`, `WG-4`, `WG-7`, `WG-8`, `WG-9`)

- [x] **T-025** Implement SparkNotePad-inspired multi-theme engine (`SparkleThemePalette`, `SparkleThemeCatalog`, `ThemeCatalogExtended`, `SparkleThemeStore`) providing `28` themes across `15` families, `Auto`/`Light`/`Dark` switching, WCAG AA contrast validation, and custom JSON theme import/export (`PreferencesThemeTab`).
- [x] **T-026** Implement full Auto-Update Preferences (`AutoUpdateSettings`, `PreferencesUpdatesTab`, `SparkleUpdaterService`, `UpdateConfigurationValidator.isNewerVersion`) with frequency, channel, validated HTTPS feed URL, Ed25519 verification badge, and community GitHub Releases API check fallback.
- [x] **T-027** Migrate `AppStrings` to maintainable JSON locale catalogs (`Resources/Locales/en.json` & `id.json`, `309` synchronized keys) + runtime override directory (`LocalizationCatalog`) + Preferences card-grid selector & coverage/import/export tools (`PreferencesLocalizationTab`) + toolbar/status-bar/menu Globe switchers (`MainWindowView`, `SparkleSFTPApp`).
- [x] **T-028** Enhance FileZilla XML (`<Folder>` stack, `base64`, `crypt` rejection) & WinSCP INI (UTF-16LE/BE/UTF-8 BOM, nested `Sessions\Folder%2FName`, `FSProtocol` `0/1/2/5`, proxies) readers (`WinSCPAndFileReader`) + `.ini` `UTType` picker + interactive `ImportConnectionsSheet`.
- [x] **T-029** Build Minimalist Notepad2 Internal File Editor (`Features/Editor/`: `EditorModels`, `EditorSessionManager`, `EditorSyntaxHighlighter`, `NotepadTextView`, `NotepadLineNumberRuler`, `InternalEditorToolbar`, `InternalEditorBars`, `InternalEditorView`, `EditorWindowController`) with Commander integration and remote upload-on-save.
- [x] **T-030** Implement Bidirectional & Reverse Folder Synchronization (`TASK-108` across `SyncPlanner`, `SyncExecutor`, `SyncPreviewSheet`, `BidirectionalSyncTests`, `EditorAndSyncTests`).
- [x] **T-031** Conduct 14-pillar / 14-skill Post-Completion Long-Term Review ([`docs/LONG_TERM_REVIEW_2026_11.md`](LONG_TERM_REVIEW_2026_11.md), [ADR-006](ADR/0006-post-mvp-theming-i18n-notepad2-and-updater.md), [ADR-007](ADR/0007-third-party-toolchain-pipelined-transfers-and-filezilla-conflicts.md)), verify SonarQube/MegaLinter/SwiftLint gates, and harden `.app` resource bundle lookup against `Bundle.module` `fatalError` crashes.
- [x] **T-032** Connection UX, Fast Quit & Runtime Performance Tuning: double-click connect on Connection List rows, atomic `ConnectionEditorMode` `.sheet(item:)` Edit modal (`ConnectionEditorView`), **Clone Connection** (`AppState.cloneProfile`) with independent Keychain secrets, `⌘A` Select All + batch Delete Selected confirmation (`ConnectionStore.deleteProfiles`), non-deadlocking `AppDelegate.applicationShouldTerminate` + bounded parallel NIO teardown, `TransferMonitor` 10Hz progress isolation, cached `strings`/`activePalette`, 2s SQLite checkpoint throttling, and single-`lstat` POSIX enumeration (`ConnectionManagementAndPerfTests`).
- [x] **T-033** Full Workspace Theme Propagation, SparkNotePad-Style About Window, 1:1 Branded Logo, Remember Password, AppKit Navigation Focus & C11 IDE Hygiene: propagate `SparkleThemePalette` across SwiftUI (`sparkleWorkspaceSurface`), AppKit tables, `TerminalThemeColors`, and `NSApp.windows`; build 7-tab `AboutView`/`AboutWindowController` (incl. `Libraries`); update `AppIcon.png`/`.icns` (`1024x1024` 1:1 squircle in blue/white/pastel-yellow); wire Keychain **Remember Password** toggle + Clear Saved + `FTPService` runtime prompt; replace SwiftUI `List` gesture conflict with `ConnectionListTableView` (`NSTableView` unique row keys) + `InteractiveFileTableView`; configure `.clangd`/`compile_flags.txt`/`.clang-format` for `ClibcurlHelpers.c` & `ClibcurlSystemLibs.c` (`AboutAndThemePasswordTests`).
- [x] **T-034** Third-Party Toolchain Bridge, Pipelined Multi-Thread Transfers & FileZilla Conflict Flow: link `-lcurl -lz` (`zlib`) in `Packages/Clibcurl/ClibcurlSystemLibs.c` + bounded `ZlibCompressionCodec`, optimize `CurlClientHelper` (`256 KB` buffers, `TCP_NODELAY`/`TCP_KEEPALIVE`, GCD worker dispatch), add dynamic `dlopen` `libssh2` probe + `OpenSSL`/`OpenSSH`/POSIX shell detection (`ToolchainInspector`), `LocalShellTerminalRepresentable` local shell tabs, sanitized `ExternalTerminalLauncher` (`iTerm2`/`Terminal.app`), actor-free `SFTPPipelinedTransfer` (`8x` window) + `TransferScheduler` (`4` global / `3` per-host), FileZilla `ConflictResolutionSheet` + FIFO `pendingConflictQueue`, and card-grid + toolbar/menu language switcher (`ToolchainAndConflictTests`).
- [x] **T-035** Post-Completion 14-Pillar / 14-Skill Long-Term Review Refresh (`1b9d9f4`): audit all `135` Swift files, `3` C11 files, `27` Markdown files, CI/MegaLinter runs, explicit SonarQube server gap (`TD-08`), `17` prod `@unchecked Sendable` / `6` `DispatchQueue` call sites, SwiftUI/`NSTableView` perf, protocol/CWE posture, `SwiftTerm`/`TransferJournal`/Docker/Release gaps (`TD-01`–`TD-15`), and commit updated [`docs/LONG_TERM_REVIEW_2026_11.md`](LONG_TERM_REVIEW_2026_11.md) + `CHANGELOG.md`.

## Post-MVP / External Infrastructure Gates (Deferred)

- [ ] Run live Docker server integration tests (`Tools/TestServers/run-integration-tests.sh`) against live SSH/SFTP/FTP containers (Docker runtime not installed on this host).
- [ ] Execute Developer ID notarization (`xcrun notarytool submit` via `Tools/Release/notarize.sh`) and live Sparkle Ed25519 appcast signing on release host.
