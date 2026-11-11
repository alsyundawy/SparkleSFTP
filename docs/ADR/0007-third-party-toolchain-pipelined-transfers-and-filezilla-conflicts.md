# ADR-007: Third-Party Toolchain Bridge, Pipelined Multi-Thread Transfers & FileZilla Conflict Flow

## Status

Accepted

## Date

2026-11-11

## Context

Following Milestone 7 UX hardening, SparkleSFTP needed four production capabilities while preserving **macOS 13+ deployment**, **Swift 6 strict concurrency**, **Universal 2 (`arm64` + `x86_64`) portability**, and **GitHub Actions `macos-15` CI compatibility**:

1. **Third-Party Libraries & External Terminals (`libcurl`, `zlib`, `libssh2`, `OpenSSL`, `OpenSSH`, `SHELL`, `iTerm2`)**:
   - Hard-linking Homebrew-only libraries (`-lssh2`) in `Package.swift` breaks CI runners (`macos-15`) and end-user Universal 2 `.app` bundles that lack `/usr/local/opt/libssh2`.
   - `zlib` is guaranteed in macOS SDK (`/usr/lib/libz.tbd`) and strengthens streaming compression (`CWE-409` bounded decompression).
   - `CurlClientHelper` previously executed synchronous `curl_easy_perform` with default buffers directly without dedicated worker tuning or TCP keepalive defaults.
   - Users wanted both in-app interactive local shells (`$SHELL`) and quick launching into external OpenSSH / iTerm2 / Terminal.app sessions cleanly without shell-injection exposure (`CWE-78`).
2. **Multi-Thread Pipelined Uploads & Downloads**:
   - Sequential chunk-by-chunk SFTP `READ`/`WRITE` serialized network RTT across every 32 KB block.
   - Actor-isolated helper loops inside `SFTPService` trigger Swift 6 `#SendingRisksDataRace` diagnostics if nested closures capture mutable sliding-window state.
3. **FileZilla-Style Target Conflict Overwrite Flow & Language Switcher Layout**:
   - Real multi-thread queues hit multiple target file collisions simultaneously and require FileZilla's full action set (`Overwrite`, `Overwrite if source newer`, `Overwrite if different size`, `Overwrite if different size or newer`, `Resume`, `Rename`, `Skip`), per-queue/direction checkboxes, and serialized FIFO modal prompting without overwriting concurrent user choices.
   - Preferences language selection benefited from clickable locale cards alongside toolbar/status bar/menu quick switching.

## Decision

1. **Portable C11 `Clibcurl` & `ToolchainInspector` (`Packages/Clibcurl`, `Packages/Networking/ZlibAndLibraryProbes.swift`)**:
   - Link `-lz` alongside `-lcurl` in `Package.swift` for `ClibcurlSystemLibs.c`, exposing bounded `zlib`/`gzip` streaming (`ZlibCompressionCodec` enforcing `maxOutputBytes`) and `curl_version_info` capability probes.
   - Probe optional Homebrew `libssh2` safely at runtime via `dlopen`/`dlsym` (`sparklesftp_probe_libssh2`) instead of link-time coupling; probe OpenSSH/OpenSSL/shells/iTerm2 asynchronously (skipping subprocess probes automatically under App Sandbox).
   - Optimize `CurlClientHelper` with 256 KB buffers (`CURLOPT_BUFFERSIZE`, `CURLOPT_UPLOAD_BUFFERSIZE`), `TCP_NODELAY`, `TCP_KEEPALIVE`, and `runOffCooperativePool` GCD worker dispatch.
   - Add `LocalShellTerminalRepresentable` (`SwiftTerm.LocalProcessTerminalView`) + `CWE-78`-validated `ExternalTerminalLauncher` (`ssh://` URL under App Sandbox, `0o700` single-quoted OpenSSH launcher script outside sandbox), surfaced in Preferences and the 7th About tab (`Libraries`).
2. **Actor-Free Pipelined SFTP Windows (`SFTPPipelinedTransfer`, `TransferScheduler`)**:
   - Move sliding-window `withThrowingTaskGroup` loops into `nonisolated` `SFTPPipelinedTransfer` (`inFlightWindow = min(16, max(1, pipelineDepth)) * 2`) with sequential commit buffers + short-read gap recovery on download and locked `UploadChunkCursor` offsets on upload.
   - Increase default `TransferScheduler` limits to `4` global (`1...16`) / `3` per-host (`1...8`) and default `SFTPService` pipeline depth to `8` (`1...16`).
3. **FileZilla Conflict Dialog & FIFO Serialized Queue (`ConflictResolutionSheet`, `ConflictResolver`, `AppState`)**:
   - Expand `TransferConflictPolicy` (8 cases), `TransferConflictResolution` (including `.resume`), and `TransferConflictScope` (`.all`, `.uploadsOnly`, `.downloadsOnly`), with SFTP overwrite delete-retry rename fallback (`TransferQueue+ConflictHelpers`).
   - Serialize concurrent `AppState.promptConflictResolution` calls via FIFO `pendingConflictQueue` with automatic sticky-rule drain once a queue/direction rule is checked.
4. **Card-Grid + Toolbar/Menu Language Switcher (`PreferencesLocalizationTab`, `MainWindowView`, `SparkleSFTPApp`)**:
   - Pair clickable `LocaleDocument` cards (displaying coverage % and key counts) with toolbar/status-bar Globe menus, `⌘`-menu items, and a synchronized 309-key `en.json` / `id.json` catalog.

## Consequences

- Universal 2 `.app` builds stay self-contained using macOS SDK `libcurl` + `libz` while leveraging Homebrew `libssh2`/`OpenSSL`/`OpenSSH`/`iTerm2` whenever present.
- Pipelined 512 KB multi-chunk loopback SFTP upload/download verified in `0.211s` with SHA-256 parity and zero Swift 6 data-race warnings.
- Concurrent multi-thread transfer conflicts never drop or race modal prompts.
