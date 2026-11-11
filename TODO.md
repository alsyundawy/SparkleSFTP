# SparkleSFTP — Master TODO (Full MVP)

Live checklist tracking the Full MVP implementation of **SparkleSFTP** (`Swift 6`, `SwiftUI + AppKit`, `macOS 13+`, `Open-Source MIT`).
Detailed task breakdown and acceptance specs live in [`docs/TASK_LIST.md`](docs/TASK_LIST.md), [`tasks/plan.md`](tasks/plan.md), and [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md).

## Phase A: Architecture, Docs & Manifest (`WG-1`)

- [x] Verify `/Users/alsyundawy/Downloads/GitHub/SparkleSFTP/docs/*.md` lineage (`MacSFTP` -> `SparkleSFTP`)
- [x] Audit upstream SPM dependencies & SDK (`apple/swift-nio-ssh 0.15.1`, `SwiftTerm 1.20.0`, `Sparkle 2.10.1`, system `libcurl`, `SQLite3`)
- [x] Create `docs/ADR/0004` & `docs/ADR/0005` (macOS 13+ & CVE-2026-43798 alignment)
- [x] Create `docs/TECHNICAL_SPECIFICATION.md`, `docs/SECURITY_MODEL.md`, `docs/WORKGROUND.md`, `docs/TASK_LIST.md`, `DOCNOTE.md`, `tasks/plan.md`, `tasks/todo.md`
- [x] Create `Package.swift` and `src/Packages/Clibcurl` (`T-001`, `T-002`)
- [x] Implement `src/Packages/Core` & `src/Packages/DesignSystem` + `CoreTests` (`T-003`, `T-004`, `T-005`)

## Phase B: Security & Persistence (`WG-7`)

- [x] Implement `src/Packages/Security` (`KeychainService`, `HostTrustStore`, `TLSCertificateValidator`, `PathValidator`, `PrivateKeyParser`, `DiagnosticsLogger`, `SecurityScopedBookmarkManager`) (`T-006`)
- [x] Implement `src/Packages/Persistence` (`ConnectionStore`, `TransferJournal` SQLite3 WAL, `SSHConfigParser`, `ExternalImporters`) (`T-007`)
- [x] Pass `SecurityTests` and `PersistenceTests` (`T-008`)

## Phase C: Protocol Engines (`WG-2`, `WG-3`)

- [x] Implement `SFTPPacketCodec`, `SFTPPacketModels`, `SFTPChannelBridge`, and `SSHClientService` (`apple/swift-nio-ssh 0.15.1`) (`T-009`)
- [x] Implement `SFTPService` & `SCPCompatibilityAdapter` (`T-010`)
- [x] Implement `FTPService`, `FTPListingParser`, `CurlClientHelper`, and `RemoteServiceFactory` (`T-011`)
- [x] Pass `NetworkingTests` (`T-012`)

## Phase D: Transfer Engine, FileManager & Sync (`WG-4`, `WG-6`, `WG-8`)

- [x] Implement `src/Packages/TransferEngine` (`TransferQueue`, `TransferScheduler`, `ResumeValidator`, `SHA256Verifier`, `ProgressThrottler`, `ConflictResolver`) (`T-013`)
- [x] Implement `src/Packages/FileManager` (`LocalFileService`, `FileSortDescriptor`, `POSIXPermissions`, `DualPaneState`) (`T-014`)
- [x] Implement `src/Packages/Synchronization` (`DirectoryScanner`, `SyncPlanner`, `SyncExecutor`) (`T-015`)
- [x] Pass `TransferEngineTests`, `FileManagerTests`, and `SynchronizationTests` (`T-016`)

## Phase E: Terminal, UI & Application Shell (`WG-4`, `WG-5`)

- [x] Implement `src/Packages/Terminal` (`TerminalViewRepresentable`, `TerminalSessionManager`, `CommandSnippetStore`, `PortForwardingManager`) (`T-017`)
- [x] Implement `src/Features/` (`AppState`, `Dashboard`, `Connections`, `Commander` with `FilePaneTableView` & `QuickLookCoordinator`, `Transfers`, `Terminal`, `Synchronization`, `Settings`, `Editor`) (`T-018`)
- [x] Implement `src/App/` (`SparkleSFTPApp`, `AppDelegate`, `AppEnvironment`, `SparkleUpdaterService`, `Resources/Info.plist`, `SparkleSFTP.entitlements`) (`T-019`)
- [x] Pass `IntegrationTests` & executable `swift build` (`T-020`)

## Phase F: Release Tooling, Docs Sync & Final Verification (`WG-9`)

