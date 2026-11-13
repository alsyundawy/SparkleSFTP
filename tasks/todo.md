# Task Execution Checklist (`tasks/todo.md`)

Tracks active execution of [`tasks/plan.md`](plan.md) and [`docs/TASK_LIST.md`](../docs/TASK_LIST.md).

## Milestone 1: Foundation (`T-001` – `T-005`)

- [x] `T-001` Write `Package.swift` (`.macOS(.v13)`, Swift 6, verified dependency pins)
- [x] `T-002` Implement `src/Packages/Clibcurl` C helper wrapper
- [x] `T-003` Implement `src/Packages/Core` domain contracts & models
- [x] `T-004` Implement `src/Packages/DesignSystem` theme, components & EN/ID strings
- [x] `T-005` Add & pass `Tests/CoreTests`

## Milestone 2: Security & Persistence (`T-006` – `T-008`)

- [x] `T-006` Implement `src/Packages/Security`
- [x] `T-007` Implement `src/Packages/Persistence`
- [x] `T-008` Add & pass `Tests/SecurityTests` and `Tests/PersistenceTests`

## Milestone 3: Networking (`T-009` – `T-012`)

- [x] `T-009` Implement `SFTPPacketCodec` & `SSHClientService`
- [x] `T-010` Implement `SFTPService` & `SCPCompatibilityAdapter`
- [x] `T-011` Implement `FTPService`, `FTPListingParser`, `RemoteServiceFactory`
- [x] `T-012` Add & pass `Tests/NetworkingTests`

## Milestone 4: Transfer Engine, FileManager & Sync (`T-013` – `T-016`)

- [x] `T-013` Implement `src/Packages/TransferEngine`
- [x] `T-014` Implement `src/Packages/FileManager`
- [x] `T-015` Implement `src/Packages/Synchronization`
- [x] `T-016` Add & pass `TransferEngineTests`, `FileManagerTests`, `SynchronizationTests`

## Milestone 5: Terminal, Features & App (`T-017` – `T-020`)

- [x] `T-017` Implement `src/Packages/Terminal`
- [x] `T-018` Implement `src/Features/` (SwiftUI + AppKit `FilePaneTableView` + `QuickLookCoordinator`)
- [x] `T-019` Implement `src/App/` executable + entitlements + `Info.plist` + `SparkleUpdaterService`
- [x] `T-020` Add & pass `Tests/IntegrationTests`

## Milestone 6: Tooling, Docs Sync & Full Gate (`T-021` – `T-023`)

- [x] `T-021` Create `Tools/TestServers/` & `Tools/Release/` scripts
- [x] `T-022` Reconcile `README.md`, `README-id.md`, `docs/*.md`, `CHANGELOG.md`, `TODO.md`
- [x] `T-023` Run full build, tests (`95 tests in 25 suites`), SwiftLint (`160` files), SwiftFormat (`0/160`), Trunk, SonarQube config/reporter, YAMLlint, ShellCheck, Shfmt, Markdownlint, Clang/Cppcheck, Actionlint
- [x] `T-024` Build and verify Universal 2 (`x86_64 arm64`) `.app` + `SparkleSFTP-0.2.0-universal.dmg` + `.sha256` via `Tools/Release/build-universal.sh`, `create-dmg.sh`, and `.github/workflows/release.yml`

## Milestone 7: Post-MVP Quality-of-Life & Editor Enhancements (`T-025` – `T-036`)

