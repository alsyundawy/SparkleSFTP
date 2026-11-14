# Changelog

All notable changes to **SparkleSFTP** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

## [0.6.0] - 2026-11-14

### Added & Enhanced (Portability & Trust Release)

- **Native Configuration Bundles & Cryptographic Vault (F-01, `SparklePersistence`)**:
  - Introduced `.sparkleconfig` (portable JSON) and `.sparklevault` (AES-256-GCM authenticated binary archive).
  - Hardened key derivation via PBKDF2-HMAC-SHA256 with 600,000 iterations and in-place cryptographic memory zeroization.
  - Implemented 46-byte binary header (`SPKVAULT1`) with Additional Authenticated Data (AAD) binding.
  - Multi-source migration engine importing FileZilla `sitemanager.xml`, WinSCP `WinSCP.ini`, OpenSSH `~/.ssh/config`, and legacy exports with 4 conflict policies (`.skipExisting`, `.overwrite`, `.keepBoth`, `.mergeGroups`).
  - Added `PasswordStrengthMeter` with color-coded entropy validation and `ImportBundlePreviewSheet` diff inspection.
- **Complete 10-Tab Settings Registry & Universal Search (F-02, `SparkleCore`, `SparkleFeatures`)**:
  - Implemented centralized `SettingsRegistry` cataloging preferences across all 10 tabs with type-safe descriptors.
  - Added live search query filtering across setting labels and descriptions with match counters.
  - Implemented per-tab and universal factory defaults reset, plus JSON settings dictionary import/export.
  - Fully implemented all 10 tabs: General, Connections, Transfers, Sync & Bookmarks, Terminal, Editor, Security, Network, Archives, and Themes.
- **High-Performance Directory Comparison (F-03, `SparkleFileManager`)**:
  - Linear $O(N + M)$ dual-map comparison classifying items into 6 states: identical, only in local, only in remote, different size, local newer, and remote newer.
  - High-volume benchmark verified: 10,000 files compared in under 150ms.
- **External Editor Watcher & Sync-Back (F-04, `SparkleFeatures`)**:
  - Sandboxed cache staging inside `~/Library/Caches/SparkleSFTP/remote-edit/` with POSIX permissions `0700`.
  - Darwin `DispatchSourceFileSystemObject` file watcher with `O_NOFOLLOW` symlink defense and 500ms write debounce.
- **Transfer Bandwidth Limiter & Adaptive Pipeline Depth (F-05, `SparkleTransferEngine`)**:
  - Token-bucket transfer rate limiter enforcing upload and download throughput limits with zero UI jitter.
  - Dynamic `AutoPipelineController` probing network latency and adjusting pipeline concurrency between 1 and 16 windows.
  - Exponential backoff with jitter retry coordinator rejecting non-retryable security and authentication errors.
- **Real-Time Folder Watch & Sync Coordinator (F-06, `SparkleSynchronization`)**:
  - Actor-isolated folder modification coordinator with 1.5s debounce, pause/resume, and glob exclusion filtering.
- **Batch Rename Engine & UI Dialog (F-07, `SparkleFileManager`, `SparkleFeatures`)**:
  - Pure rule planner supporting find/replace, regular expressions, case formatting, and counter token `[C]`.
  - Comprehensive safety validations detecting path traversal (`..`), empty names, and duplicate collisions.
- **Multi-Hash Checksum Computation & Verification (F-08, `SparkleFileManager`, `SparkleFeatures`)**:
  - Streaming SHA-256, SHA-512, SHA-1, and MD5 hashing without loading entire files into memory.
  - Checksum dialog with paste-and-verify badge and automated remote CLI digest extraction.
- **Safe Archive Toolkit (F-09, `SparkleFileManager`, `SparkleFeatures`)**:
  - Safe ZIP, TAR, and GZ compression and extraction via system `/usr/bin/tar` and optional `7zz`.
  - Zip-Slip path traversal defense rejecting entries with `..` or leading slashes, capped at 50,000 entries.
- **FTPS Protocol Hardening (F-10, `SparkleNetworking`)**:
  - Enforced `CURLOPT_FTP_SKIP_PASV_IP = 0` to prevent malicious third-party IP hijacking in passive mode.
  - Enforced `CURLUSESSL_ALL` (PROT P) for complete control and data channel TLS encryption.
- **Productivity & System Integrations (F-11 through F-15)**:
  - SSH Agent authentication helper verifying `SSH_AUTH_SOCK` Unix domain sockets.
  - Rsync integration service probing GNU rsync vs OpenRsync with `--` argument injection defense.
  - Non-intrusive workspace tab session restorer.
  - Spotlight-style ⌘⇧P Command Palette searching navigation, connections, bookmarks, and actions.
- **Localization & Documentation**:
  - 100% key parity across English (`en.json`) and Indonesian (`id.json`) spanning 691 keys.
  - Added `ADR-0009` (Config Bundles & Crypto) and `ADR-0010` (External Toolchains & Security).
  - Authored comprehensive 14-Pillar Codebase Review report (`docs/reviews/0.6.0-14-pillar-review.md`).

## [0.5.0] - 2026-11-14

### Added & Enhanced (WinSCP Productivity Features & Terminal Integration Release)

- **High-Contrast File/Folder Selection & Full Selection Controls (`DualPaneCommanderView`, `InteractiveFileTableSupport`)**:
  - Implemented high-contrast `ThemedFileRowView` selection styling with a vibrant 3.5px left indicator bar, rounded selection highlight, and focus-aware tinting (emphasized active vs muted inactive pane).
  - Added dedicated **Select All** (`conn.selectAllShort` / "Semua") and **Deselect All** (`conn.deselectAllShort` / "Batal") toolbar buttons to both local and remote action bars.
  - Added **Deselect All** (`conn.deselectAll`) menu item to the commander right-click context menu.
  - Implemented instant deselect keyboard shortcuts: `Esc` (keyCode 53), `⇧⌘A`, and `⌘D`.
  - Added click-to-deselect when clicking on the empty canvas area below files in both commander and connection tables.
  - Fixed selection persistence across directories by clearing selected IDs upon navigating to a new directory in `refreshLocalDirectory` and `refreshRemoteDirectory`.
- **Force Update Detection by Commit & Release (`SparkleUpdaterService`, `UpdateConfigurationValidator`)**:
  - Enhanced `SparkleUpdaterService` to check Git commit hash (`target_commitish`) and release publication timestamp, allowing force-updating even when version tag and asset names remain identical.
  - Extended `UpdateConfigurationValidator` with `isSameVersion` and `isNewerBuildOrCommit` heuristics.
  - Updated `build-universal.sh` to inject exact Git commit SHA, commit count build number, and build timestamp directly into `SparkleSFTP.app/Contents/Info.plist`.
- **Bookmarks & Path History Manager (`src/Features/Bookmarks/`)**:
  - Implemented `BookmarkItem` and `PathHistoryItem` models supporting Sendable and Codable isolation with icon indicators, host scoping, and custom naming.
  - Implemented `BookmarkManager` handling UserDefaults persistence and 20-item ring buffer history per scope (`local` / `remote`).
  - Added `BookmarkQuickJumpMenu` integrated into both local and remote pane toolbars with quick jump, parent directory, and bookmark management triggers.
  - Added `BookmarkManagementSheet` providing complete CRUD operations (add, edit, delete, reorder) for bookmarks.
  - Implemented Synchronized Browsing toggle (`isSynchronizedBrowsingEnabled`) that automatically navigates the opposite pane if a matching relative subpath exists.
- **Directory Tree Navigation Sidebar (`src/Features/DirectoryTree/`)**:
  - Implemented hierarchical `DirectoryTreeNode` supporting lazy evaluation of children on node expansion and cycle-safe symlink resolution.
  - Implemented collapsible `DirectoryTreeView` with search filtering, manual refresh, and bidirectional selection synchronization with commander panes.
  - Added dedicated toggle button (`sidebar.left`) and HSplitView integration to `DualPaneCommanderView` for both local and remote panes.
- **Quick Remote Commands Runner (`src/Features/RemoteCommands/`)**:
  - Implemented `RemoteCommandModels` with built-in presets for Linux (`systemctl status !`, `df -h`, `journalctl -u ! -n 50`), BSD (`service ! status`, `top -s 1`), and macOS (`launchctl list`, `du -sh *`).
  - Implemented `RemoteCommandSanitizer` supporting WinSCP-style substitutions (`!` for current file, `!/` for remote path, `!?prompt:default?!` for interactive prompts) and rigorous metacharacter filtering to prevent shell injection (CWE-78).
  - Added `RemoteCommandBar` docked at the bottom of the active remote pane delivering sanitized commands directly to active SwiftTerm SSH channels.
- **OSC 7 Directory Synchronization (`TerminalSessionManager`, `DualPaneCommanderView`)**:
  - Implemented OSC 7 escape sequence detection (`\033]7;file://...`) emitted by active terminal shells (bash, zsh, fish) in SwiftTerm.
  - Synchronizes remote commander pane path in real time when navigating directories via shell `cd`.
- **FileZilla-Style Transfer Queue Redesign (`TransferQueueView`, `TransferQueueRowView`, `TransferQueueView+Subviews`)**:
  - Re-architected bottom transfer queue drawer to replicate FileZilla's multi-tab tabular layout:
    - 3 bottom tabs: `[ Queued files ]`, `[ Failed transfers ]`, and `[ Successful transfers ]` with live item counts.
    - Dynamic column headers per active tab:
      - Queued: `Server/Local file` | `Direction` | `Remote file` | `Size` | `Priority` | `Status`.
      - Failed: `Server/Local file` | `Direction` | `Remote file` | `Size` | `Priority` | `Time` | `Reason`.
      - Successful: `Server/Local file` | `Direction` | `Remote file` | `Size` | `Priority`.
    - Retained top action bar (Pause All, Abort All, Resume All, Retry All Failed, Clear Finished, conflict policy selector) and `chevron.down` minimize toggle paired with `chevron.up` restore indicator.
