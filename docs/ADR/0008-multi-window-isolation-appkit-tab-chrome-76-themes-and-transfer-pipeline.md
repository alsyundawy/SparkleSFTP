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
   - Isolate each window's coordinator via `AppEnvironment.makeWindowState()` + `FocusedValues`, bind each workspace tab 1-to-1 with its own single remote `TerminalTabSession` (`workspaceTabID` + `remoteSessionID`, removing multi-tab/split terminal chrome and `preferredShellPath`), coordinate tab actions via `AppState+WorkspaceTabs` + `AppState+NavigationAndShortcuts`, render the tab strip with `WorkspaceTabStripRepresentable` (`.layoutPriority(-1)`) + native AppKit `TabBarActionButton`, and show `QuickConnectBar`, `quickConnectToggleButton`, and toolbar `Connect` strictly when `appState.isQuickConnectAvailable` (unconnected tabs/windows only).
2. **Unified Window Configurator, Card-Grid Themes & Scoped Shortcuts (`SparkleWindowConfigurator`, `PreferencesThemeTab`, `SparkleSFTPApp`, `FilePaneTableView`, `ConnectionTableView`)**:
   - Apply `[.titled, .closable, .miniaturizable, .resizable]`, `.fullScreenPrimary`, unrestricted `maxSize`, visible traffic-light buttons, `NSAppearance`, and `NSWindow.backgroundColor` via lock-safe `WindowObserverBox` (`didBecomeKeyNotification` / `didUpdateNotification` + next-runloop pass) across Main, About, Preferences, and Editor (`sparkle.editor`) windows.
   - Replace global `\t` and duplicate `⇧⌘N` handlers with `⌘W` (`hostWindow` + `sparkle.editor` multi-tab handling), `⌘⇧[`/`⌘⇧]`, `⌘\`, `⌘⇧S` Synchronize menu action (`AppState.isShowingSyncSheet`), `F7`/`⌘⇧C`/`⌘⌥C`/`⌘↩`/`⌥↩` + exact modifier equality + `NSText`-safe focus guards in `InteractiveFileTableView` & `InteractiveConnectionTableView`, and `validateUserInterfaceItem`/`performKeyEquivalent` responders.
3. **76-Palette / 26-Family Theme Card Grid & Terminal Focus (`src/Packages/DesignSystem/`, `PreferencesThemeTab`, `Terminal/`)**:
   - Partition 76 WCAG 2.1 AA contrast-validated palettes across `ThemeCatalogCore`, `ThemeCatalogExtended`, `ThemeCatalogSpectrum`, and `ThemeCatalogStudio`; render a Live Active Theme Preview card + filter bar + responsive `LazyVGrid` clickable cards (`ThemePaletteCard`) in `PreferencesThemeTab` + 26 grouped family submenus in `MainWindowView`; remove `Local Shell` (`openLocalShellTab`, `LocalShellTerminalRepresentable`, `⌘⇧L`, `preferredShellPath`) and restore `terminal.fill`.
4. **Speedometer, Ordered 64 KB Pipelined SFTP, Reentrancy Hardening & Bottom-Up Folder POSIX Permissions (`TransferSpeedMeter`, `SFTPChannelBridge`, `SFTPService*`, `TransferQueue*`, `AppState+TransferHelpers`, `AppState+NavigationAndShortcuts`, `RemoteFileModels`)**:
   - Introduce stall-decaying `TransferSpeedMeter` (`0.01s` start floor, `>= 0.4s` decay, `>= 2.0s` zeroing + `CurlClientHelper` `total=0` filtering), increase SFTP block size to `64 KB` with sequential `submitPacket`/`awaitPacket` ordering and contiguous ACK tracking, sequence/reentrancy-guard `TransferQueue.handleProgress` (`ProgressSequenceBox` + post-await status verification + `reconcilePausedCheckpoint`), support `100%` remote `.part` upload resume & Conflict `.skip` zero-byte cleanup, enforce `0o755` directory permission defaults across `RemoteFile`/`SFTPService`/`FTPListingParser`, keep `(mode | 0o700)` while child tasks run and restore exact `mode & 0o777` bottom-up (`PendingFolderPermissionJob`), and debounce pane auto-refresh.

## Consequences

- Verified locally (`91 tests in 24 suites`, `0` SwiftLint/SwiftFormat/Trunk/Markdownlint/C11 issues across `157` Swift files / `31,031` LOC and `365` synchronized EN/ID keys) and on GitHub Actions (`CI`, `MegaLinter`, `CodeQL`, `Deploy Jekyll` passing on `main`).
- Residual release (`TD-03` inside-out signing + Sandbox XPC exceptions + Ed25519 appcast) and architecture (`TD-01` `AppState` decomposition, `TD-02` Docker interop) items remain tracked cleanly in [`docs/LONG_TERM_REVIEW_2026_11.md`](../LONG_TERM_REVIEW_2026_11.md).
