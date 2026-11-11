# Implementation Plan: SparkleSFTP Full MVP

> **Spec:** [`docs/TECHNICAL_SPECIFICATION.md`](../docs/TECHNICAL_SPECIFICATION.md) · [`docs/SECURITY_MODEL.md`](../docs/SECURITY_MODEL.md) · [`docs/WORKGROUND.md`](../docs/WORKGROUND.md)

## Overview

Build the complete initial Swift 6 SwiftPM repository implementation of **SparkleSFTP** targeting **macOS 13+** (`SwiftUI + AppKit`), open-source MIT distribution, with zero placeholder stubs and empirically verified dependency APIs (`apple/swift-nio-ssh 0.15.1`, `SwiftTerm 1.19.0`, `Sparkle 2.10.1`, system `libcurl` via `Clibcurl`, `Security.framework`, and macOS `SQLite3`).

## Architecture Decisions

- **Direct `NIOSSH` + Native SFTP v3 Engine** ([ADR-004](../docs/ADR/0004-direct-swift-nio-ssh-and-sftp-codec.md)): Avoids `Citadel` `.macOS(.v14)` floor and `0.3.x` forks; guarantees CVE-2026-43798 patch (`>= 0.14.1`).
- **macOS 13+ Native Persistence & Observation** ([ADR-005](../docs/ADR/0005-macos13-sqlite3-journal-and-observable-object.md)): Uses native `Security.framework` Keychain, `SQLite3` WAL `TransferJournal`, atomic JSON `ConnectionStore`, and `@MainActor` `ObservableObject` ViewModels.
- **Strict Acyclic Module Graph**: `Package.swift` isolates `SparkleCore`, `SparkleSecurity`, `SparklePersistence`, `SparkleNetworking`, `SparkleTransferEngine`, `SparkleFileManager`, `SparkleTerminal`, `SparkleSynchronization`, `SparkleDesignSystem`, `SparkleFeatures`, and `SparkleSFTP`.

## Global Constraints

- Target: `.macOS(.v13)` minimum, Swift 6 strict concurrency (`swift-tools-version: 6.0`).
- No `acceptAnyHostKey` / `acceptAnything`, no `kSecAttrAccessibleAfterFirstUnlock` or non-`ThisDeviceOnly` Keychain items, no secrets in `OSLog` or JSON/SQLite.
- Zero `fatalError("TODO")` or unverified dependency calls.

## Execution Order & Checkpoints

1. **M1 (`T-001`–`T-005`)**: Manifest, `Clibcurl`, `SparkleCore`, `SparkleDesignSystem` → **Checkpoint:** `swift package resolve` & `CoreTests` pass.
2. **M2 (`T-006`–`T-008`)**: `SparkleSecurity`, `SparklePersistence` → **Checkpoint:** `SecurityTests` & `PersistenceTests` pass.
3. **M3 (`T-009`–`T-012`)**: `SparkleNetworking` (SSH, SFTP, SCP, FTP/FTPS) → **Checkpoint:** `NetworkingTests` pass.
4. **M4 (`T-013`–`T-016`)**: `SparkleTransferEngine`, `SparkleFileManager`, `SparkleSynchronization` → **Checkpoint:** `TransferEngineTests`, `FileManagerTests`, `SynchronizationTests` pass.
5. **M5 (`T-017`–`T-020`)**: `SparkleTerminal`, `SparkleFeatures`, `App/` → **Checkpoint:** `IntegrationTests` & `swift build` executable pass.
6. **M6 (`T-021`–`T-024`)**: `Tools/`, `.github/workflows/release.yml`, docs reconciliation, `CHANGELOG.md` → **Checkpoint:** Full MVP verified.
7. **M7 (`T-025`–`T-033`)**: SparkNotePad Multi-Themes (`28` palettes) + Full Workspace Theme Propagation (`sparkleWorkspaceSurface`, `TerminalThemeColors`, AppKit tables, `NSApp.windows`), SparkNotePad-style 7-tab About window (incl. `Libraries`) & 1:1 pastel-yellow/blue/white `AppIcon`, Auto-Update Preferences & fallback check, JSON i18n maintenance (`309` keys), FileZilla/WinSCP preview importer, Minimalist Notepad2 Internal Editor, Bidirectional Sync (`TASK-108`), Remember Password Keychain flow (`ConnectionEditorView`, `CredentialPromptSheet`, `FTPService`), Native AppKit `ConnectionListTableView` + `InteractiveFileTableView` mouse/keyboard navigation, Fast Exit (`applicationShouldTerminate` + bounded parallel NIO shutdown), Runtime Performance Tuning & `.clangd`/`.clang-format` C11 hygiene.
8. **M8 (`T-034`)**: Third-Party Toolchain Bridge & Optimization (`Clibcurl` `-lz` bounded `zlib`/`gzip`, `256 KB` `TCP_NODELAY`/`TCP_KEEPALIVE` + GCD off-cooperative `libcurl` workers, dynamic `dlopen` `libssh2` probe, `OpenSSL`/`OpenSSH`/POSIX shell detection, `LocalShellTerminalRepresentable`, sanitized `ExternalTerminalLauncher` for iTerm2/Terminal), Multi-Thread Pipelined SFTP (`SFTPPipelinedTransfer` `8x` window + `TransferScheduler` `4` global / `3` per-host defaults), FileZilla-style Conflict Overwrite Sheet + FIFO Serialized `pendingConflictQueue`, and Card-Grid + Toolbar/Menu Language Switcher — **Checkpoint:** `71 tests in 18 suites` + SwiftLint (`0/135`) + SwiftFormat (`0/135`) + Markdownlint + YAMLlint + ShellCheck + Clang/Cppcheck + Actionlint exit `0`.