- **Activity Log Workspace Location Revert (`MainWindowView`, `MainWindowView+Subviews`, `ActivityLogView`)**:
  - Reverted `ActivityLogView` from the left sidebar back to its original horizontal position above `DualPaneCommanderView` in the main workspace `VSplitView` (from v0.4.1), eliminating sidebar cramping while preserving full horizontal width.
  - Symmetrical minimize/restore indicators: `chevron.up` to collapse activity log, `chevron.down` restore button on `MainWindowMinimizedActivityLogBar`.
- **FileZilla XML Import & Password Decryption (`ExternalImporters`, `ExternalSessionFileReader`)**:
  - Implemented base64 password decoding from both `<Pass>` and `<Password>` tags (case-insensitive, whitespace/newline-tolerant).
  - Added automatic file detection for `.config/filezilla/filezilla.xml`, `.filezilla/filezilla.xml`, `Library/Preferences/FileZilla/filezilla.xml`, and `recentservers.xml`.
- **Tokyo Night Storm Default Theme & SparkNotePad Naming (`ThemeCatalog`, `ThemeCatalogCore`, `AppState`)**:
  - Anchored default dark theme across bootstrap and catalog to Tokyo Night Storm (`tokyoNightStorm`).
  - Standardized all references from legacy `NotepadNext` to `SparkNotePad` across the entire codebase and theme catalog.
- **Internal Terminal Integration (`ExternalTerminalApp`, `AppState+Operations`, `InternalEditorToolbar`)**:
  - Added `case internalTerminal = "internal"` ("SparkleSFTP Internal Terminal (iTerm2-Style)") to `ExternalTerminalApp`.
  - Added dedicated Internal Terminal launcher button (`⌘⌥T`) in SparkNotePad toolbar for seamless access to the built-in iTerm2-style terminal.
- **Expanded About / Credits & Toolchain Libraries (`AboutView+Tabs`, `ZlibAndLibraryProbes`)**:
  - Expanded About/Credits to accurately acknowledge Google Antigravity IDE, Google Gemini 3.8 Flash AI model, SparkNotePad, SubnetCalc, SwiftTerm (1.20.0), Sparkle (2.10.1), SQLite3 WAL, and Apple Security & CryptoKit.
  - Updated toolchain libraries inspector to report linked statuses for SwiftTerm, Sparkle, SQLite3 WAL, and Apple Security & CryptoKit.
- **Native Connection Export & Import Engine (`InternalConnectionExporter`, `ExportConnectionsSheet`, `ImportConnectionsSheet`)**:
  - Implemented comprehensive connection configuration export & import supporting `.sparklesftp` and `.json` formats.
  - Three robust security tiers:
    - `sanitizedWithoutSecrets`: Clears all sensitive credentials, passwords, and private key references for safe team sharing.
    - `passwordProtected`: Encrypts complete configuration archives using AES-256-GCM + PBKDF2-HMAC-SHA256 (100,000 iterations, 16-byte random salt, 12-byte random nonce).
    - `plaintextSecrets`: Unencrypted local JSON backup with explicit security warning.
  - Added interactive `ExportConnectionsSheet` with export scope (All vs Selected) and security mode selector.
  - Enhanced `ImportConnectionsSheet` with password-protected archive unlock UI, `.sparklesftp` file type support, and format badges.
  - Integrated `File -> Export Connections...` (`⌘⇧E`) and `File -> Import Connections...` (`⌘⇧I`) menu shortcuts and connection list action buttons.
- **Comprehensive Localization & Quality Gates**:
  - Added 27 new localization keys across `en.json` and `id.json` achieving 100% key parity across 555 strings.
  - Expanded unit test suite to 134 tests across 36 test suites passing with 100% green status; verified 0 SwiftLint violations and 0 SwiftFormat warnings across 225 Swift files.
  - Built Universal 2 signed release bundle and packaged `SparkleSFTP-0.5.0-universal.dmg` (SHA-256: `7222917a08fb271822a92074cc43ffccd56ac95a35e18104931fca2f866b58bf`).

## [0.4.1] - 2026-11-13

### Added & Enhanced ("Sparkle Commander" Visual Refresh & Showcase Gallery)

- **Restoration of Eager Loading for All 76 SparkNotePad Palettes (`AppState+NavigationAndShortcuts`, `PreferencesThemesShowcase`, `ShowcaseGalleryView`)**:
  - Restored full eager loading of all 76 built-in themes at cold startup via `SparkleThemeStore.loadAllPalettes()`, ensuring all themes across Core, Extended, Spectrum, and Studio collections are immediately available without delay.
  - Removed `.prefix(18)` limitation in `PreferencesThemesShowcase.swift` so the complete catalog of 76 themes is viewable in the showcase grid.
  - Updated `ShowcaseGalleryView.swift` to list all 76 palettes in its dynamic live preview palette switcher.
- **Symmetrical Minimize & Restore Indicators for Log Box & Transfer Box (`MainWindowView`, `MainWindowView+Subviews`, `ActivityLogView`, `TransferQueueView`)**:
  - Implemented `MainWindowMinimizedActivityLogBar` in `MainWindowView+Subviews.swift` with a centered `[ ⌄ Show Activity Log ]` restore button featuring a `chevron.down` arrow indicator when the log dock is collapsed.
  - Aligned the minimize toggle button in `ActivityLogView.swift` to use a `chevron.up` arrow indicator.
  - Paired symmetrically with the Transfer Queue drawer's `chevron.down` minimize button in `TransferQueueView.swift` and `chevron.up` restore bar (`MainWindowMinimizedTransferBar`) in `MainWindowView+Subviews.swift`.
- **Marketing & Desktop Suite Flyer Banner (`assets/sparklesftp-desktop-banner.jpg`)**:
  - Added a high-resolution marketing and desktop suite banner (1376x768 pixels, sRGB JPEG) in `assets/sparklesftp-desktop-banner.jpg`, matching the layout, typography, and cyber-tech visual style of `SparkNotePad/assets/sparknotepad-desktop-banner.jpg`.
- **User-Friendly Documentation Overhaul (`README.md`, `README-id.md`)**:
  - Completely redesigned `README.md` and `README-id.md` modeled directly after SparkNotePad's clean, user-friendly documentation with quick navigation badges, visual feature table, keyboard shortcut guide, and accessible installation instructions for average users.
- **Semantic Surface Tokens (`SemanticSurfaceTokens.swift`)**:
  - Implemented dynamic semantic tokens resolving surface backgrounds, card elevations, hairline borders (1 px @ 6–8% opacity), text hierarchies, and row selection states directly from the active `SparkleThemePalette`.
  - Guaranteed zero hardcoded hex colors and verified full WCAG 2.1 AA contrast compliance across both dark and light palette modes.
- **Deterministic Showcase Datasets (`ShowcaseData.swift`, `ShowcaseData+Datasets.swift`)**:
  - Implemented pure `Sendable` showcase data structures covering local macOS filesystem (`/Users`), remote Linux nginx log tree (`/var/log/nginx`), and FreeBSD ports collection (`/usr/ports/security`), preserving `Mock*` backward compatibility typealiases.
  - Added simulated batch transfer queue jobs (active, queued, paused, completed, and conflict states), connection profile catalogs (SFTP, SCP, FTPS, FTP), partition disk usage (`statvfs`), and split terminal session outputs.
- **Reusable macOS HIG Design System Components (`src/Features/Showcase/Components/`)**:
  - `StatusBadge`: Compact capsule badge with semantic tints for transfer, connection, and protocol states.
  - `ModernProgressBar`: 4 pt rounded progress bar with smooth accent gradient fills.
  - `PathBreadcrumbsBar`: Interactive segmented breadcrumb path control (`NSPathControl` style) with folder icons and clickable navigation segments.
  - `DiskSpaceBar`: Compact storage usage bar displaying partition capacity, used/free bytes, and percentage.
  - `EmptyStateView`: macOS HIG empty state layout with 48×48 icon container, title, description, and primary action button.
- **8 High-Fidelity Native macOS Showcase Screens (`src/Features/Showcase/`)**:
  - `MainWorkspaceShowcase` & `MainWorkspacePaneView`: High-fidelity dual-pane commander workspace featuring workspace tab strip, quick connect bar, central transfer actions, path breadcrumbs, disk space gauges, and minimized transfer drawer.
  - `ConnectionManagerShowcase`: Session manager interface with grouped connection profiles, protocol badges, favorite filters, and detail inspector.
  - `TransferQueueShowcase`: Batch transfer queue monitor with live throughput gauges (MB/s), ETA countdowns, conflict state alerts, and batch controls.
  - `TerminalShowcase` & `TerminalShowcase+Panes`: iTerm2-inspired split terminal layout featuring simultaneous remote SSH and local shell panes with status badges.
  - `PreferencesThemesShowcase` & `PreferencesThemesShowcase+Contrast`: Visual theme palette browser showcasing Core, Extended, Spectrum, and Studio collections, paired with a live WCAG contrast checker inspector panel.
  - `EmptyStateShowcase`: Dedicated empty state showcase for new connections, empty directories, and inactive queues.
  - `ConflictDialogShowcase`: Dual-file comparison dialog with detailed metadata diffs (size, mtime, permissions) and Overwrite, Resume, Skip, and Rename options.
  - `DashboardShowcase`: High-level session analytics dashboard displaying throughput metrics, active connection cards, and recent transfer logs.
