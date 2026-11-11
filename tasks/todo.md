# Task Execution Checklist (`tasks/todo.md`)

Tracks active execution of [`tasks/plan.md`](plan.md) and [`docs/TASK_LIST.md`](../docs/TASK_LIST.md).

## Milestone 1: Foundation (`T-001` – `T-005`)

- [x] `T-001` Write `Package.swift` (`.macOS(.v13)`, Swift 6, verified dependency pins)
- [x] `T-002` Implement `Packages/Clibcurl` C helper wrapper
- [x] `T-003` Implement `Packages/Core` domain contracts & models
- [x] `T-004` Implement `Packages/DesignSystem` theme, components & EN/ID strings
- [x] `T-005` Add & pass `Tests/CoreTests`

## Milestone 2: Security & Persistence (`T-006` – `T-008`)

- [x] `T-006` Implement `Packages/Security`
- [x] `T-007` Implement `Packages/Persistence`
- [x] `T-008` Add & pass `Tests/SecurityTests` and `Tests/PersistenceTests`

## Milestone 3: Networking (`T-009` – `T-012`)

- [x] `T-009` Implement `SFTPPacketCodec` & `SSHClientService`
- [x] `T-010` Implement `SFTPService` & `SCPCompatibilityAdapter`
- [x] `T-011` Implement `FTPService`, `FTPListingParser`, `RemoteServiceFactory`
- [x] `T-012` Add & pass `Tests/NetworkingTests`

## Milestone 4: Transfer Engine, FileManager & Sync (`T-013` – `T-016`)

- [x] `T-013` Implement `Packages/TransferEngine`
- [x] `T-014` Implement `Packages/FileManager`
- [x] `T-015` Implement `Packages/Synchronization`
- [x] `T-016` Add & pass `TransferEngineTests`, `FileManagerTests`, `SynchronizationTests`

## Milestone 5: Terminal, Features & App (`T-017` – `T-020`)

- [x] `T-017` Implement `Packages/Terminal`
- [x] `T-018` Implement `Features/` (SwiftUI + AppKit `FilePaneTableView` + `QuickLookCoordinator`)
- [x] `T-019` Implement `App/` executable + entitlements + `Info.plist` + `SparkleUpdaterService`
- [x] `T-020` Add & pass `Tests/IntegrationTests`

## Milestone 6: Tooling, Docs Sync & Full Gate (`T-021` – `T-023`)

- [x] `T-021` Create `Tools/TestServers/` & `Tools/Release/` scripts
- [x] `T-022` Reconcile `README.md`, `README-id.md`, `docs/*.md`, `CHANGELOG.md`, `TODO.md`
- [x] `T-023` Run full build, tests (`57 tests in 15 suites`), SwiftLint (`118` files), SwiftFormat (`0/118`), YAMLlint, ShellCheck, Shfmt, Markdownlint, Actionlint
- [x] `T-024` Build and verify Universal 2 (`x86_64 arm64`) `.app` + `SparkleSFTP-0.2.0-universal.dmg` + `.sha256` via `Tools/Release/build-universal.sh`, `create-dmg.sh`, and `.github/workflows/release.yml`

## Milestone 7: Post-MVP Quality-of-Life & Editor Enhancements (`T-025` – `T-030`)

- [x] `T-025` Multi-theme engine (`SparkleThemePalette`, `28` themes / `15` families inspired by SparkNotePad, WCAG AA contrast, JSON import/export)
- [x] `T-026` Maintainable JSON i18n system (`en.json` & `id.json` `263` keys, custom `Locales/` override directory, Preferences coverage inspector)
- [x] `T-027` Full Auto-Update Preferences & community GitHub Releases API fallback check (`AutoUpdateSettings`, `PreferencesUpdatesTab`)
- [x] `T-028` Enhanced FileZilla XML & WinSCP INI reader + `ImportConnectionsSheet` preview importer (BOM/UTF-16, nested folders, `FSProtocol`, `.ini` `UTType`)
- [x] `T-029` Minimalist Notepad2 Internal File Editor (`Features/Editor/`, multi-tab `NSTextView` + line numbers + regex syntax/find/transforms/encodings + remote upload)
- [x] `T-030` Bidirectional & Reverse Folder Synchronization (`TASK-108` across `SyncPlanner`, `SyncExecutor`, `SyncPreviewSheet`, `BidirectionalSyncTests`, `EditorAndSyncTests`)

## External Operational & Release Gates (Deferred to Release Environment)

- [ ] Execute live Docker integration test suite (`Tools/TestServers/run-integration-tests.sh`; Docker not installed locally)
- [ ] Execute Apple Developer ID notarization & stapling (`Tools/Release/notarize.sh`) with production signing credentials
