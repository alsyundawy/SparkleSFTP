# SparkleSFTP — Master TODO (Full MVP)

Live checklist tracking the Full MVP implementation of **SparkleSFTP** (`Swift 6`, `SwiftUI + AppKit`, `macOS 13+`, `Open-Source MIT`).
Detailed task breakdown and acceptance specs live in [`docs/TASK_LIST.md`](docs/TASK_LIST.md), [`tasks/plan.md`](tasks/plan.md), and [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md).

## Phase A: Architecture, Docs & Manifest (`WG-1`)

- [x] Verify `/Users/alsyundawy/Downloads/GitHub/SparkleSFTP/docs/*.md` lineage (`MacSFTP` -> `SparkleSFTP`)
- [x] Audit upstream SPM dependencies & SDK (`apple/swift-nio-ssh 0.15.1`, `SwiftTerm 1.20.0`, `Sparkle 2.10.1`, system `libcurl`, `SQLite3`)
- [x] Create `docs/ADR/0004` & `docs/ADR/0005` (macOS 13+ & CVE-2026-43798 alignment)
- [x] Create `docs/TECHNICAL_SPECIFICATION.md`, `docs/SECURITY_MODEL.md`, `docs/WORKGROUND.md`, `docs/TASK_LIST.md`, `DOCNOTE.md`, `tasks/plan.md`, `tasks/todo.md`
- [x] Create `Package.swift` and `Packages/Clibcurl` (`T-001`, `T-002`)
- [x] Implement `Packages/Core` & `Packages/DesignSystem` + `CoreTests` (`T-003`, `T-004`, `T-005`)

## Phase B: Security & Persistence (`WG-7`)

- [x] Implement `Packages/Security` (`KeychainService`, `HostTrustStore`, `TLSCertificateValidator`, `PathValidator`, `PrivateKeyParser`, `DiagnosticsLogger`, `SecurityScopedBookmarkManager`) (`T-006`)
- [x] Implement `Packages/Persistence` (`ConnectionStore`, `TransferJournal` SQLite3 WAL, `SSHConfigParser`, `ExternalImporters`) (`T-007`)
- [x] Pass `SecurityTests` and `PersistenceTests` (`T-008`)

## Phase C: Protocol Engines (`WG-2`, `WG-3`)

- [x] Implement `SFTPPacketCodec`, `SFTPPacketModels`, `SFTPChannelBridge`, and `SSHClientService` (`apple/swift-nio-ssh 0.15.1`) (`T-009`)
- [x] Implement `SFTPService` & `SCPCompatibilityAdapter` (`T-010`)
- [x] Implement `FTPService`, `FTPListingParser`, `CurlClientHelper`, and `RemoteServiceFactory` (`T-011`)
- [x] Pass `NetworkingTests` (`T-012`)

## Phase D: Transfer Engine, FileManager & Sync (`WG-4`, `WG-6`, `WG-8`)

- [x] Implement `Packages/TransferEngine` (`TransferQueue`, `TransferScheduler`, `ResumeValidator`, `SHA256Verifier`, `ProgressThrottler`, `ConflictResolver`) (`T-013`)
- [x] Implement `Packages/FileManager` (`LocalFileService`, `FileSortDescriptor`, `POSIXPermissions`, `DualPaneState`) (`T-014`)
- [x] Implement `Packages/Synchronization` (`DirectoryScanner`, `SyncPlanner`, `SyncExecutor`) (`T-015`)
- [x] Pass `TransferEngineTests`, `FileManagerTests`, and `SynchronizationTests` (`T-016`)

## Phase E: Terminal, UI & Application Shell (`WG-4`, `WG-5`)

- [x] Implement `Packages/Terminal` (`TerminalViewRepresentable`, `TerminalSessionManager`, `CommandSnippetStore`, `PortForwardingManager`) (`T-017`)
- [x] Implement `Features/` (`AppState`, `Dashboard`, `Connections`, `Commander` with `FilePaneTableView` & `QuickLookCoordinator`, `Transfers`, `Terminal`, `Synchronization`, `Settings`) (`T-018`)
- [x] Implement `App/` (`SparkleSFTPApp`, `AppDelegate`, `AppEnvironment`, `SparkleUpdaterService`, `Resources/Info.plist`, `SparkleSFTP.entitlements`) (`T-019`)
- [x] Pass `IntegrationTests` & executable `swift build` (`T-020`)

## Phase F: Release Tooling, Docs Sync & Final Verification (`WG-9`)

- [x] Implement `Tools/TestServers/` & `Tools/Release/` scripts (`T-021`)
- [x] Update `README.md`, `README-id.md`, `docs/ARCHITECTURE.md`, `docs/IMPLEMENTATION_PLAN.md`, `docs/ROADMAP.md`, `CHANGELOG.md`, `DOCNOTE.md` (`T-022`)
- [x] Implement SparkNotePad multi-themes (`28` palettes / `15` families + custom JSON store), Auto-Update settings & fallback check, JSON i18n catalog & maintenance UI (`263` keys), FileZilla/WinSCP BOM-safe preview importer, Notepad2 multi-tab internal editor (`Features/Editor/`), and Bidirectional Sync (`TASK-108`) (`T-025`)
- [x] Verify 0 errors across `swift build -j 2`, `swift test -j 2` (`60 tests in 16 suites`), `swiftlint lint --strict` (`122` files), `swiftformat --lint .` (`0/122`), `yamllint -c .yamllint.yml .`, `shellcheck -s bash`, `shfmt -d -i 2 -ci`, `markdownlint-cli2`, and `actionlint` (`T-023`)
- [x] Connection UX, Fast Quit & Performance Pass: Double-click connect, atomic `ConnectionEditorMode` Edit sheet, Clone Connection with independent Keychain refs, `⌘A` Select All + batch Delete Selected, `applicationShouldTerminate` + bounded parallel NIO teardown, `TransferMonitor` 10Hz decoupling, cached `strings`/`activePalette`, 2s throttled SQLite journal ticks, and single-`lstat` enumeration (`T-032`)
- [x] Verify Universal 2 (`x86_64 arm64`) release `.app` bundle (with embedded `Sparkle.framework` & entitlements) + `SparkleSFTP-0.2.0-universal.dmg` + `.sha256` via `Tools/Release/build-universal.sh`, `create-dmg.sh`, and `.github/workflows/release.yml` (`T-024`)

## Post-MVP / External Infrastructure Gates (Not Executed in Offline Sandbox)

- [ ] Run live Docker multi-server interop smoke suite (`Tools/TestServers/run-integration-tests.sh` against SFTP/FTP/FTPS containers; requires Docker Engine)
- [ ] Run Apple Developer ID codesigning, notarization, stapling, and Sparkle Ed25519 appcast signing (`Tools/Release/notarize.sh`; ad-hoc signing & Universal 2 DMG already verified locally)