- **Isolated Showcase Gallery Launcher (`ShowcaseGalleryView.swift`, `SparkleSFTPApp.swift`)**:
  - Built an interactive sidebar gallery launcher allowing rapid previewing and testing of all 8 showcase screens, along with dynamic live palette switching.
  - Hooked launcher via `--showcase-gallery` (with `--mockup-gallery` alias), ensuring normal application startup flow and core transfer engines remain 100% untouched.
- **Maintenance Branches & IDE Diagnostics Hygiene**:
  - Established dedicated maintenance release branches `0.1.0`, `0.2.0`, `0.3.0`, `0.4.0`, and `0.4.1` on `origin` to streamline multi-version maintenance and cherry-picks.
  - Configured comprehensive IDE exclusions in `.vscode/settings.json`, `.markdownlint-cli2.jsonc`, and `.markdownlintignore` to eliminate false-positive diagnostics from SwiftPM checkout dependencies while keeping 100% strict verification across repository sources.
- **Localization Parity & Universal 2 Release Packaging**:
  - Added `showcase.*` and `mockup.*` localization keys to both `en.json` and `id.json` with 100% key parity (488 keys in both locales).
  - Built Universal 2 fat binary (`x86_64` + `arm64`) and packaged `SparkleSFTP-0.4.1-universal.dmg` with SHA256 checksum (`0e0dd7933d68a2782701cdd63b9f2e0c6cd541163421002d852c055dfc29ada9`).

## [0.4.0] - 2026-11-12

### Added, Fixed & Optimized (`T-054`–`T-065`)

- **Cold-Launch Theme Catalog Lazy-Loading (`ThemeCatalog`, `ThemePalette`, `AppState+NavigationAndShortcuts`, `PreferencesThemeTab`, `AppState+ConnectionManagement`)**:
  - Replaced eager startup instantiation of all 76 theme palettes with lightweight bootstrap initialization (`SparkleThemeStore.loadBootstrapPalettes`), instantiating only `defaultLight`, `defaultDark`, and the user's currently active palette at cold start.
  - Converted `SparkleThemeCatalog.builtInPalettes` to a computed property and added `findBuiltInPalette(id:)` with short-circuit lookup across Core, Extended, Spectrum, and Studio palettes.
  - Deferred instantiation of the remaining 74 palettes and scanning of custom theme JSON files via `FileManager` until `PreferencesThemeTab` is explicitly opened by the user.
- **Elimination of SwiftUI View Invalidation Thrashing (`MainWindowView`, `MainWindowView+Subviews`, `AppState`)**:
  - Decoupled `MainWindowView` root body evaluations from high-frequency transfer progress notifications by removing `.onReceive(appState.transferMonitor.$snapshots)` from the root window.
  - Extracted `MainWindowStatusBar` and `MainWindowMinimizedTransferBar` as dedicated, isolated `View` structs, preventing frequent transfer percentage and status message updates from invalidating the root `NavigationSplitView` and dual-pane commander views.
  - Routed transfer snapshot changes directly to `@MainActor` in `AppState.startTransferObserver` and bound updates to `TransferMonitor.updateSnapshots`.
- **Transfer Queue Update Coalescing & Throttling (`TransferMonitor`, `TransferQueue+Checkpoint`, `TransferQueueView`)**:
  - Implemented an 80ms throttle window (~12.5 Hz, within the ideal 10–15 Hz band) in `TransferMonitor.updateSnapshots` to prevent high-frequency micro-file transfers from saturating the SwiftUI render loop.
  - Removed the `snapshots.count <= 20` unthrottled bypass in `TransferQueue.broadcastSnapshots` so update coalescing applies consistently across all transfer queue volumes, reserving immediate flushes strictly for terminal status changes (`.completed`, `.failed`, `.cancelled`, `.paused`) and queue count transitions.
  - Maintained windowed rendering with `visibleLimit = 150` in `TransferQueueView` to ensure scroll performance remains fluid with zero jitter.
- **Cross-Platform Transfer Resilience & macOS Metadata Filtering (`SFTPService`, `Protocols`, `AppError`, `TransferQueue+Execution`, `AppState+TransferHelpers`, `DirectoryScanner`)**:
  - Added graceful POSIX `SETSTAT` tolerance: when remote `SSH_FXP_SETSTAT` fails with `SSH_FX_PERMISSION_DENIED` (common on Linux/BSD servers where non-root accounts cannot mutate `mtime` or `chmod`), logged a non-fatal warning instead of aborting the transfer.
  - Added automatic filtering of macOS `.DS_Store` and AppleDouble `._*` metadata files during local directory upload walks (`AppState+TransferHelpers.swift`) and directory synchronization scans (`DirectoryScanner.swift`), keeping remote Linux/BSD environments clean.
  - Upgraded in-progress upload temporary naming to `.destination.sparklesftp.<uuid>.filepart` with atomic rename upon verified completion, protecting against partial file corruption during sudden network dropouts while retaining backwards-compatible checkpoint resumption.
- **Startup Profiling Signposts (`SparkleSignposts`, `SparkleSFTPApp`, `AppState+Connections`, `AppState`)**:
  - Created `SparkleSignposts` using Apple's unified logging framework (`os.signpost` / `OSSignposter`) with subsystem `"com.sparklesftp.app"` and category `"LaunchPerformance"`.
  - Added interval signposts around `ThemeInitialization`, `InitialDirectoryListing`, and `WindowConfiguration` to enable accurate cold-launch latency and memory profiling in Xcode Instruments (Time Profiler & Points of Interest).
- **Test Suite Determinism & Headless Alert Guard (`AppState+Settings`)**:
  - Guarded `NSAlert.runModal()` during update checks in headless test environments to prevent test runner hangs.
  - Verified 100% test pass rate across all 121 tests in 33 test suites under Swift 6 strict concurrency with zero compiler warnings.

## [0.3.0] - 2026-11-12

### Added, Fixed & Optimized (`T-042`–`T-053`)

- **Zero Runaway CPU Loop Elimination & High-Performance Table Reuse (`SparkleWindowConfigurator`, `FilePaneTableView`, `LocalFileService`)**:
  - Eliminated the runaway 100% CPU infinite feedback loop in `SparkleWindowConfigurator` by replacing `NSWindow.didUpdateNotification` with `NSWindow.didResizeNotification`, preventing continuous layout triggers on every runloop pass.
  - Implemented AppKit cell and row reuse via `tableView.makeView(withIdentifier:owner:)` in `FilePaneTableView` for `ThemedFileRowView`, eliminating unbounded memory allocations of tracking areas and subviews during rapid dual-pane scrolling.
  - Added a 250ms debouncer in `LocalDirectoryWatcher` (`LocalFileService.swift`) to coalesce bursts of filesystem notification events and prevent repeated concurrent directory re-reads.
- **FileZilla-Inspired Activity Logging Console (`ActivityLogger`, `ActivityLogView`, `MainWindowView`, `SparkleSFTPApp`)**:
  - Added real-time timestamped `[HH:mm:ss]` activity logging engine (`ActivityLogger`) with semantic message categorization (Status, Command, Response, Error, Transfer) and active theme palette integration.
  - Created collapsible `ActivityLogView` console dock with level filters, auto-scroll toggle, quick copy (`⌘C` / Copy row / Copy message), clear, centered minimize/hide control, and global menu/toolbar toggle (`⌥⌘L`).
- **Workspace Tab Disconnect & Connect on New Tab (`AppState+WorkspaceTabs`, `WorkspaceTabStripRepresentable`, `WorkspaceTabBar`)**:
  - Added `tabs.disconnect` context menu option to drop the remote SSH/SFTP connection without closing the workspace tab, returning it safely to the local browser state.
  - Added `tabs.connectOnNewTab` context menu option to duplicate the profile connection directly into a fresh workspace tab.
- **Orthodox Commander Keyboard Shortcut Resolution (`InteractiveFileTableSupport`, `AboutView+Tabs`, `LocalizationCatalog`)**:
  - Resolved `F5` shortcut ambiguity: aligned `F5` strictly to cross-pane direct transfer (Upload in local pane, Download in remote pane), mapped custom target path prompt to `Copy To... (⇧F5)`, and preserved standard clipboard copy as `⌘C`.
- **Collapsible Transfer Drawer with Centered Minimize/Hide Toggle (`TransferQueueView`, `MainWindowView`)**:
  - Added a centered `[ ⌵ Hide / Minimize Transfers ]` button in `TransferQueueView` and a centered `[ ⌃ Transfers (N) ]` restore button in `MainWindowView` when collapsed.
- **Tooltips Perfection & Complete Bilingual Localization (`QuickConnectBar`, `DualPaneCommanderView+Actions`, `en.json`, `id.json`)**:
  - Audited and enriched interactive tooltips across all Quick Connect controls, action bar buttons, and status bar toggles with shortcut indicators, fully localized in English and Bahasa Indonesia.
- **Manual Update Check Modal User Feedback (`AppState+Settings`)**:
  - Implemented explicit AppKit `NSAlert` modal dialog for manual "Check for Updates Now" requests, displaying up-to-date status, update details with release URL button, or error reason.
- **Application Branding & Transparent Squircle Icon Update (`AppIcon.png`, `AppIcon.icns`)**:
  - Replaced application branding with the new 1:1 cloud-folder-lightning logo, removing the solid black background and replacing it with an RGBA continuous squircle mask with subpixel anti-aliased transparency outside the boundary across full 16x16 through 1024x1024 multi-resolution asset pipelines.
