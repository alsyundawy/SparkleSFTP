# ADR-008: Multi-Window State Isolation, AppKit Tab Chrome, 76-Theme Catalog, and Permission-Preserving Transfer Pipeline

## Status

Accepted

## Date

2026-11-11

## Context

Post-`0.2.0` desktop usability and protocol-reliability feedback identified five architectural gaps that needed resolution while keeping **macOS 13+ deployment**, **Swift 6 strict concurrency**, and **zero MainActor stalls**:

1. **Cloned Window State & SwiftUI Tab Chrome Clipping**: Sharing a single `AppState` across macOS `WindowGroup` windows caused `New Window` (`⌘N`) to mirror an active connection, while SwiftUI `.buttonStyle(.bordered)` action buttons alongside the AppKit tab strip lacked guaranteed AppKit hover/bounds fidelity and left `QuickConnectBar` visible over connected sessions.
2. **Window Traffic Lights & Shortcut Collisions**: Non-main windows (`About`, `Preferences`, `Editor`) lacked unified AppKit traffic-light (`Close`, `Minimize`, `Zoom`) & `NSAppearance` enforcement, global `\t` shortcut handling hijacked text-field focus traversal, and duplicate `⇧⌘N` bindings across panes conflicted in menu dispatch.
3. **Partial Theme Migration & Contrast Regressions**: The initial 28-palette catalog omitted 48 developer palettes from `SparkNotePad`/`NotepadNext-MacOS`, had sub-4.5:1 text contrast on chrome in `solarizedLight`/`synthWave84Glow`, and suffered stale dark-mode detection when `NSApp.appearance != nil`.
4. **Local Shell Scope Redundancy**: An in-app local `$SHELL` view duplicated iTerm2/Terminal.app workflows and displaced v0.1's `terminal.fill` remote shell icon.
5. **Transfer Speed Jitter & Folder Fidelity**: `libcurl` resume callbacks emitting transient `total=0` totals caused speedometer spikes, SFTP 32 KB block windows underutilized high-latency links, upload resume blocked at `checkpoint.bytesTransferred > 0`, and recursive folder transfers dropped POSIX mode bits (`& 0o777`) and hidden dotfiles.

## Decision

1. **Per-Window State & AppKit Chrome (`src/App/`, `src/Features/Dashboard/`)**:
   - Isolate each window's coordinator via `AppEnvironment.makeWindowState()` + `FocusedValues`, coordinate tab actions via `AppState+WorkspaceTabs` + `AppState+NavigationAndShortcuts`, render the tab strip with `WorkspaceTabStripRepresentable` (`.layoutPriority(-1)`) + native AppKit `TabBarActionButton`, and hide both `QuickConnectBar` and `quickConnectToggleButton` whenever `appState.currentSession != nil`.
2. **Unified Window Configurator & Scoped Shortcuts (`SparkleWindowConfigurator`, `SparkleSFTPApp`, `FilePaneTableView`)**:
   - Apply `[.titled, .closable, .miniaturizable, .resizable]`, `.fullScreenPrimary`, visible traffic-light buttons, `NSAppearance`, and `NSWindow.backgroundColor` through `SparkleWindowConfigurator` across Main, About, Preferences, and Editor windows.
   - Replace global `\t` and duplicate `⇧⌘N` handlers with `⌘W`, `⌘⇧[`/`⌘⇧]`, `⌘\`, single `.sparkleRequestNewFolder`, table-scoped `Tab` pane switching (`FilePaneTableView` `coordinator` notification observer), and `validateUserInterfaceItem`/`performKeyEquivalent` responders.
3. **76-Palette / 26-Family Theme Catalog & Terminal Focus (`src/Packages/DesignSystem/`, `Terminal/`)**:
   - Partition 76 WCAG 2.1 AA contrast-validated palettes across `ThemeCatalogCore`, `ThemeCatalogExtended`, `ThemeCatalogSpectrum`, and `ThemeCatalogStudio`; add search and `All`/`Light`/`Dark` tone filters in `PreferencesThemeTab` + 26 grouped family submenus in `MainWindowView`; remove `Local Shell` (`openLocalShellTab`, `LocalShellTerminalRepresentable`, `⌘⇧L`) and restore `terminal.fill`.
4. **Speedometer, 64 KB Pipelined SFTP & Recursive Permission Preservation (`TransferSpeedMeter`, `SFTPService*`, `TransferQueue*`, `AppState+TransferHelpers`)**:
   - Introduce `NSLock`-protected EWMA `TransferSpeedMeter` across SFTP/SCP/FTP (`CurlClientHelper` filtering `activeNow == 0 && rawTotal == 0`), increase SFTP block size to `64 KB` with sliding window `min(32, max(2, pipelineDepth * 4))`, preserve POSIX permissions (`& 0o777`), include hidden dotfiles (`showHidden: true`) with symlink cycle protection and merge-safe `ensureRemoteDirectory` (`0o700` write guard), fix upload resume (`resolveUploadResumeOffset`), and debounce pane auto-refresh after completion.

## Consequences

- Verified locally (`81 tests in 22 suites`, `0` SwiftLint/SwiftFormat/Trunk/Markdownlint/C11 issues across `155` Swift files) and on GitHub Actions (`CI`, `MegaLinter`, `CodeQL`, `Deploy Jekyll` passing on `main`).
- Residual release (`TD-03` inside-out signing + Sandbox XPC exceptions + Ed25519 appcast) and architecture (`TD-01` `AppState` decomposition, `TD-02` Docker interop) items remain tracked cleanly in [`docs/LONG_TERM_REVIEW_2026_11.md`](../LONG_TERM_REVIEW_2026_11.md).