- [x] Implement `Tools/TestServers/` & `Tools/Release/` scripts (`T-021`)
- [x] Update `README.md`, `README-id.md`, `docs/ARCHITECTURE.md`, `docs/IMPLEMENTATION_PLAN.md`, `docs/ROADMAP.md`, `CHANGELOG.md`, `DOCNOTE.md` (`T-022`)
- [x] Implement SparkNotePad/NotepadNext multi-themes (`76` palettes / `26` families + custom JSON store + full workspace theme & `NSAppearance` propagation via `SparkleWindowConfigurator`), SparkNotePad-style 7-tab About window (`AboutView` / `AboutWindowController`, incl. `Libraries`) with full Close/Minimize/Zoom window controls & 1:1 blue/white/pastel-yellow `AppIcon`, Auto-Update settings & fallback check, JSON i18n catalog & maintenance UI (`361` keys), FileZilla/WinSCP BOM-safe preview importer, Notepad2 multi-tab internal editor (`src/Features/Editor/`), and Bidirectional Sync (`TASK-108`) (`T-025`)
- [x] Verify 0 errors across `swift build -j 2`, `swift test --no-parallel` (`81 tests in 22 suites`), `swiftlint lint --strict` (`155` files), `swiftformat --lint .` (`0/155`), `trunk check`, `sonar-scanner`/SonarQube JSON reporter, `yamllint -c .yamllint.yml .`, `shellcheck -s bash`, `shfmt -d -i 2 -ci`, `markdownlint-cli2`, `clang-format --dry-run --Werror`, `cppcheck`, `clang -fsyntax-only`, and `actionlint` (`T-023`)
- [x] Connection UX, Keychain Remember Password, Cursor/Keyboard Fix, Fast Quit & Performance Pass: Native AppKit `ConnectionListTableView` + `InteractiveFileTableView` click/keyboard focus navigation (`⌘W`, `⌘⇧[`/`⌘⇧]`, `⌘\`, scoped `Tab` pane switching, single `⇧⌘N`, AppKit responder validation), Remember/Clear Keychain password flow (`ConnectionEditorView`, `CredentialPromptSheet`, `FTPService`), double-click connect, atomic `ConnectionEditorMode` Edit sheet, Clone Connection with independent Keychain refs, `⌘A` Select All + batch Delete Selected, `applicationShouldTerminate` + bounded parallel NIO teardown, `TransferMonitor` 10Hz decoupling, cached `strings`/`activePalette`, 2s throttled SQLite journal ticks, and single-`lstat` enumeration (`T-032`)
- [x] Third-Party Toolchain Support, Multi-Thread Transfers, FileZilla Conflict Dialog & Language Switcher Layout (`T-034`): `Clibcurl` `-lz` bounded `zlib`/`gzip` (`ZlibCompressionCodec`), optimized `CurlClientHelper` (`256 KB` buffers, `TCP_NODELAY`/`TCP_KEEPALIVE`, GCD worker dispatch, `total=0` resume guard), dynamic `dlopen` `libssh2` / `OpenSSL` / `OpenSSH` probing (`ToolchainInspector`), v0.1 `terminal.fill` Shell icon + sanitized `ExternalTerminalLauncher` (`iTerm2`/`Terminal.app`/`ssh://`), actor-free `SFTPPipelinedTransfer` (`64 KB` blocks, `min(32, max(2, pipelineDepth * 4))` window), shared EWMA `TransferSpeedMeter`, POSIX permission & dotfile preservation + upload resume (`resolveUploadResumeOffset`) + debounced pane refresh, `TransferScheduler` (`4` global / `3` per-host), FileZilla `ConflictResolutionSheet` + FIFO `pendingConflictQueue`, and card-grid + toolbar/menu language switcher (`PreferencesLocalizationTab`, `MainWindowView`, `SparkleSFTPApp`)
- [x] `src/` Restructure, Multi-Window Isolation, FileZilla/WinSCP Multi-Tab Connections, Responsive Hover/Right-Click/Select-All & WinSCP Menus (`T-036`): Reorganize `src/{App,Features,Packages}`; per-window `AppEnvironment.makeWindowState()` + `FocusedValues` (`New Window` opens clean sessionless window); `WorkspaceTabBar` (AppKit `TabBarActionButton` + `WorkspaceTabStripRepresentable`, instant switch/close, `New Tab` / `Duplicate Tab` / `Reconnect` / `Open in New Window` / `Close Tab` / `Close Other Tabs`) & `QuickConnectBar` (auto-hidden when active tab connected); `NSTrackingArea` row hover + `rightMouseDown` click-select + visible Connection toolbar (`Connect`/`New`/`Edit`/`All`/`Delete`); WinSCP Commander `Edit`/`Copy... F5`/`Move... F6`/`File Custom Commands`/`File Names` context submenus; `sonar-project.properties` (`WindowTabsAndWinSCPCommandsTests`, `WindowControlsAndShortcutsTests`, `FolderPermissionsTransferTests`)
- [x] Post-Completion Long-Term Review Refresh & Documentation Sync (`T-037`): Conduct full 14-pillar / 14-skill review on live `5c2c212` tree (`155` Swift files / `29,344` LOC, `81 tests in 22 suites`), add [ADR-008](docs/ADR/0008-multi-window-isolation-appkit-tab-chrome-76-themes-and-transfer-pipeline.md), fix `sonar-project.properties` (`sonar.externalIssuesReportPaths`, `0.2.0`) while documenting unconfigured CI SonarQube server gap, align [`SECURITY.md`](SECURITY.md) / [`CONTRIBUTING.md`](CONTRIBUTING.md) / [`README.md`](README.md) / [`README-id.md`](README-id.md) / [`docs/LONG_TERM_REVIEW_2026_11.md`](docs/LONG_TERM_REVIEW_2026_11.md) / [`CHANGELOG.md`](CHANGELOG.md)
- [x] Verify Universal 2 (`x86_64 arm64`) release `.app` bundle (with embedded `Sparkle.framework` & entitlements) + `SparkleSFTP-0.2.0-universal.dmg` + `.sha256` via `Tools/Release/build-universal.sh`, `create-dmg.sh`, and `.github/workflows/release.yml` (`T-024`)

## Post-MVP / External Infrastructure Gates (Not Executed in Offline Sandbox)

- [ ] Run live Docker multi-server interop smoke suite (`Tools/TestServers/run-integration-tests.sh` against SFTP/FTP/FTPS containers; requires Docker Engine)
- [ ] Run Apple Developer ID codesigning, notarization, stapling, and Sparkle Ed25519 appcast signing (`Tools/Release/notarize.sh`; ad-hoc signing & Universal 2 DMG already verified locally)