- **Standalone iTerm2-Style macOS Terminal (`T-049`: `StandaloneTerminalWindowController`, `StandaloneTerminalWindowView`, `StandaloneTerminalSplitView`, `StandaloneTerminalBars`, `StandaloneTerminalManager`, `StandaloneTerminalModels`, `LocalTerminalProcessRepresentable`)**:
  - Built a separate, full-screen-capable macOS terminal window (`⌘⌥T` and always-enabled toolbar button in `MainWindowView`) powered by `SwiftTerm.LocalProcessTerminalView`.
  - Added multi-tab local login shells (default `$SHELL`, `/usr/local/bin/bash -l`, `/bin/zsh -l`), sanitized SSH connection tabs (`ExternalTerminalLauncher.buildOpenSSHCommandParts`), arbitrary recursive vertical (`⌘D`) and horizontal (`⌘⇧D`) split panes (`TerminalSplitNode`), live `SwiftTerm` scrollback find bar (`⌘F` case/regex/whole-word + match counter), font zoom (`⌘+`/`⌘-`/`⌘0`), live 76-palette ANSI color synchronization, and Hardened Runtime direct-distribution entitlements (`com.apple.security.app-sandbox = false` in `SparkleSFTP.entitlements`).
- **Zero Launch / Click Keychain Prompt Loop (`T-044`: `FileHostTrustBackingStore`, `KeychainService`, `SSHClientService+Helpers`, `FTPService`)**:
  - Replaced launch-time Keychain queries on `HostTrustStore` with a `0600` POSIX JSON store (`trusted_hosts.v1.json`) plus one-time silent migration using `LAContext.interactionNotAllowed = true` (`HostTrustStore.swift`), added `KeychainMemoryCache` for non-TouchID lookups + non-interactive `hasSecret(for:)` checks, and allowed clean in-app credential prompt fallback when a Keychain item is missing or denied.
- **Non-Blocking Multi-File Transfer Engine, Responsive Context Menus & Queue Controls (`T-045`–`T-048`: `AppState+TransferHelpers`, `TransferScheduler`, `TransferJournal+Batch`, `TransferQueue+BatchActions`, `TransferQueueView`, `FilePaneTableView+Menu`, `ConnectionTableView+Menu`, `SparkleWindowConfigurator`)**:
  - Moved recursive local/remote folder enumeration off `@MainActor` into `Task.detached` workers batching 50-item chunks via `TransferQueue.enqueueBatch`, added O(1) `pendingIDs` tracking in `TransferScheduler`, added WAL transactions in `TransferJournal+Batch` (`upsertBatch`/`deleteBatch`), coalesced snapshot updates (`60ms`) and debounced busy pane refreshes (`2.0s`), cached window configurator palette/number state, and guarded `FilePaneTableView` & `ConnectionTableView` with `NSMenuDelegate` `isMenuOpen` checks so right-click menus stay smooth even during large directory transfers.
  - Added FileZilla-style Transfer Queue tabs (`Active`, `Completed`, `Failed`, `All`), **Abort All** (`cancelAll`), **Pause All**, **Retry Failed** (`retryAllFailed`), **Clear Completed** / **Clear Failed** / **Clear Finished** (`TransferQueueView`), and windowed `visibleLimit = 150` row rendering.
  - Suppressed `Swift.CancellationError` and `URLError(.cancelled)` globally via `AppState.reportNonCancellationError` (`AppState+NavigationAndShortcuts`, `+Operations`, `+Imports`, `+CommanderCommands`, `+InternalEditor`), keeping cancelled/failed transfer errors non-blocking inside the queue drawer and status banner instead of interrupting workflows with modal alerts.
  - Added independent **Upload** and **Download** 8-action "File Already Exists" policies (`Ask`, `Overwrite`, `Overwrite If Source Newer`, `Overwrite If Size Differs`, `Overwrite If Size Differs or Newer`, `Resume`, `Auto-Rename`, `Skip`) in `ConflictResolver`, `TransferQueue`, `AppSettingsSnapshot`, `PreferencesView`, and `TransferQueueView`.
- **Copyright-Safe Importer Naming & CI / C11 Fixes (`T-042`, `T-043`, `T-050`–`T-062`)**:
  - Removed all remaining proprietary trademark identifiers across source, tests, locales (`456` EN/ID keys), and documentation (`IniSessionImporter`, `.commanderINI`, `"import.iniFormat"`, `IniSessionPasswordDecoder`) while preserving full `[Sessions\...]` `.ini` + `0xA3` obfuscated password import compatibility.
  - Fixed `.github/workflows/codeql.yml` pre-resolve step (`swift package resolve` before `Initialize CodeQL` + `--skip-update`), `.github/workflows/release.yml` Checkov `CKV_GHA_7` annotation, `.vscode/settings.json`, `ClibcurlSystemLibs.c` C11 `ZLIB_CONST`/const-correct copy without C-style casts (`0` Clang/Cppcheck warnings), expanded verification to **`121` tests in `33` suites** across **`188` Swift files (`36,120` LOC)**, and bumped bundle metadata to `0.3.0`.

### Added & Fixed (`T-041` and Earlier)

- **Full-Repository 14-Pillar Security, Concurrency, Transfer, Editor & CI/Release Hardening Pass (`T-041`)**:
  - **Memory Safety & Async Cancellation (`FTPService`, `CurlClientHelper`, `SFTPChannelBridge`, `SSHClientService+Helpers`, `SSHChannelHandlers`, `ClibcurlSystemLibs.c`)**: Pinned `CurlTransferBox` and `CurlMemoryBox` lifetimes across synchronous `curl_easy_perform` via `withExtendedLifetime(...)` to eliminate Swift Release `-O` Use-After-Free (`CWE-416`), propagated Keychain/auth/TLS errors out of `FTPService.connect`/`listDirectory` instead of silent fallback, validated FTP/proxy hosts and `curl_slist_append` OOM returns, fixed cancellation races & hangs in `SFTPChannelBridge.initializeSFTP`/`waitForPacketResponse` and `SSHClientService.runExec` (`ExecContinuationBox.cancel`), capped `deflateBound` > `UINT32_MAX` before `malloc`, fixed exact `max_output_bytes` gzip trailer inflation (`sparklesftp_zlib_inflate`), and removed bare relative `"libssh2.1.dylib"` `dlopen` search entries.
  - **SFTP Wire Codec, Pipelined Resume & Conflict Integrity (`SFTPPacketCodec+Decode`, `SFTPService*`, `FTPListingParser`, `TransferQueue*`, `ConflictResolver`, `TransferJournal`)**: Consumed SFTP `0x80000000` extended attributes cleanly, switched `SFTPService.download` to symlink-following `.stat` + awaited handle closes + local partial truncation, fixed `FTPListingParser` `S`/`T` non-execute permission decoding and static `DateFormatter` reuse, eliminated download sparse-zero-hole resume corruption when larger `.part` files exist alongside smaller destinations (`DownloadConflictPlan.allowPreparedPartial`) and pipelined upload out-of-order holes (`resolveUploadResumeOffset` bounded to verified contiguous checkpoints), added random collision-proof suffixes to `ConflictResolver.uniqueName`, and added `PRAGMA user_version = 1` + `"queued"` launch recovery to `TransferJournal`.
  - **Path/Command Injection Defense & Importer Fixes (`PathValidator`, `LocalFileService`, `ExternalTerminalLauncher`, `AppState+CommanderCommands`, `Sync*`, `DirectoryScanner`, `LocalizationCatalog`, `External*`)**: Closed rooted `/../../etc/passwd` bypasses in `PathValidator.canonicalizeRemote`, multi-segment traversal/symlink escapes in `SyncExecutor.resolveSafeLocalURL`, `createDirectory`/`rename` `CWE-22` traversal in `LocalFileService`, locale-code `CWE-22` writes in `LocalizationCatalog.importLocaleFile`, OpenSSH `--`/leading-hyphen `CWE-88` injection in `ExternalTerminalLauncher`, and `/usr/bin/tar --` injection + UI blocking in `AppState+CommanderCommands`; fixed Commander INI `FSProtocol` mapping (`0` = `.scp`, `1`/`2` = `.sftp`), FileZilla space-containing `RemoteDir` decoding + strict password encoding handling, `SyncPlanner` `.remoteToLocal` `.update` remote mtime verification, duplicate relative-path safety, and dangling remote symlink resilience in `DirectoryScanner`.
  - **UI Lifecycle, Terminal, Editor & Localization (`AppState*`, `MainWindowView`, `Terminal*`, `PortForwardingManager`, `Editor*`, `CommanderCustomCommandSheets`, `ThemePalette`, `en.json`/`id.json`)**: Added `onDismiss` continuation cancellation handlers across Host Key, Credential, and Conflict sheets (`Esc`-safe), extracted `AppState+Prompts` & `AppState+InternalEditor`, re-validated active session indices after `await` in `AppState+Operations`, fixed `disconnect` session assignment and `quickConnectPassword` clearing, preserved `.auto` `NSAppearance = nil` for live system theme switching, fixed `TerminalViewRepresentable` tab rebinding + `10,000`-line scrollback + pre-attach PTY buffering + `PortForwardingManager` `autoRead = false`, fixed `EditorModels` UTF-16 LE BOM duplication + `NotepadLineNumberRuler` EOF glyph bounds + `CopyMoveItemSheet` destination toggle updates, validated all 11 palette hex fields in `SparkleThemeStore.isValidPalette`, and added missing `"conn.password"` key across EN/ID catalogs (`366` keys).
  - **CI, Secret Scanning, Release Tooling & Verification (`_config.yml`, `.betterleaks.toml`, `.swiftlint.yml`, `codeql.yml`, `Tools/Release/*`, `Tools/TestServers/*`, `docs/*`)**: Excluded source trees and test fixtures from GitHub Pages via `_config.yml`, switched `.betterleaks.toml` allowlist to `condition = "AND"` on `src/` paths, expanded `.swiftlint.yml` `no_password_in_logs` + `kSecAttrAccessibleAlways`, added `swift` (`macos-15`) and `c-cpp` (`ubuntu-latest`) scanning to `codeql.yml`, switched `create-dmg.sh` to sign before hashing, replaced `codesign --deep` with inside-out Sparkle component signing in `build-universal.sh` and `notarize.sh` (`SPARKLE_BUILD_JOBS:-2` + Apple `/usr/bin/clang` export), bound `docker-compose.test.yml` ports to `127.0.0.1`, aligned `docs/` & ADR diagrams/claims, and expanded verification to **`111` tests across `31` Swift Testing suites** (`169` Swift files, `0` SwiftLint/SwiftFormat/Trunk/MegaLinter issues).

