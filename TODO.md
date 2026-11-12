# SparkleSFTP — Master TODO (Full MVP)

Live checklist tracking the Full MVP implementation of **SparkleSFTP** (`Swift 6`, `SwiftUI + AppKit`, `macOS 13+`, `Open-Source MIT`).
Detailed task breakdown and acceptance specs live in [`docs/TASK_LIST.md`](docs/TASK_LIST.md), [`tasks/plan.md`](tasks/plan.md), and [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md).

## Phase A: Architecture, Docs & Manifest (`WG-1`)

- [x] Verify `docs/*.md` lineage (`MacSFTP` -> `SparkleSFTP`)
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
- [x] Implement SparkNotePad/NotepadNext multi-themes (`76` palettes / `26` families + custom JSON store + full workspace theme & `NSAppearance` propagation via `SparkleWindowConfigurator`), SparkNotePad-style 7-tab About window (`AboutView` / `AboutWindowController`, incl. `Libraries`) with full Close/Minimize/Zoom window controls & 1:1 blue/white/pastel-yellow `AppIcon`, Auto-Update settings & fallback check, JSON i18n catalog & maintenance UI (`361` keys), FileZilla XML & Commander INI BOM-safe preview importer, Notepad2 multi-tab internal editor (`src/Features/Editor/`), and Bidirectional Sync (`TASK-108`) (`T-025`)
- [x] Verify 0 errors across `swift build -j 2`, `swift test --no-parallel` (`95 tests in 25 suites`), `swiftlint lint --strict` (`160` files), `swiftformat --lint .` (`0/160`), `trunk check`, `sonar-scanner`/SonarQube JSON reporter, `yamllint -c .yamllint.yml .`, `shellcheck -s bash`, `shfmt -d -i 2 -ci`, `markdownlint-cli2`, `clang-format --dry-run --Werror`, `cppcheck`, `clang -fsyntax-only`, and `actionlint` (`T-023`)
- [x] Connection UX, Keychain Remember Password, Cursor/Keyboard Fix, Fast Quit & Performance Pass: Native AppKit `ConnectionListTableView` + `InteractiveFileTableView` click/keyboard focus navigation (`⌘W`, `⌘⇧[`/`⌘⇧]`, `⌘\`, scoped `Tab` pane switching, single `⇧⌘N`, AppKit responder validation), Remember/Clear Keychain password flow (`ConnectionEditorView`, `CredentialPromptSheet`, `FTPService`), double-click connect, atomic `ConnectionEditorMode` Edit sheet, Clone Connection with independent Keychain refs, `⌘A` Select All + batch Delete Selected, `applicationShouldTerminate` + bounded parallel NIO teardown, `TransferMonitor` 10Hz decoupling, cached `strings`/`activePalette`, 2s throttled SQLite journal ticks, and single-`lstat` enumeration (`T-032`)
- [x] Third-Party Toolchain Support, Multi-Thread Transfers, FileZilla Conflict Dialog & Language Switcher Layout (`T-034`): `Clibcurl` `-lz` bounded `zlib`/`gzip` (`ZlibCompressionCodec`), optimized `CurlClientHelper` (`256 KB` buffers, `TCP_NODELAY`/`TCP_KEEPALIVE`, GCD worker dispatch, `total=0` resume guard), dynamic `dlopen` `libssh2` / `OpenSSL` / `OpenSSH` probing (`ToolchainInspector`), v0.1 `terminal.fill` Shell icon + sanitized `ExternalTerminalLauncher` (`iTerm2`/`Terminal.app`/`ssh://`), actor-free `SFTPPipelinedTransfer` (`64 KB` blocks, `min(32, max(2, pipelineDepth * 4))` window), stall-decaying `TransferSpeedMeter`, bottom-up POSIX permission & dotfile preservation + upload resume (`resolveUploadResumeOffset`) + debounced pane refresh, `TransferScheduler` (`4` global / `3` per-host), FileZilla `ConflictResolutionSheet` + FIFO `pendingConflictQueue`, and card-grid + toolbar/menu language switcher (`PreferencesLocalizationTab`, `MainWindowView`, `SparkleSFTPApp`)
- [x] `src/` Restructure, Multi-Window Isolation, FileZilla XML & Commander INI Multi-Tab Connections, Responsive Hover/Right-Click/Select-All & Commander Menus (`T-036`): Reorganize `src/{App,Features,Packages}`; per-window `AppEnvironment.makeWindowState()` + `FocusedValues` (`New Window` opens clean sessionless window); `WorkspaceTabBar` (AppKit `TabBarActionButton` + `WorkspaceTabStripRepresentable`, instant switch/close, `New Tab` / `Duplicate Tab` / `Reconnect` / `Open in New Window` / `Close Tab` / `Close Other Tabs`) & `QuickConnectBar` (auto-hidden when active tab connected); `NSTrackingArea` row hover + `rightMouseDown` click-select + visible Connection toolbar (`Connect`/`New`/`Edit`/`All`/`Delete`); Commander Commander `Edit`/`Copy... F5`/`Move... F6`/`File Custom Commands`/`File Names` context submenus (`AppState+CommanderCommands`, `CommanderCustomCommandSheets`); `sonar-project.properties` (`WindowTabsAndCommanderCommandsTests`, `WindowControlsAndShortcutsTests`, `FolderPermissionsTransferTests`)
- [x] Post-Completion Long-Term Review Refresh & Documentation Sync (`T-037`): Conduct full 14-pillar / 14-skill review on live tree (`157` Swift files / `31,031` LOC, `91 tests in 24 suites`), add [ADR-008](docs/ADR/0008-multi-window-isolation-appkit-tab-chrome-76-themes-and-transfer-pipeline.md), fix `sonar-project.properties` (`sonar.externalIssuesReportPaths`, `0.2.0`) while documenting unconfigured CI SonarQube server gap, align [`SECURITY.md`](SECURITY.md) / [`CONTRIBUTING.md`](CONTRIBUTING.md) / [`README.md`](README.md) / [`README-id.md`](README-id.md) / [`docs/LONG_TERM_REVIEW_2026_11.md`](docs/LONG_TERM_REVIEW_2026_11.md) / [`CHANGELOG.md`](CHANGELOG.md)
- [x] Commander `.ini` Simple Password Decryption & Neutral Filename Refactor (`T-038`): Decode `0xA3` simple obfuscated `Password=` entries (`0xFF`/`0x00` standard UTF-8 & legacy formats) into `ImportedConnection.transientSecret` -> Apple Keychain inside `ExternalSessionFileReader.swift` while failing closed on `[Configuration\Security] UseMasterPassword=1` or malformed payloads, and rename all four `*commander*` source/test files (`ExternalImportersTests`)
- [x] 1-Tab = 1-Shell Binding, Preferences Themes Card Grid, Persistent Window Traffic Lights, Scoped Shortcuts & Transfer Engine Hardening (`T-039`): Bind each `WorkspaceTab` 1-to-1 with a single remote `TerminalTabSession` (`v0.1` `terminal.fill`, no multi-tab/split terminal or Local Shell); restrict `QuickConnectBar` + toolbar `Connect` strictly to unconnected tabs (`macwindow` chip); redesign `PreferencesThemeTab` with Live Preview + `LazyVGrid` cards (`365` EN/ID keys); keep Close/Minimize/Zoom active across Main/Preferences/About/Editor windows (`WindowObserverBox`); scope `InteractiveFileTableView`/`InteractiveConnectionTableView` modifiers (`F7`, `⌘⇧C`, `⌘⌥C`, `⌘↩`, `⌥↩`, `⌘⇧S` menu Sync, `NSText` exclusion, `hostWindow` `⌘W`); fix `TransferSpeedMeter` stall decay, ordered SFTP packet pipelining (`submitPacket`/`awaitPacket`), `TransferQueue` actor reentrancy (`ProgressSequenceBox` + post-await check + pause byte reconciliation), `100%` partial upload resume, Conflict `.skip` zero-byte cleanup, 0-byte `1.0` completion progress, and bottom-up `PendingFolderPermissionJob` restoration + `0o755` dir defaults (`ShellTabsAndWindowControlsTests`, `LoopbackTransferResumeTests`)
- [x] Standalone AppKit Preferences Window, Titlebar Z-Order, Active Close/Minimize/Zoom Controls & Fixed Dialog Box Sizes (`T-040`): Fix `MainWindowView` titlebar/toolbar occlusion (`SparkleWindowConfigurator.isTitlebarCoveredByContent` `positioned: .above` + `ignoresSafeAreaEdges: []`), replace SwiftUI `Settings` with `PreferencesWindowController` via shared `ManagedWindowController` (`sizingOptions = [.minSize]`, `760x600`, `CommandGroup(replacing: .appSettings)` `⌘,`, live locale title updates) + unify `AboutWindowController` (`720x560`) and `EditorWindowController` (`900x620`), and lock explicit fixed `width x height` geometry across all modal dialog sheets (`PreferencesAndDialogSizeTests`)
- [x] Full-Repository 14-Pillar Audit & Hardening Pass (`T-041`): Fix `FTPService` UAF lifetime (`withExtendedLifetime`), `SFTPChannelBridge` & `SSHClientService.runExec` cancellation deadlocks, `SFTPService` symlink `.stat` + awaited close + `0x80000000` extended attrs, `TransferQueue` sparse-hole download resume + hole-free pipelined upload resume, `ExternalTerminalLauncher` / `tar` `--` CWE-88 guards, `PathValidator` / `LocalFileService` / `LocalizationCatalog` / `SyncExecutor` CWE-22 guards, `SyncPlanner` `remoteToLocal` mtime, Commander INI `FSProtocol` (`0=SCP, 1/2=SFTP`) & FileZilla spaces/encoding parsing, `ClibcurlSystemLibs.c` C11 `deflateBound`/`max_output_bytes` boundary, `AppState` `Esc`-sheet `onDismiss` + post-`await` session lookups, `EditorModels` UTF-16LE BOM + EOF ruler bounds, `366` EN/ID keys (`conn.password`), Jekyll `_config.yml`, `.betterleaks.toml` `AND` allowlist, `codeql.yml` Swift+C/C++, inside-out release signing & codesign-before-sha256 (`111 tests in 31 suites`)
- [x] Verify Universal 2 (`x86_64 arm64`) release `.app` bundle (with embedded `Sparkle.framework` & entitlements) + `SparkleSFTP-0.2.0-universal.dmg` + `.sha256` via `Tools/Release/build-universal.sh`, `create-dmg.sh`, and `.github/workflows/release.yml` (`T-024`)

## Phase G: Standalone Terminal, Zero-Prompt Keychain, Batch Queue & 8-Policy Conflict Engine (`v0.3.0`, `T-042` – `T-052`)

- [x] Remove all proprietary trademark identifiers (`IniSessionImporter`, `.commanderINI`, `"import.iniFormat"`, EN/ID docs) while keeping `[Sessions\...]` `.ini` + `0xA3` decoder (`T-042`)
- [x] Fix CodeQL Swift resolve, `release.yml` Checkov `CKV_GHA_7`, `.vscode/settings.json`, and `ClibcurlSystemLibs.c` C11 warnings (`T-043`)
- [x] Eliminate launch/click/edit Keychain prompts via `FileHostTrustBackingStore` (`0600` JSON + silent `LAContext` migration) and `KeychainMemoryCache` (`T-044`)
- [x] Offload recursive folder scans off `MainActor`, batch `enqueueBatch`/`TransferJournal+Batch`, coalesce snapshots, cache window chrome, and add `NSMenuDelegate` context menu reload guards (`T-045`)
- [x] Suppress `CancellationError` modal alerts via `reportNonCancellationError` and move transfer error surfacing inline to the queue drawer (`T-046`)
- [x] Support independent Upload & Download 8-action "File Already Exists" policies across `ConflictResolver`, `TransferQueue`, `PreferencesView`, and `TransferQueueView` (`T-047`)
- [x] Add Transfer Queue tabs (`Active`, `Completed`, `Failed`, `All`), **Abort All**, **Retry Failed**, and **Clear Completed/Failed/Finished** (`T-048`)
- [x] Build Standalone iTerm2-style macOS Terminal (`StandaloneTerminalWindowController`, `StandaloneTerminalManager`, `LocalProcessTerminalView`, multi-tab, `⌘D`/`⌘⇧D` splits, `⌘F` search, zoom, `0.3.0` Hardened Runtime entitlements) (`T-049`)
- [x] Add regression tests covering FileHostTrustStore, Keychain `hasSecret`, 8-policy Upload/Download resolver, queue batch lifecycle, `CancellationError` suppression, `NSMenuDelegate` guards, and Standalone Terminal (`T-050`)
- [x] Run full 14-pillar audit, all linters (`0` violations), full `121 tests / 33 suites`, Universal 2 `0.3.0` `.app`/`.dmg` build, docs/CI verification & push (`T-051`, `T-052`)

## Phase H: Runaway CPU Elimination, FileZilla Activity Logger, Tab Disconnect & Icon Modernization (`v0.3.0`, `T-053`)

- [x] Fix 100% CPU infinite layout loop in `SparkleWindowConfigurator` via `NSWindow.didResizeNotification`
- [x] Implement `ThemedFileRowView` AppKit row reuse in `FilePaneTableView` eliminating unbounded allocations
- [x] Add 250ms debouncer to `LocalDirectoryWatcher` in `LocalFileService`
- [x] Integrate FileZilla-style real-time Activity Logging Console (`ActivityLogger`, `ActivityLogView`, `⌥⌘L`)
- [x] Add `tabs.disconnect` and `tabs.connectOnNewTab` options to workspace tab context menus
- [x] Disambiguate `F5` (Cross-Pane Transfer) vs `⇧F5` (Copy To...) vs `⌘C` (Clipboard Copy)
- [x] Implement centered minimize/hide transfer drawer and expander bar
- [x] Add localized tooltips with shortcut indicators across Quick Connect and Action bars
- [x] Add native `NSAlert` modal feedback for manual "Check for Updates Now" requests
- [x] Modernize application branding with user-specified 1:1 transparent squircle icon asset generation (`AppIcon.png`, `AppIcon.icns` with solid black background removed)

## Phase I: Cold-Launch Performance, Invalidation Decoupling, Transfer Throttling & Cross-Platform Resilience (`v0.4.0`, `T-054` – `T-065`)

- [x] Lazy-load theme catalogs: load only default light, default dark, and active user palette on startup (`SparkleThemeStore.loadBootstrapPalettes`), deferring 74 palettes & JSON scanning until `PreferencesThemeTab` opens (`T-054`)
- [x] Eliminate SwiftUI view invalidation thrashing: extract `MainWindowStatusBar` and `MainWindowMinimizedTransferBar` as isolated views, decouple root `MainWindowView` from transfer snapshots (`T-055`)
- [x] Transfer queue coalescing & throttling: implement 80ms throttle window (~12.5 Hz) in `TransferMonitor.updateSnapshots` and remove `snapshots.count <= 20` bypass in `TransferQueue.broadcastSnapshots` (`T-056`)
- [x] Maintain `visibleLimit = 150` in `TransferQueueView` to prevent table scrolling jitter (`T-057`)
- [x] Graceful Linux/BSD SETSTAT handling: catch `SSH_FXP_SETSTAT` `SSH_FX_PERMISSION_DENIED` on `mtime`/`chmod` mutations and log non-fatal warnings without aborting transfers (`T-058`)
- [x] Automatic macOS metadata filtering: skip `.DS_Store` and AppleDouble `._*` files during directory uploads and synchronization scans (`T-059`)
- [x] Resilient temporary upload naming: use `.destination.sparklesftp.<uuid>.filepart` with atomic rename upon full completion (`T-060`)
- [x] Cold-launch profiling signposts: add `OSSignposter` markers (`ThemeInitialization`, `InitialDirectoryListing`, `WindowConfiguration`) under `com.sparklesftp.app` / `LaunchPerformance` (`T-061`)
- [x] Guard update check modal alerts in headless test environments to prevent test runner hangs (`T-062`)
- [x] Run full test suite (`121 tests / 33 suites`, 100% green), static code review, and linter check (`T-063`)
- [x] Build Universal 2 release `.app` and DMG (`SparkleSFTP-0.4.0-universal.dmg` + `.sha256`) (`T-064`)
- [x] Update documentation (`CHANGELOG.md`, `DOCNOTE.md`, `README.md`, `README-id.md`, `TODO.md`, `docs/releases/v0.4.0.md`, `docs/*.md`) (`T-065`)

## Post-MVP / External Infrastructure Gates (Not Executed in Offline Sandbox)

- [ ] Run live Docker multi-server interop smoke suite (`Tools/TestServers/run-integration-tests.sh` against SFTP/FTP/FTPS containers; requires Docker Engine)
- [ ] Run Apple Developer ID codesigning, notarization, stapling, and Sparkle Ed25519 appcast signing (`Tools/Release/notarize.sh`; ad-hoc signing & Universal 2 DMG already verified locally)