- [x] `T-025` Multi-theme engine (`SparkleThemePalette`, `76` themes / `26` families inspired by SparkNotePad/NotepadNext, WCAG AA contrast on canvas & chrome, Search + tone filters, JSON import/export) + full workspace theme & `NSAppearance` propagation across `SparkleWindowConfigurator`, SwiftUI sheets/forms, AppKit tables, `TerminalView`, and `NSApp.windows`
- [x] `T-026` Maintainable JSON i18n system (`en.json` & `id.json` `361` keys, custom `Locales/` override directory, Preferences coverage inspector)
- [x] `T-027` Full Auto-Update Preferences & community GitHub Releases API fallback check (`AutoUpdateSettings`, `PreferencesUpdatesTab`)
- [x] `T-028` Enhanced FileZilla XML & Commander INI reader + `ImportConnectionsSheet` preview importer (BOM/UTF-16, nested folders, `FSProtocol`, `.ini` `UTType`)
- [x] `T-029` Minimalist Notepad2 Internal File Editor (`src/Features/Editor/`, multi-tab `NSTextView` + line numbers + regex syntax/find/transforms/encodings + remote upload)
- [x] `T-030` Bidirectional & Reverse Folder Synchronization (`TASK-108` across `SyncPlanner`, `SyncExecutor`, `SyncPreviewSheet`, `BidirectionalSyncTests`, `EditorAndSyncTests`)
- [x] `T-032` Connection List double-click connect, atomic Edit sheet (`ConnectionEditorMode`), Clone Connection with Keychain secret duplication, `⌘A` Select All + batch Delete Selected, fast `applicationShouldTerminate` exit, `TransferMonitor` 10Hz decoupling, cached `strings`/`activePalette`, 2s SQLite checkpoint throttling & single-`lstat` POSIX listing (`ConnectionManagementAndPerfTests`)
- [x] `T-033` SparkNotePad-style 7-tab About window (`AboutView` / `AboutWindowController`, incl. `Libraries`), 1:1 pastel-yellow/blue/white squircle `AppIcon`, Keychain Remember/Clear Password flow (`ConnectionEditorView`, `CredentialPromptSheet`, `FTPService`), AppKit `ConnectionListTableView` + `InteractiveFileTableView` cursor/keyboard focus navigation, and C11/`Clibcurl` `.clangd` + `.clang-format` IDE hygiene (`AboutAndThemePasswordTests`)
- [x] `T-034` Third-party library integration & tuning (`ClibcurlSystemLibs.c` `-lz` bounded `zlib`/`gzip`, `256 KB` `TCP_NODELAY`/`TCP_KEEPALIVE` + GCD off-cooperative `CurlClientHelper` workers, `total=0` resume guard, dynamic `dlopen` `libssh2` probe, `OpenSSL`/`OpenSSH` detection, v0.1 `terminal.fill` Shell icon, sanitized `ExternalTerminalLauncher` for iTerm2/Terminal), Multi-Thread Pipelined SFTP (`SFTPPipelinedTransfer` `64 KB` blocks, `min(32, max(2, pipelineDepth * 4))` window + `4` global / `3` per-host `TransferScheduler`), shared EWMA `TransferSpeedMeter`, POSIX permission & dotfile recursive transfer preservation + upload pause/resume (`resolveUploadResumeOffset`) + debounced pane refresh, FileZilla-style `ConflictResolutionSheet` + FIFO `pendingConflictQueue`, and card-grid + toolbar/menu language switcher (`ToolchainAndConflictTests`, `FolderPermissionsTransferTests`)
- [x] `T-035` Post-Completion Long-Term Review (post-`1b9d9f4`, 14 skills & 14 pillars): MacBook RAM check, full linter & CI sweep, web research, concurrency & SwiftUI/NSTableView perf audit, protocol/security CVE/CWE review, Terminal/TransferJournal/Docker/Release risk audit, and updated [`docs/LONG_TERM_REVIEW_2026_11.md`](../docs/LONG_TERM_REVIEW_2026_11.md) + `CHANGELOG.md`
- [x] `T-036` `src/` Layout Restructure (`src/App`, `src/Features`, `src/Packages`), Multi-Window Session Isolation (`AppEnvironment.makeWindowState`, `FocusedValues`, `Connect in New Window`), FileZilla XML & Commander INI Multi-Tab Workspaces (`WorkspaceTabBar`, `WorkspaceTabBarActionButton`, `QuickConnectBar` auto-hidden when active tab connected), Native Window Close/Minimize/Zoom Traffic Lights (`SparkleWindowConfigurator`), Scoped macOS Shortcuts (`⌘W`, `⌘⇧[`/`⌘⇧]`, `⌘\`, table-scoped `Tab`, single `⇧⌘N`, AppKit responder validation), Mouse Hover/Right-Click Selection Responsiveness (`NSTrackingArea` + `rightMouseDown`), Visible Connection Toolbar + Commander Host/File Context Menus & Sheets (`AppState+CommanderCommands`, `CommanderCustomCommandSheets`), and SonarQube config (`sonar-project.properties`) (`WindowTabsAndCommanderCommandsTests`, `WindowControlsAndShortcutsTests`)
- [x] `T-037` Post-Completion Long-Term Review Refresh (`5c2c212`): run full linter sweep, create [`docs/ADR/0008`](../docs/ADR/0008-multi-window-isolation-appkit-tab-chrome-76-themes-and-transfer-pipeline.md), fix `sonar-project.properties` (`sonar.externalIssuesReportPaths`, `0.2.0`), refresh [`docs/LONG_TERM_REVIEW_2026_11.md`](../docs/LONG_TERM_REVIEW_2026_11.md) across all 14 pillars/skills (incl. Sparkle Sandbox `-spks`/`-spki` & inside-out signing gaps), and sync `SECURITY.md`, `CONTRIBUTING.md`, `README*.md`, `DOCNOTE.md`, `TODO.md`, and `CHANGELOG.md`
- [x] `T-038` Commander `.ini` Simple Password Decryption & Neutral Filename Refactor (`ExternalSessionFileReader.swift`, `AppState+CommanderCommands.swift`, `CommanderCustomCommandSheets.swift`, `WindowTabsAndCommanderCommandsTests.swift`): decode `0xA3` simple obfuscation (`0xFF`/`0x00` standard UTF-8 + legacy formats) into `ImportedConnection.transientSecret` -> Keychain while failing closed on `[Configuration\Security] UseMasterPassword=1` or invalid framing (`ExternalImportersTests`)
- [x] `T-039` 1-Tab = 1-Shell Binding, Preferences Themes Card Grid, Persistent Window Traffic Lights, Scoped Shortcuts & Transfer Engine Hardening (`TerminalSessionManager`, `PreferencesThemeTab`, `SparkleWindowConfigurator`, `SparkleSFTPApp`, `InteractiveFileTableSupport`, `InteractiveConnectionTableSupport`, `TransferSpeedMeter`, `SFTPChannelBridge`, `TransferQueue*`, `AppState+NavigationAndShortcuts`, `RemoteFileModels`, `SFTPService`, `FTPListingParser`) — verified `91 tests in 24 suites` (`ShellTabsAndWindowControlsTests`, `LoopbackTransferResumeTests`, `FolderPermissionsTransferTests`, `TransferEngineResumeTests`) + `365` synchronized EN/ID keys + `0` violations across `157` Swift files
- [x] `T-040` `MainWindowView` Titlebar Z-Order/Safe-Area Fix, Standalone AppKit Preferences Window, Active Close/Minimize/Zoom Controls & Fixed Dialog Box Sizes (`SparkleWindowConfigurator`, `ManagedWindowController`, `PreferencesWindowController`, `AboutWindowController`, `EditorWindowController`, `SparkleSFTPApp`, `DualPaneCommanderView+Actions`, `MainWindowView`, `ConnectionViews`, `WorkspaceTabBar`, `PreferencesView`, `AboutView`, Modal Sheets) — keep `NSTitlebarContainerView` above `NSHostingView` with `ignoresSafeAreaEdges: []`, replace SwiftUI `Settings` with `PreferencesWindowController` (`760x600`, `sizingOptions = [.minSize]`, active Close/Minimize/Zoom, live locale title updates, single-window reuse), unify `AboutWindowController` (`720x560`) and `EditorWindowController` (`900x620`), and enforce fixed `width x height` dimensions across all modal sheet dialogs (`PreferencesAndDialogSizeTests`) — verified `95 tests in 25 suites` + `0` violations across `160` Swift files (`31,467` LOC)
- [x] `T-041` Full-Repository 14-Pillar Audit & Hardening Fix Pass — close verified CWE-416/88/22/409, cancellation deadlocks (`SFTPChannelBridge`, `SSHClientService.runExec`), sparse-hole resume corruption, Commander INI `FSProtocol` (`0=SCP, 1/2=SFTP`), `FileZilla` space/encoding bugs, `SyncPlanner`/`SyncExecutor` bugs, `Esc`-sheet continuations, UTF-16LE double-BOM, `conn.password` i18n parity (`366` EN/ID keys), `_config.yml` Jekyll exclusions, `.betterleaks.toml` `AND` allowlist, `codeql.yml` Swift + C/C++ matrix, and inside-out release signing + DMG checksum order across all `111 tests in 31 suites` & `169` Swift files + `2` C11 sources

## Milestone 8: Standalone iTerm-Style Terminal, Transfer Queue Overhaul, Keychain/Performance Fixes & IDE Zero-Diagnostic Sweep (`T-042` – `T-052`)

- [x] `T-042` Remove all remaining proprietary third-party brand strings, symbols, enum cases, localization keys, comments, test names, and documentation references (`IniSessionImporter`, `.commanderINI`, `"import.iniFormat"`) while preserving standard `[Sessions\...]` INI + `0xA3` import compatibility
- [x] `T-043` Fix IDE diagnostics & CodeQL Swift CI (`codeql.yml` untraced `swift package resolve` + `--skip-update --disable-sandbox`, `release.yml`, `.vscode/settings.json` C11 CppCheck/YAML settings, `ClibcurlSystemLibs.c` `ZLIB_CONST` + const-safe copy with zero `cstyleCast`/`dangerousTypeCast`)
- [x] `T-044` Eliminate unwanted macOS Keychain prompts on app launch, sidebar click, and connection edit (`FileHostTrustBackingStore` `0600` `trusted_hosts.v1.json`, `KeychainService.hasSecret` `LAContext.interactionNotAllowed`, `KeychainMemoryCache`, non-prompting list/editor selection)
- [x] `T-045` Fix Main-Thread UI freezes, unresponsive mouse clicks, and blocked right-click context menus during large/multi-file folder transfers (off-MainActor recursive folder walk, batched `TransferQueue.enqueueBatch`, coalesced snapshot stream emissions, throttled auto-refresh + `NSMenuDelegate` guards, windowed `TransferQueueView`, cached `SparkleWindowConfigurator`)
- [x] `T-046` Eliminate disruptive modal error alerts for failed or cancelled transfers (`CancellationError` silent suppression, non-blocking inline/drawer error tracking in `TransferQueueView` `Failed` tab instead of blocking `.alert` sheets)
- [x] `T-047` Implement independent Upload & Download 8-action "File Already Exists" conflict policies (`Ask`, `Overwrite`, `Overwrite if source newer`, `Overwrite if size differs`, `Overwrite if size differs or source newer`, `Resume`, `Rename`, `Skip`) in `TransferQueue`, `ConflictResolver`, `PreferencesView`, and `TransferQueueView` quick menu
- [x] `T-048` Add Transfer Queue filter tabs (`Active`, `Completed`, `Failed`, `All`), **Cancel / Abort All**, per-item & bulk **Resume / Retry Failed**, and **Clear Completed** / **Clear Failed** / **Clear Finished** controls
- [x] `T-049` Build Standalone iTerm2-style macOS Terminal (`StandaloneTerminalWindowController`, `StandaloneTerminalManager`, `LocalTerminalProcessRepresentable` over `SwiftTerm.LocalProcessTerminalView`, tabs, vertical/horizontal split panes, `⌘F` `SwiftTerm` scrollback find bar, local login shells + SSH connection tabs, font zoom, 76-theme ANSI palette sync, and Direct/Hardened-Runtime `SparkleSFTP.entitlements`)
- [x] `T-050` Add comprehensive TDD/regression tests covering neutral INI importer, zero-prompt Keychain/FileHostTrustStore, off-MainActor batch queue & `CancellationError` suppression, 8-action upload/download policies, queue tabs/CancelAll/Clear/Retry, and Standalone Terminal multi-tab/split-pane manager (`121 tests in 33 suites` passing)
- [x] `T-051` Execute full 14-pillar audit checklist across every file (`/*`, `/*/*`), pass ALL linters (`SwiftLint --strict`, `SwiftFormat`, `SonarQube JSON`, `Trunk`, `MarkdownLint`, `YAMLlint`, `Actionlint`, `ShellCheck`, `Shfmt`, `Clang -Werror`, `Cppcheck --check-level=exhaustive`, `lint-check.sh`), pass `swift test`, and build Universal 2 `SparkleSFTP.app` + `.dmg` + `.sha256` (`0.3.0`)
- [x] `T-052` Update EN/ID i18n, `README.md`, `README-id.md`, `docs/*.md`, `DOCNOTE.md`, `CHANGELOG.md`, `TODO.md`, commit & push, and verify all 4 GitHub Actions workflows (`CI`, `MegaLinter`, `CodeQL Advanced`, `Deploy Jekyll`) pass cleanly

## Milestone 9: Runaway CPU Elimination, FileZilla Activity Logger & Modern UX (`T-053` – `T-062`)

- [x] `T-053` Fix runaway 100% CPU infinite layout loop in `SparkleWindowConfigurator` via `NSWindow.didResizeNotification`
- [x] `T-054` Implement AppKit cell & row reuse (`makeView(withIdentifier:owner:)`) in `FilePaneTableView` for `ThemedFileRowView`
- [x] `T-055` Add 250ms debouncer to `LocalDirectoryWatcher` in `LocalFileService`
- [x] `T-056` Implement FileZilla-style real-time Activity Logging Console (`ActivityLogger`, `ActivityLogView`, `⌥⌘L`)
- [x] `T-057` Add `tabs.disconnect` and `tabs.connectOnNewTab` options to workspace tab context menus
- [x] `T-058` Disambiguate `F5` (Cross-Pane Transfer) vs `⇧F5` (Copy To...) vs `⌘C` (Clipboard Copy)
- [x] `T-059` Implement centered minimize/hide transfer drawer and expander bar
- [x] `T-060` Enrich localized tooltips with shortcut indicators across Quick Connect and Action bars
- [x] `T-061` Add native `NSAlert` modal feedback for manual "Check for Updates Now" requests
- [x] `T-062` Modernize application branding with user-specified 1:1 transparent squircle icon asset generation (`AppIcon.png`, `AppIcon.icns` with solid black background removed)

## Milestone 10: Cold-Launch Performance, Invalidation Decoupling, Transfer Throttling & Cross-Platform Resilience (`T-063` – `T-074`)

- [x] `T-063` Lazy-load theme catalogs: load only default light, default dark, and active user palette on startup (`SparkleThemeStore.loadBootstrapPalettes`), deferring 74 palettes & JSON scanning until `PreferencesThemeTab` opens
- [x] `T-064` Eliminate SwiftUI view invalidation thrashing: extract `MainWindowStatusBar` and `MainWindowMinimizedTransferBar` as isolated views, decouple root `MainWindowView` from transfer snapshots
- [x] `T-065` Transfer queue coalescing & throttling: implement 80ms throttle window (~12.5 Hz) in `TransferMonitor.updateSnapshots` and remove `snapshots.count <= 20` bypass in `TransferQueue.broadcastSnapshots`
- [x] `T-066` Maintain `visibleLimit = 150` in `TransferQueueView` to prevent table scrolling jitter
- [x] `T-067` Graceful Linux/BSD SETSTAT handling: catch `SSH_FXP_SETSTAT` `SSH_FX_PERMISSION_DENIED` on `mtime`/`chmod` mutations and log non-fatal warnings without aborting transfers
- [x] `T-068` Automatic macOS metadata filtering: skip `.DS_Store` and AppleDouble `._*` files during directory uploads and synchronization scans
- [x] `T-069` Resilient temporary upload naming: use `.destination.sparklesftp.<uuid>.filepart` with atomic rename upon full completion
- [x] `T-070` Cold-launch profiling signposts: add `OSSignposter` markers (`ThemeInitialization`, `InitialDirectoryListing`, `WindowConfiguration`) under `com.sparklesftp.app` / `LaunchPerformance`
- [x] `T-071` Guard update check modal alerts in headless test environments to prevent test runner hangs
- [x] `T-072` Run full test suite (`121 tests / 33 suites`, 100% green), static code review, and linter check
- [x] `T-073` Build Universal 2 release `.app` and DMG (`SparkleSFTP-0.4.0-universal.dmg` + `.sha256`)
- [x] `T-074` Update documentation (`CHANGELOG.md`, `DOCNOTE.md`, `README.md`, `README-id.md`, `TODO.md`, `docs/releases/v0.4.0.md`, `docs/*.md`)

## Milestone 11: Native macOS UI/UX Mockups ("Sparkle Commander" Visual Refresh v0.4.1) (`T-075` – `T-086`)

- [x] `T-075` Implement semantic surface tokens (`src/Packages/DesignSystem/SemanticSurfaceTokens.swift`) resolved dynamically from active `SparkleThemePalette` with WCAG 2.1 AA compliance
- [x] `T-076` Implement deterministic `Sendable` mock data models (`src/Features/Mockups/MockData.swift`) for sessions, dual-pane file trees, transfers, and terminals
- [x] `T-077` Implement shared mockup components (`src/Features/Mockups/Components/`): `StatusBadge`, `ModernProgressBar`, `PathBreadcrumbsBar`, `DiskSpaceBar`, `EmptyStateView`
- [x] `T-078` Implement Screen 1: `MainWorkspaceMockup.swift` (MainWindowView + WorkspaceTabBar + QuickConnectBar + Breadcrumbs) with Xcode Previews at 1280×800
- [x] `T-079` Implement Screen 2: `ConnectionManagerMockup.swift` (Saved session profiles, protocol badges: SFTP, SCP, FTP) with Xcode Previews at 1280×800
- [x] `T-080` Implement Screen 3: `TransferQueueMockup.swift` (Batch queue, speed indicators, conflict state badges) with Xcode Previews at 1280×800
- [x] `T-081` Implement Screen 4: `TerminalMockup.swift` (iTerm2-inspired split terminal view with status indicator) with Xcode Previews at 1280×800
- [x] `T-082` Implement Screen 5: `PreferencesThemesMockup.swift` (Theme family browser and contrast checker preview) with Xcode Previews at 1280×800
- [x] `T-083` Implement Screen 6 (`EmptyStateMockup.swift`), Screen 7 (`ConflictDialogMockup.swift`), and Screen 8 (`DashboardMockup.swift`) with Xcode Previews at 1280×800
- [x] `T-084` Implement Gallery Launcher (`src/Features/Mockups/MockupGalleryView.swift`) and hook into `SparkleSFTPApp.swift` via `--mockup-gallery` launch argument
- [x] `T-085` Add mock display strings with 100% parity across `en.json` and `id.json`, and run full linter sweeps (SwiftLint, SwiftFormat, Trunk, ShellCheck, Markdownlint, YAMLlint)
- [x] `T-086` Execute 14-Pillar code audit, build universal binary `.app` and DMG (`SparkleSFTP-0.4.1-universal.dmg` + `.sha256`), update `README.md`, `README-id.md`, `CHANGELOG.md`, `DOCNOTE.md`, `TODO.md`, and docs

## External Operational & Release Gates (Deferred to Release Environment)

- [ ] Execute live Docker integration test suite (`Tools/TestServers/run-integration-tests.sh`; Docker not installed locally)
- [ ] Execute Apple Developer ID notarization & stapling (`Tools/Release/notarize.sh`) with production signing credentials