- **Standalone AppKit Preferences Window, Active Close/Minimize/Zoom Controls, Titlebar Z-Order & Fixed Dialog Box Sizes (`SparkleWindowConfigurator`, `ManagedWindowController`, `PreferencesWindowController`, `AboutWindowController`, `EditorWindowController`, `SparkleSFTPApp`, `AppState*`, `MainWindowView`, `ConnectionViews`, `WorkspaceTabBar`, `PreferencesView`, `AboutView`, Modal Sheets)**:
  - Fixed macOS `MainWindowView` (`WindowGroup` + `NavigationSplitView`) titlebar & toolbar visibility where SwiftUI stacked `NSHostingView<MainWindowView>` above `NSTitlebarContainerView` while `.background(palette.windowColor)` ignored safe-area edges and painted over the `52pt` titlebar, traffic lights, and toolbar items — enforcing `SparkleWindowConfigurator.isTitlebarCoveredByContent` (`positioned: .above`) and `ignoresSafeAreaEdges: []` on `MainWindowView`, `ConnectionManagerView`, and `WorkspaceTabBar`.
  - Replaced SwiftUI's `Settings` scene (which stripped Minimize/Maximize buttons and dynamically resized per tab on macOS) with `PreferencesWindowController` backed by shared `ManagedWindowController` (`sizingOptions = [.minSize]`, single-window reuse, live locale title sync, `760x600` fixed tab-switch geometry) wired via `CommandGroup(replacing: .appSettings)` (`⌘,`) and `DualPaneCommanderView+Actions.configureEditor`.
  - Refactored `AboutWindowController` (`720x560` constant) and `EditorWindowController` (`900x620`) onto `ManagedWindowController` with zero duplicate window boilerplate and persistent Close/Minimize/Maximize traffic lights.
  - Locked every modal sheet dialog to explicit fixed `width x height` geometry with internal scroll containers so toggles, conflict choices, or empty/populated lists never resize dialogs (`SyncPreviewSheet` `680x500`, `ConflictResolutionSheet` `580x560`, `HostKeyVerificationSheet` `500x240`, `CredentialPromptSheet` `460x220`, `PermissionsEditorSheet` `360x190`, `RenameItemSheet` `380x165`, `NewFolder` `360x165`, `CopyMoveItemSheet` `480x230`, `FileComparisonSheet` `640x320`, plus `ImportConnectionsSheet`, `SecurityDiagnosticsView`, `ConnectionEditorView`), expanding verification to **`95` tests across `25` Swift Testing suites** (`PreferencesAndDialogSizeTests`, `160` Swift files / `31,467` LOC).

- **1-Tab = 1-SSH Shell Binding, Quick Connect Scoping & v0.1 `terminal.fill` Icon (`TerminalSessionManager`, `WorkspaceModels`, `AppState+WorkspaceTabs`, `AppState+Imports`, `TerminalWorkspaceView`, `MainWindowView`, `WorkspaceTabBar`, `WorkspaceTabChipView`, `AppState+Settings`)**:
  - Bound each connected `WorkspaceTab` 1-to-1 with its own single SSH `TerminalTabSession` (`workspaceTabID` + `remoteSessionID`), automatically switching or hiding the bound Shell drawer across workspace tab changes, removing redundant multi-tab terminal chrome and split-terminal UI (`splitTerminalMode` and dead `preferredShellPath` removed), and restoring v0.1 `SparkleTheme.Symbols.terminal` (`"terminal.fill"`) across toolbar and status bar (`ShellTabsAndWindowControlsTests`).
  - Restricted `QuickConnectBar`, `quickConnectToggleButton`, and toolbar lightning `Connect` strictly to unconnected New Tabs / New Windows (`AppState.isQuickConnectAvailable == true`), updating disconnected tab chips to `"macwindow"`.
- **Preferences Themes Card Grid GUI & Synchronized `365`-Key JSON Catalogs (`PreferencesThemeTab`, `en.json`, `id.json`, `LocalizationCatalog`)**:
  - Redesigned `PreferencesThemeTab` from a cramped macOS `List` into a responsive `LazyVGrid` card gallery (`ThemePaletteCard`, active selection border, WCAG AA badge) paired with a Live Active Theme Preview card (`ThemeActivePreviewCard`), structured Appearance/Family/Search/Tone filter bar, empty-state Reset Filters card, and 4 new localized keys (`prefs.themeActivePreview`, `prefs.themeNoResults`, `prefs.themeResetFilters`, `nav.closeShell`) bringing `en.json`/`id.json` parity to `365` keys.
- **Persistent macOS Traffic Lights, Scoped Keyboard Shortcuts & Menu Dispatch (`SparkleWindowConfigurator`, `PreferencesView`, `EditorWindowController`, `SparkleSFTPApp`, `InteractiveFileTableSupport`, `InteractiveConnectionTableSupport`, `ConnectionTableView`, `AboutView+Tabs`)**:
  - Added lock-safe `WindowObserverBox` monitoring `NSWindow.didBecomeKeyNotification`, `NSWindow.didUpdateNotification`, and next-runloop layout resets alongside unrestricted `maxSize` so `Close`, `Minimize`, and `Maximize/Zoom` buttons remain active on Main, Preferences (`allowFullScreen: true`), About, and Editor (`sparkle.editor`) windows.
  - Added `isTableResponderFocused()` (allowing child views while ignoring `NSText` editing) and exact modifier masks (`⌘` vs `⌘⇧C`/`⌘⌥C` vs `⌘↩`/`⌥↩` + `F7` `keyCode 98`) in both `InteractiveFileTableView` and `InteractiveConnectionTableView`, moved `⌘⇧S` Synchronize into `SparkleAppCommands` via `AppState.isShowingSyncSheet`, hardened `⌘W` with `hostWindow` and `sparkle.editor` multi-tab awareness, and refreshed `AboutView+Tabs`.
- **Speedometer Stall Decay, SFTP Pipelined Ordering, Actor Reentrancy & Bottom-Up Folder POSIX Permissions (`TransferSpeedMeter`, `SFTPChannelBridge`, `SFTPServiceHelpers`, `TransferQueue*`, `AppState+TransferHelpers`, `AppState+NavigationAndShortcuts`, `RemoteFileModels`, `SFTPService`, `FTPListingParser`, `TransferQueueView`)**:
  - Updated `TransferSpeedMeter` with `0.01s` start denominator clamp, `>= 0.4s` exponential stall decay, and `>= 2.0s` zeroing (`FolderPermissionsTransferTests`).
  - Converted SFTP pipelined upload (`SFTPPipelinedTransfer.transferUpload`) to sequential `submitPacket` + concurrent `awaitPacket` with contiguous ACK tracking (`ackedSlices`) and bounded `abandonedRequestIDs` tracking in `SFTPChannelBridge`.
  - Fixed `TransferQueue.handleProgress` actor reentrancy across `await throttler.shouldEmit` (`ProgressSequenceBox` + post-await `isProgressWritableStatus` re-validation and `.paused`/terminal guards in `updateSnapshot`), added paused download checkpoint reconciliation (`finalizeExecutionSlot`), supported `100%` remote `.part` upload resume (`remotePartial.size <= localSize`), cleaned stale `.part` + zeroed reported bytes on Conflict `.skip`, rendered `1.0` progress for `.completed` 0-byte transfers (`TransferProgressBar`), preserved temporary `(mode | 0o700)` while transferring folders before restoring exact `mode & 0o777` bottom-up (`PendingFolderPermissionJob`), and fixed `0o755` default directory permissions in `RemoteFile`, `SFTPService`, and `FTPListingParser` (`TransferEngineResumeTests`, `LoopbackTransferResumeTests`).
  - Expanded test coverage to **`91` tests across `24` Swift Testing suites** across **`157` Swift files (`31,031` LOC)** with `0` SwiftLint/SwiftFormat/Trunk/MegaLinter issues.

- **Commander `.ini` Simple Password Decryption & Neutral Filename Refactor (`ExternalSessionFileReader.swift`, `AppState+CommanderCommands.swift`, `CommanderCustomCommandSheets.swift`, `WindowTabsAndCommanderCommandsTests.swift`)**:
  - Implemented `IniSessionPasswordDecoder` inside [`ExternalSessionFileReader.swift`](src/Packages/Persistence/ExternalSessionFileReader.swift) supporting Commander INI `0xA3` simple XOR obfuscation (`0xFF`/`0x00` standard UTF-8 with percent-decoded & empty-username candidate key verification, plus legacy `< 0xFF` format), storing decoded credentials via `ImportedConnection.transientSecret` -> Apple Keychain (`KeychainService`) with `.plaintextReady` preview status while failing closed to `.encryptedUnavailable` whenever `[Configuration\Security] UseMasterPassword=1` or malformed hex/framing is encountered.
  - Renamed all four files previously containing `commander` to `ExternalSessionFileReader.swift`, `AppState+CommanderCommands.swift`, `CommanderCustomCommandSheets.swift`, and `WindowTabsAndCommanderCommandsTests.swift`.
- **Post-Completion Long-Term Review Refresh (`5c2c212`), `ADR-008` & SonarQube Generic Report Alignment (`docs/LONG_TERM_REVIEW_2026_11.md`, `docs/ADR/0008-*.md`, `sonar-project.properties`)**:
  - Added [ADR-008](docs/ADR/0008-multi-window-isolation-appkit-tab-chrome-76-themes-and-transfer-pipeline.md) documenting multi-window `AppEnvironment` state isolation, AppKit tab bar chrome, `SparkleWindowConfigurator`, the 76-palette catalog, `Local Shell` removal, scoped keyboard shortcuts, and the permission-preserving 64 KB transfer pipeline.
  - Updated [`docs/LONG_TERM_REVIEW_2026_11.md`](docs/LONG_TERM_REVIEW_2026_11.md) across all 14 pillars and 14 skills against live `5c2c212` metrics (`155` Swift files / `29,344` LOC, `83 tests in 22 suites`, `361` EN/ID keys, `18` prod + `5` test `@unchecked Sendable` boxes, SwiftUI/`NSTableView` audit, Sparkle sandbox XPC `-spks`/`-spki` & inside-out signing gaps, Docker fixtures, and 90-day / 12-month roadmaps).
  - Fixed [`sonar-project.properties`](sonar-project.properties) (`sonar.projectVersion=0.2.0` matching `Info.plist`, switching to `sonar.externalIssuesReportPaths=reports/swiftlint-sonarqube.json` for `swiftlint --reporter sonarqube`), reconciled Explicit vs Implicit FTPS wording in [`SECURITY.md`](SECURITY.md), aligned `--no-parallel` guidance in [`CONTRIBUTING.md`](CONTRIBUTING.md), and synced [`README.md`](README.md), [`README-id.md`](README-id.md), [`DOCNOTE.md`](DOCNOTE.md), [`TODO.md`](TODO.md), [`tasks/`](tasks/), and `docs/*.md`.
- **Full `SparkNotePad` / `NotepadNext-MacOS` 76-Theme Catalog, Contrast Hardening & Preferences Filter (`SparkleDesignSystem`, `PreferencesThemeTab`, `MainWindowView`, `AppState+Settings`)**:
  - Expanded `SparkleThemeCatalog` across modular catalogs (`ThemeCatalogCore`, `ThemeCatalogExtended`, `ThemeCatalogSpectrum`, `ThemeCatalogStudio`) to **76 curated palettes across 26 families** (`Auto`/`Light`/`Dark`), hardening WCAG 2.1 AA contrast (`>= 4.5:1`) on both canvas and window chrome (`solarizedLight` darkened to `#485A61`, `synthWave84Glow` primary `#F8F8F2`).
  - Added theme search bar, `All` / `Light` / `Dark` tone segmented filter, and matching theme count badge in `PreferencesThemeTab`, exposed all 26 families via grouped submenus in `MainWindowView`, fixed `AppState.resolveSystemDarkMode()` when `NSApp.appearance != nil`, and propagated `NSAppearance` (`aqua`/`darkAqua`) + `NSWindow.backgroundColor` across Main, Preferences, About, Internal Editor, and AppKit/SwiftTerm surfaces.
- **Native macOS Window Controls & Configurator (`SparkleWindowConfigurator`, `AboutWindowController`, `AboutView`, `PreferencesView`, `InternalEditorView`)**:
  - Added reusable `SparkleWindowConfigurator` (`NSViewRepresentable`) enabling `[.titled, .closable, .miniaturizable, .resizable]`, `.fullScreenPrimary`, and visible/enabled Close, Minimize, and Maximize/Zoom traffic-light buttons across Main, About, Preferences, and Editor windows while syncing active theme chrome.
- **`src/` Repository Restructure & SonarQube Tooling (`Package.swift`, `sonar-project.properties`, `.github/workflows/`, `Tools/Release/`)**:
  - Reorganized source folders into `src/App/`, `src/Features/`, and `src/Packages/*` (`Package.swift`, `.swiftlint.yml`, `.mega-linter.yml`, `.clangd`, `.vscode/*`, `Tools/Release/build-universal.sh`, `Tools/Release/notarize.sh`, `.github/workflows/release.yml`, `.github/pull_request_template.md`).
  - Added `sonar-project.properties` wiring `sonar.sources=src`, `sonar.tests=Tests`, and `swiftlint --reporter sonarqube` output alongside `.trunk/trunk.yaml` and MegaLinter v10 checks.
- **Independent Multi-Window Sessions & FileZilla XML & Commander INI Multi-Tab Workspaces (`AppEnvironment`, `SparkleSFTPApp`, `AppState+WorkspaceTabs`, `WorkspaceTabBar`, `WorkspaceTabBarActionButton`, `QuickConnectBar`)**:
  - Refactored `AppEnvironment` to share persistent stores while calling `makeWindowState()` for every `WindowGroup` instance (`⌘N` now opens a fresh blank session instead of cloning active sessions), synchronized saved profile/group and theme/locale updates cleanly via `NotificationCenter` (`sparkleConnectionsDidChange` / `sparklePreferencesDidChange`), added `WindowGroup(id: "connection-window", for: UUID.self)` for **Connect in New Window**, and tracked active window menus via `FocusedValues`.
  - Replaced `ActiveSessionModel`'s profile-ID key with per-tab session UUIDs inside `WorkspaceTab` (supporting multiple independent tabs to the same server with `#2` disambiguation and paired local directory history) backed by native AppKit `WorkspaceTabStripRepresentable` + `TabBarActionButton` controls and inline `QuickConnectBar` (`Protocol`, `Host`, `Port`, `Username`, `Password`, `Save`, `Quickconnect`), automatically hiding both `QuickConnectBar` and the Quickconnect toggle button whenever the active tab has a connected session.
- **Responsive AppKit Mouse Hover/Selection, Visible Connection Toolbar & Commander Context Menus (`ConnectionTableView`, `ConnectionViews`, `InteractiveFileTableSupport`, `FilePaneTableView+Menu`, `AppState+CommanderCommands`, `CommanderCustomCommandSheets`)**:
  - Added `NSTrackingArea` row hover highlighting (`ThemedConnectionRowView`, `ThemedFileRowView`), immediate `rightMouseDown` clicked-row auto-selection, and native `selectAll(_:)` (`⌘A`) / `delete(_:)` responders to both Connections and Commander file tables, reusing cached `ConnectionListCoordinator.symbolImage(isEncrypted:)` SF symbols.
  - Added an always-visible Connection sidebar toolbar (`Connect`, `New`, `Edit`, `Select All`, `Delete` + count badge) and Commander host context menu (`Connect`, `Connect in New Tab`, `Connect in New Window`, `Open in External Terminal`, `Edit`, `Clone`, `Copy Host Address`, `Select All`, `Delete`).
  - Expanded Commander `NSMenu` and `DualPaneCommanderView+Actions` with Commander actions (`Edit` submenu -> Internal Notepad / External App / Editor Preferences, `Copy... F5`, `Move... F6`, `Delete F8`, `Rename F2`, `Copy to Clipboard`, `File Custom Commands` -> `Compare Files` / `Compress & Upload (.gz)` via `-lz` / `Verify Checksum (SHA-256)` / `CWE-78`-quoted `Execute Custom SSH Command...`, `File Names` -> `Insert to Command Line` in terminal / `Copy Name(s)` / `Copy Full Path(s)`, `Properties F9`, `Permissions`, `New Folder`, `Select All`, `Show in Finder`), with synchronized EN/ID JSON catalogs (`361` keys).

- **Third-Party Library Support, Runtime Toolchain Diagnostics & SSH / iTerm2 Shell Integration (`src/Packages/Clibcurl`, `SparkleCore/ToolchainModels`, `SparkleNetworking`, `SparkleTerminal`, `src/Features/*`)**:
  - Linked macOS SDK `-lz` (`zlib`) alongside `-lcurl` in [`Package.swift`](Package.swift) `Clibcurl` and added bounded C11 streaming codecs (`sparklesftp_zlib_deflate`, `sparklesftp_zlib_inflate` with `MAX_WBITS + 32` auto-detect and `max_output_bytes` `CWE-409` zip-bomb cap + `UINT32_MAX` guard) plus `ZlibCompressionCodec` and optional `SCPCompatibilityAdapter` gzip helpers.
  - Optimized `CurlClientHelper` with `256 KB` buffers (`CURLOPT_BUFFERSIZE`, `CURLOPT_UPLOAD_BUFFERSIZE`), `TCP_NODELAY`, `TCP_KEEPALIVE`, `curl_version_info` inspection (`sparklesftp_curl_version_summary`, `sparklesftp_curl_supports_zlib`), and non-blocking off-cooperative GCD worker dispatch (`runOffCooperativePool`) for concurrent FTP/FTPS transfers.
  - Added dynamic `dlopen`/`dlsym` probing for optional Homebrew `libssh2` (`sparklesftp_probe_libssh2`, preserving CI & Universal 2 portability), OpenSSL/OpenSSH/shell detection (`ToolchainInspector`), `CWE-78`-sanitized external terminal launching (`ExternalTerminalLauncher` for iTerm2 / Apple Terminal.app with App Sandbox `ssh://` URL fallback), restored v0.1's `terminal.fill` Shell icon (`SparkleTheme.Symbols.terminal`), and added a 7th **Libraries** tab (`AboutTabKind.libraries`) in `AboutView`.
- **Multi-Thread Pipelined Upload/Download, EWMA Speedometer & Permission-Preserving Recursive Transfers (`TransferSpeedMeter`, `SFTPService`, `SCPCompatibilityAdapter`, `FTPService`, `TransferQueue*`, `AppState+TransferHelpers`)**:
  - Added lock-protected EWMA `TransferSpeedMeter` shared across SFTP, SCP, and FTP/FTPS (filtering `CurlClientHelper` resume `total=0` spikes and rate jitter) and bumped SFTP transfer block size from `32 KB` to `64 KB` with sliding window `min(32, max(2, pipelineDepth * 4))` (`SFTPPipelinedTransfer`).
  - Preserved POSIX permissions (`& 0o777`) on both uploaded and downloaded files and directories (`TransferTaskMetadata.sourcePermissions`, merge-safe `ensureRemoteDirectory` with owner-`0o700` upload guard, `FileManager.setAttributes` after atomic `replaceItemAt`), enabled hidden dotfiles (`showHidden: true`) + symlink cycle guards in recursive folder transfers, fixed upload resume (`resolveUploadResumeOffset`), `.queued` & terminal-status `pause` handling, monotonic progress enforcement, and debounced pane auto-refresh (`AppState+NavigationAndShortcuts`).
  - Updated `TransferScheduler` defaults to `4` global (`1...16`) / `3` per-host (`1...8`) concurrent transfers and default SFTP pipeline depth `8` (`1...16`), persisted cleanly in Preferences.
- **FileZilla-Style Conflict Overwrite Dialog & Language Switcher Redesign (`ConflictResolutionSheet`, `ConflictResolver`, `TransferQueue+ConflictHelpers`, `PreferencesLocalizationTab`, `MainWindowView`, `SparkleSFTPApp`)**:
  - Added FileZilla-inspired `ConflictResolutionSheet` showing side-by-side Source vs Target comparison cards, 7 resolution actions (`Overwrite`, `Overwrite if source newer`, `Overwrite if different size`, `Overwrite if different size or newer`, `Resume`, `Rename`, `Skip`), sticky checkboxes (`Always use this action`, `Apply to current queue / direction only`), and FIFO serialized `AppState.pendingConflictQueue` with automatic sticky drain for concurrent multi-thread conflicts plus SFTP rename-overwrite target cleanup.
  - Redesigned `PreferencesLocalizationTab` with a clickable locale card grid (showing translation coverage and key count), synchronized language picker, and 2x2 JSON maintenance grid, paired with toolbar/status-bar Globe menus (`MainWindowView`) and macOS menu commands (`SparkleSFTPApp`), backed by `361` synchronized EN/ID JSON keys.
- **Multi-Theme Engine (`76` SparkNotePad Palettes / `26` Families) & Full Workspace Propagation (`SparkleDesignSystem`, `Packages/Terminal`, `Features/*`)**:
  - Added `SparkleThemePalette`, `ThemeAppearanceMode` (`auto`/`light`/`dark`), WCAG 2.1 relative luminance & contrast ratio calculation, modular `SparkleThemeCatalog` + `ThemeCatalogCore`/`Extended`/`Spectrum`/`Studio` (`76` curated developer palettes across `26` families), and `SparkleThemeStore` for runtime custom JSON theme loading, import, and export.
  - Added `PreferencesThemeTab` with search bar, `All`/`Light`/`Dark` tone filter, live preview cards, family filter, appearance selector, WCAG contrast badge, and custom Themes JSON folder controls, plus grouped 26-family menus in `MainWindowView`.
  - Propagated live `SparkleThemePalette` surfaces (`surfaceColor`, `selectionColor`, `View.sparkleWorkspaceSurface(_:useCanvas:)`, `SparkleWindowConfigurator`, `NSApp.appearance` + `NSApp.windows` background sync, AppKit `ConnectionListTableView` & `InteractiveFileTableView` cell/header/selection styling, and `TerminalThemeColors` in `TerminalViewRepresentable` / `TerminalWorkspaceView`) across all Commander panes, Transfers, Snippets, Port Forwarding, Preferences tabs, Sync, Connection sheets, About windows, and Editor windows.
- **Maintainable JSON i18n System (`Packages/DesignSystem/Resources/Locales/`)**:
  - Replaced static localization tables with bundled `en.json` & `id.json` (`361` synchronized keys), `LocalizationCatalog` runtime override support (`~/Library/Application Support/SparkleSFTP/Locales/`), and `PreferencesLocalizationTab` showing translation coverage, missing keys, and JSON import/export tools.
  - Localized remaining Commander, Connections, About, Sync, Terminal, Transfer Queue, Conflict Dialog, Toolchain Inspector, and Settings views/context menus via `AppStrings.t(_:fallback:)`.
- **SparkNotePad-Style About Window & 1:1 Branded Logo (`Features/Dashboard/AboutView*`, `App/Resources/AppIcon.*`, `SparkleSFTPApp`)**:
  - Added `AboutWindowController`, `AboutView`, and `AboutView+Tabs` featuring 7 structured tabs (`About`, `Maintainer`, `Credits`, `Libraries`, `Diagnostics`, `Shortcuts`, `License`), copyable runtime diagnostics, GitHub/PayPal links, live theme styling, and macOS menu bar (`CommandGroup(replacing: .appInfo)`) + toolbar Info button integration.
  - Updated `App/Resources/AppIcon.png` (`1024x1024` 1:1 squircle mask) and `App/Resources/AppIcon.icns` preserving the SparkleSFTP cloud/folder/arrows/bolt motif styled in SparkNotePad's blue, white, and pastel yellow pencil palette.
- **Keychain Password Persistence & Runtime `FTPService` Prompt (`AppState`, `ConnectionEditorView`, `CredentialPromptSheet`, `FTPService`)**:
  - Added explicit Keychain secret status indicator (`hasSavedSecret(for:)`), **Remember password in Apple Keychain** toggle, and explicit secret clearing (`clearStoredSecrets`, `deleteProfileSecrets(_:)`) in `ConnectionEditorView` and `CredentialPromptSheet`, wired through `resolveCredentialPrompt(_:remember:)` and `finalizeSuccessfulConnection` plus runtime `credentialPrompt` support in `FTPService`.
- **Connection List Ergonomics: Double-Click Connect, Clone Connection & Multi-Select Delete (`Features/Connections/`, `AppState+ConnectionManagement`)**:
  - Added double-click-to-connect gesture on every Connection List row with concurrent per-profile connect guard (`connectingProfileIDs`).
  - Added **Clone Connection** (`AppState.cloneProfile(_:)`) duplicating all connection metadata cleanly and re-issuing independent `SecretReference` Keychain entries so deleting or modifying a clone never affects the original profile's credentials.
  - Upgraded Connection List selection to `Set<UUID>` (`selectedProfileIDs`), enabling native macOS `⌘A` Select All, **Select All** action menu control, `.onDeleteCommand`, batch **Delete Selected** confirmation dialog, and atomic multi-profile removal via `ConnectionStore.deleteProfiles(ids:)`.
- **Minimalist Notepad2 Internal File Editor (`Features/Editor/`)**:
  - Added multi-tab AppKit `NSTextView` + `NSRulerView` editor (`NotepadTextView`, `NotepadLineNumberRuler`, `EditorSyntaxHighlighter`, `InternalEditorToolbar`, `InternalEditorBars`, `InternalEditorView`, `EditorWindowController`) accessible via `⌘E`, toolbar, double-click policy, and Commander context menu on both local and remote files.
  - Features theme-linked regex syntax highlighting (`Swift`, `JSON`, `YAML`, `XML/HTML`, `Shell`, `Markdown`, `INI/Conf`, `SQL`, `Log`), whitespace/tab symbol overlay (`¶`), word wrap, zoom `+/-/%`, read-only lock, Find & Replace (`Aa` / `.*`), Go-to-Line, text case/trim/sort transforms, `UTF-8`/`UTF-8 BOM`/`UTF-16 LE`/`ASCII` & `LF`/`CRLF` converters, live cursor/selection/byte status bar, and automatic remote upload on save.
- **Auto-Update Preferences & Fallback Feedback (`UpdateModels`, `App/SparkleUpdaterService`, `Features/Settings/PreferencesUpdatesTab`)**:
  - Added persisted `AutoUpdateSettings` (`automaticallyChecks`, `automaticallyDownloads`, `Hourly`/`Daily`/`Weekly`/`Manual` cadence, `Stable`/`Beta` channel, validated HTTPS feed URL, overdue startup checks) plus semantic `UpdateConfigurationValidator.isNewerVersion(_:than:)` and a live TLS GitHub Releases check for community builds alongside signed Sparkle mode.
- **FileZilla & Commander Reader & Preview Importer (`Packages/Persistence`, `Features/Connections/ImportConnectionsSheet`)**:
  - Added `ExternalSessionFileReader.swift` with security-scoped file access, UTF-16LE/BE/UTF-8 BOM and Windows-1252/Latin-1 decoding, Commander `0xA3` simple password decryption (`0xFF`/`0x00` standard & legacy, fail-closed on `[Configuration\Security] UseMasterPassword=1`), nested `Sessions\Folder%2FName` group preservation, `FSProtocol` (`0/1/2/5`) & proxy extraction, `skippedUnsupported` tracking, and interactive `ImportConnectionsSheet` selective import.
- **Bidirectional & Reverse Directory Synchronization (`TASK-108`)**:
  - Added `SyncDirection` (`.localToRemote`, `.remoteToLocal`, `.bidirectional`), `SyncActionDirection` (`.upload`, `.download`), and bidirectional merge planning/execution across `SyncPlanner`, `SyncExecutor`, and `SyncPreviewSheet`.

### Fixed

- **Fast Non-Deadlocking Quit & Runtime Performance Tuning (`AppDelegate`, `SSHClientService`, `TransferMonitor`, `LocalFileService`, `FilePaneTableView`)**:
  - Fixed a guaranteed ~2-second `@MainActor` `DispatchSemaphore` quit deadlock in `AppDelegate.applicationWillTerminate` by adopting `applicationShouldTerminate` (instant `.terminateNow` when idle, bounded `<= 350ms` `.terminateLater` otherwise), synchronous `prepareFastShutdown()`, parallel session/tunnel teardown (`shutdownAsyncResources()`), and bounded channel/EventLoopGroup closure (`SSHClientService.closeChannelAndShutdownGroup`) preserving strict child-to-bastion `ProxyJump` teardown order.
  - Fixed `ConnectionEditorView` Edit modal sometimes opening like "New Connection" by replacing dual `@State` sheet flags with an atomic `ConnectionEditorMode` `.sheet(item:)` + `.id(mode.id)` and initializing all `@State` fields directly in `ConnectionEditorView.init` & `ConnectionAdvancedOptions(profile:)`.
  - Decoupled 10Hz transfer progress ticks from whole-window `AppState` invalidation via dedicated `TransferMonitor` (`TransferQueueView`), cached `AppState.strings` and `activePalette` (with OS `colorScheme` sync), throttled periodic SQLite `TransferJournal` writes during `.transferring` ticks to `>= 2.0s` (ignoring throughput-only fluctuations via `statusCode`), switched `LocalFileService.listDirectory` to single-`lstat` POSIX calls, cached static SF Symbol `NSImage`s in `FilePaneTableView`, and replaced N×M group scans with O(N) `Dictionary(grouping:)`.
- **Superseded-Worker Reentrancy Race & Deterministic Test Timing (`Packages/TransferEngine/TransferQueue*`, `Tests/`)**:
  - Added per-execution `activeWorkerTokens` & `@TaskLocal currentWorkerToken` (`isCurrentWorkerValid`, `finalizeExecutionSlot`) in `TransferQueue` + `TransferQueue+Checkpoint.swift` so a cancelled worker from `pause(id:)` unwinding asynchronously never deletes a quickly retried worker's `activeTasks` entry or overwrites its `.connecting`/`.transferring` snapshot (`RUN-003`).
  - Replaced hardcoded `250ms`–`300ms` waits across `TransferEngineTests`, `TransferEngineResumeTests`, `EditorAndSyncTests`, `IntegrationTests`, and `LoopbackSFTPIntegrationTests` with bounded predicate polling (`waitUntilSnapshot`) for deterministic CI stability.
- **Long-Term Post-Release Review & Bundle Crash Fix (`docs/LONG_TERM_REVIEW_2026_11.md`, `ADR-006`)**:
  - Completed comprehensive 14-pillar / 14-skill post-completion review covering Swift 6 concurrency (`17` prod `@unchecked Sendable`, `6` `DispatchQueue` sites, `SFTPPipelinedTransfer`), SwiftUI/`NSTableView` performance (`TransferMonitor`, cached `strings`/`activePalette`, `TD-01`/`TD-04`), SFTP/SCP/FTP/FTPS/`CWE-409`/`CWE-78` security posture, `SwiftTerm` & `TransferJournal` durability (`TD-05`–`TD-07`, `TD-12`–`TD-15`), Docker test fixture gaps (`TD-02`), explicit SonarQube configuration gap (`TD-08`), and Sparkle Ed25519 / inside-out signing release risks (`TD-03`), verified against post-`1b9d9f4` live GitHub Actions runs (`CI`, `MegaLinter`, `CodeQL Advanced`, `Deploy Jekyll`) with a prioritized 90-day / 12-month remediation roadmap.
  - Eliminated a critical `.app` packaging launch-crash hazard where `LocalizationCatalog.loadBundledStrings` and `AppDelegate.configureApplicationIcon` invoked SwiftPM's `Bundle.module` accessor directly while `Tools/Release/build-universal.sh` omitted `SparkleSFTP_*.bundle` artifacts from `Contents/Resources/` (added crash-safe `resolveResourceBundle()` lookup + `Contents/Resources/` bundle copying).
  - Updated [ADR-001](docs/ADR/0001-tech-stack-and-protocols.md) and [ADR-003](docs/ADR/0003-metadata-persistence-swiftdata-vs-json.md) supersession headers and added [ADR-006](docs/ADR/0006-post-mvp-theming-i18n-notepad2-and-updater.md).
- **Connection List & Commander Mouse/Keyboard Focus (`ConnectionTableView`, `FilePaneTableView`) & C/Clang IDE Config (`.clangd`, `.clang-format`)**:
  - Replaced SwiftUI `List(selection:)` + dual-tap gesture conflicts (`ConnectionViews.swift`) with native AppKit `ConnectionListTableView` (`NSTableView`) using unique section/profile row keys (`ConnectionManagerView.buildTableRows`), instant click selection, native `doubleAction`, arrow-key / `Return` / `Backspace` / `NSMenu` interaction, plus `InteractiveFileTableView` immediate responder focus on `mouseDown`, `Return` activate, `Space` Quick Look, and `Backspace`/`⌘↑` parent navigation.
  - Updated `.clang-format` (`SortIncludes: true`) and added `.clangd`, `Packages/Clibcurl/compile_flags.txt`, and `.vscode/c_cpp_properties.json` C11 configuration to eliminate `ClibcurlHelpers.c` and YAML header include diagnostics.
- Fixed `FileZillaImporter` nested `<Folder>` parsing where child `<Folder>` or `<Server>` elements cleared buffered parent folder names prior to commit (`flushPendingFolderName()`).
- Fixed `IniSessionImporter` BOM (`\u{FEFF}`) handling on line 1, `\`-first path splitting prior to percent-decoding, macOS `.fileImporter` `.ini` `UTType` selection filter, and `Optional<ImportedSecretStatus>.none` compiler warning.
- **Keyboard Shortcuts, AppKit Responder Validation & `Local Shell` Removal (`SparkleSFTPApp`, `DualPaneCommanderView+Actions`, `FilePaneTableView`, `ConnectionTableView`, `TerminalWorkspaceView`, `AboutView+Tabs`)**:
  - Removed the global `\t` command-menu hijack in `SparkleSFTPApp` (which blocked text field focus cycling) and eliminated duplicate `⇧⌘N` buttons across Dual-Pane panes in favor of a single `.sparkleRequestNewFolder` menu command, while adding `⌘W` close-tab-or-window, `⌘⇧[`/`⌘⇧]` tab cycling, `⌘\` pane switching, scoped `Tab` pane switching inside `InteractiveFileTableView` with real `firstResponder` handoff, and `validateUserInterfaceItem` + `performKeyEquivalent` handlers across file & connection tables (`⌘A`, `⌘C`, `⌘⌫`, `⌘↑`/`Backspace`, `⌘↓`/`Return`, `⌘I`/`F9`, `Space`, `F2`/`F5`/`F6`/`F8`).
  - Removed `Local Shell` (`openLocalShellTab`, `⌘⇧L`, `LocalShellTerminalRepresentable`, `"applescript"` SF Symbol, and Preferences Local Shell picker) in favor of remote SSH PTY + external `iTerm2` / `Terminal.app` launch, restored v0.1's `terminal.fill` Shell icon, and updated `AboutView+Tabs` keyboard shortcut documentation.
- Fixed Solarized Light (`#485A61`) and SynthWave '84 (`#F8F8F2`) text contrast to satisfy strict WCAG AA (`>= 4.5:1`) readability on both canvas and window chrome across all `76` built-in themes.

### Verification & Deferred Infrastructure

- Verified `83 tests in 22 suites` passing via `swift test --no-parallel` (including `WindowControlsAndShortcutsTests`, `FolderPermissionsTransferTests`, `WindowTabsAndCommanderCommandsTests`, `ToolchainAndConflictTests`, `AboutAndThemePasswordTests`, `ConnectionManagementAndPerfTests`, `ThemeAndLocalizationTests`, `ExternalImportersTests`, `BidirectionalSyncTests`, `EditorAndSyncTests`, `TransferEngineResumeTests`, and `UpdateConfigurationValidator` tests), `361` synchronized EN/ID keys (`0` diff), `0` violations across `155` Swift files on `swiftlint lint --strict` & `swiftformat --lint .`, `0` C11 warnings on `cppcheck`/`clang-format`/`clang -std=c11`, plus `trunk`, SonarQube reporter, `markdownlint-cli2`, `yamllint`, `actionlint`, `shellcheck`, and `shfmt` passing with exit code `0`.
- External release/runtime tasks remain deferred to dedicated environments: Live Docker multi-server interop test execution (`Tools/TestServers/run-integration-tests.sh`) and Universal 2 (`arm64` + `x86_64`) Apple Developer ID notarization + signed Sparkle Ed25519 appcast publishing (`Tools/Release/notarize.sh`).

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
  - `SparklePersistence`: `ConnectionStore` (atomic versioned JSON, zero secrets), `TransferJournal` (`SQLite3` WAL ACID journal with crash reconciliation and bounded retention), `SSHConfigParser`, and `ExternalImporters` (FileZilla XML + Commander INI).
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

[Unreleased]: https://github.com/alsyundawy/SparkleSFTP/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/alsyundawy/SparkleSFTP/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/alsyundawy/SparkleSFTP/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/alsyundawy/SparkleSFTP/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/alsyundawy/SparkleSFTP/compare/v0.2.0-mvp...v0.3.0
[0.2.0-mvp]: https://github.com/alsyundawy/SparkleSFTP/compare/v0.1.0-bootstrap...v0.2.0-mvp
[0.1.0-bootstrap]: https://github.com/alsyundawy/SparkleSFTP/releases/tag/v0.1.0-bootstrap
