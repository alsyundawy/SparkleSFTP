# SparkleSFTP — Post-Completion Long-Term Architecture, Security & Sustainability Review

- **Review Date:** 2026-11-11
- **Reviewed Baseline:** Repository `main` at commit `1b9d9f4` (`135` Swift files, `2` C11 sources + `1` header in `Packages/Clibcurl`, `309` synchronized EN/ID JSON keys, `28` themes / `15` families, `7` About tabs, `71` tests across `18` Swift Testing suites)
- **Target Platform & Toolchain:** `macOS 13.0+` (`.macOS(.v13)`), Swift 6 (`swiftLanguageModes: [.v6]`, `swift-tools-version: 6.0`)
- **Review Methodology:** All **14 Engineering Review Pillars** ([`CODE_REVIEW_14_PILLARS.md`](CODE_REVIEW_14_PILLARS.md)) and **14 macOS Platform Engineering Skills**, backed by full post-release linter sweeps, live GitHub Actions verification (`CI` `42956153517`, `MegaLinter` `42956153551`, `CodeQL Advanced` `42956153525`, `Deploy Jekyll` `42956153542`), `swift test -j 2` runs (`0.833s`), direct source inspection, and authoritative web research.

---

## (a) Executive Summary of Architectural Health

**Overall Verdict: Strong Production Core (`A-` Security & Concurrency Foundation, `B+` Long-Term Maintainability with Tracked Multi-Month Debt)**

SparkleSFTP maintains a clean, modular Swift 6 architecture across all 10 domain/adapter targets and top-level `Features/` and `App/` composition layers:

- **Strict Acyclic Layering Holds (`Package.swift`):** `SparkleCore` imports only `Foundation`; `SparkleTransferEngine` communicates with networking and persistence purely through `RemoteFileSystem` closures and `TransferJournalProtocol` without importing `SparkleNetworking` or `SparklePersistence` (`CIRC-001`), and zero `Packages/*` targets import `SparkleFeatures` (`CIRC-002`).
- **Third-Party Toolchain & Concurrency Discipline Improved in Commit `1b9d9f4`:**
  - `Packages/Clibcurl` safely links macOS SDK `-lcurl` and `-lz` (`ClibcurlSystemLibs.c`) with `256 KB` buffers + `TCP_NODELAY`/`TCP_KEEPALIVE`, off-cooperative GCD worker dispatch (`CurlClientHelper.runOffCooperativePool`), `CWE-409`-bounded `zlib`/`gzip` decompression (`ZlibCompressionCodec`), and portable runtime `dlopen`/`dlsym` probing for optional Homebrew `libssh2` (`sparklesftp_probe_libssh2`) rather than fragile link-time `-lssh2`.
  - SFTP multi-chunk streaming uses actor-free `nonisolated` `SFTPPipelinedTransfer` (`withThrowingTaskGroup` sliding windows on `32 KB` blocks) without `#SendingRisksDataRace` or per-chunk actor hops, paired with FileZilla-style conflict overwrite controls (`ConflictResolutionSheet`) and FIFO serialized `AppState.pendingConflictQueue`.
- **Resolved Early Bottlenecks vs Remaining Structural Debt:** Prior performance fixes eliminated per-render `AppStrings` reconstruction (cached in `AppState.strings`/`activePalette`), isolated 10Hz transfer ticks in `TransferMonitor`, throttled active SQLite progress writes to `>= 2.0s` / state changes (`TransferQueue+Checkpoint.swift`), replaced deadlocking `@MainActor` quit semaphores with `applicationShouldTerminate`, and fixed `.app` resource bundle `Bundle.module` crashes. Remaining structural debt centers on:
  1. `AppState` remaining a broad `@MainActor ObservableObject` (`Features/AppState.swift`) and `FilePaneTableView.updateNSView` performing `O(N)` equality + full `tableView.reloadData()`.
  2. Live Docker multi-server regression fixtures (`Tools/TestServers/`) remaining unwired (`SPARKLESFTP_LIVE_DOCKER_TESTS=1` unused) with floating `:latest` tags and missing FTPS TLS container certs.
  3. Release signing/appcast automation incomplete (`Info.plist:34` placeholder `SUPublicEDKey`, `codesign --deep` instead of inside-out Sparkle XPC signing, no `generate_appcast` CI step or Ed25519 key-rotation runbook).
  4. **Explicit SonarQube Gap:** `swiftlint lint --reporter sonarqube` emits valid SonarQube JSON (`0` issues), **but** SonarQube / SonarCloud is not configured in the repository (`sonar-project.properties` absent and `.mega-linter.yml` does not pass `SWIFT_SWIFTLINT_ARGUMENTS: "--reporter sonarqube"`).

---

## (b) Per-Release Linter Sweep & 14-Pillar Findings

### Post-Release Linter & CI Verification Results (Commit `1b9d9f4`)

| Tool / Gate | Scope | Command / Config | Empirical Result |
| :--- | :--- | :--- | :--- |
| **SwiftLint (`--strict`)** | `135` Swift files (`Package.swift`, `App/`, `Packages/`, `Features/`, `Tests/`) | `swiftlint lint --strict` (`.swiftlint.yml`) | `0` violations, `0` serious |
| **SwiftFormat** | `135` Swift files | `swiftformat --lint .` (`.swiftformat`) | `0/135` files require formatting (`27` excluded/skipped) |
| **MegaLinter v10** | Repo-wide (`SWIFT_SWIFTLINT`, `C_CPPCHECK`, `C_CLANG_FORMAT`, `BASH_*`, `MARKDOWN_*`, `YAML_*`, `JSON_*`, `XML_*`, `ACTION_*`, `BETTERLEAKS`) | `.mega-linter.yml` / `.github/workflows/mega-linter.yml` (Run `42956153551`) | **Pass (`success`)** on `ubuntu-latest` |
| **SwiftLint SonarQube Reporter** | All Swift sources | `swiftlint lint --reporter sonarqube --quiet` | `sonarqube_issues=0` (valid JSON) |
| **SonarQube Server / Scanner** | Repository root & CI | Check `sonar-project.properties` & `.mega-linter.yml` | **Not Configured (Explicit Gap `TD-08`)** |
| **MarkdownLint** | `27` Markdown files (`*.md`, `docs/`, `tasks/`) | `npx --yes markdownlint-cli2 "**/*.md" ...` (`.markdownlint.json`) | `0` issues in `0` files |
| **YAMLlint & Actionlint** | Workflows, Docker Compose, linter YAML configs | `yamllint -c .yamllint.yml . .clangd .clang-format` + `actionlint` | `0` issues (exit `0`) |
| **ShellCheck & Shfmt** | `Tools/Release/*.sh`, `Tools/TestServers/*.sh` | `shellcheck -s bash` + `shfmt -d -i 2 -ci` | `0` issues across all 4 scripts |
| **Clibcurl C11 Hygiene** | `ClibcurlHelpers.c`, `ClibcurlSystemLibs.c`, `Clibcurl.h` | `cppcheck --check-level=exhaustive`, `clang-format --dry-run --Werror`, `clang -fsyntax-only -Wall -Wextra -Werror -std=c11` | `0` errors / formatting issues |
| **JSON & XML Checks** | Locales JSON (`309` EN / `309` ID keys), `Package.resolved`, `Info.plist`, entitlements | `python3 -m json.tool`, `xmllint --noout` | `0` syntax errors, `0` key drift |
| **Swift Testing Suite** | `8` test targets (unit + live loopback SSH/SFTP) | `nice -n 10 swift test -j 2 --disable-xctest --enable-swift-testing` | **71 tests in 18 suites passed (`0.833s`)** |
| **GitHub Actions CI & Security** | Commit `1b9d9f4` workflows | `CI` (`42956153517`), `CodeQL Advanced` (`42956153525`), `Deploy Jekyll` (`42956153542`) | **All 4 workflows completed `success`** |

### Per-Pillar Assessment (All 14 Pillars)

| # | Pillar | Severity | Empirical Findings & Citations |
| :--- | :--- | :--- | :--- |
| **1** | **Bug Review** | **Medium** | **Fixed:** `Bundle.module` crash in `LocalizationCatalog`/`AppDelegate` & BOM/folder parser edge cases. **Open (`TD-05`, `TD-10`):** `TransferJournal.reconcileInterruptedOnLaunch` (`TransferJournal.swift:125`) skips `.queued` and `.paused` rows on crash recovery; `FTPService.connect` does not populate `lastVerifiedCertificate` on `.ftpsExplicit` (`FTPService.swift:45-50`). |
| **2** | **Syntax Review** | **Low (Pass)** | Zero syntax errors or compiler warnings under `swiftLanguageModes: [.v6]` and C11 (`-Wall -Wextra -Werror`) locally and on `macos-15` Xcode CI runners. |
| **3** | **Runtime Review** | **Medium** | `MainWindowView.swift:34-37` (`if appState.isTerminalVisible`) destroys/recreates `TerminalView`, wiping scrollback history; `SCPCompatibilityAdapter.download` (`SCPCompatibilityAdapter.swift:97-140`) buffers full remote payloads (plain or gzip-base64) in memory (`TD-06`); `TransferJournal` creation in `AppState` swallows DB errors via `try?` without quarantine (`TD-05`). |
| **4** | **Logic Review** | **Medium** | TOFU 6-state machine, FIFO `pendingConflictQueue`, FileZilla policies, and FileZilla/WinSCP BOM importers are verified green. **Open:** `TransferQueue.runWithRetry` (`TransferQueue+Execution.swift:43`) uses unjittered `1 << (attempt - 1)` delays (`TD-12`); `SparkleUpdaterService.applySettings` (`SparkleUpdaterService.swift:58-65`) does not forward `AutoUpdateSettings.customFeedURL` to `SPUUpdater` (`TD-03`). |
| **5** | **Memory & Concurrency** | **Medium** | All `17` production + `5` test `@unchecked Sendable` boxes document `// JUSTIFICATION:` and lock/EventLoop confinement; `CurlClientHelper` isolates blocking C calls on `workerQueue` (`runOffCooperativePool`), and `SFTPPipelinedTransfer` avoids actor-isolated captures. **Open:** `TerminalViewRepresentable.swift:126` & `ExternalTerminalLauncher.swift:84` still use `DispatchQueue.main.async { MainActor.assumeIsolated ... }`, and `TerminalSessionManager.attachPTYChannel` dispatches raw stdout chunks without 16ms frame coalescing (`TD-07`, `TD-14`). |
| **6** | **Dead Code Review** | **Low** | `FeatureFlags` (`Packages/Core/FeatureFlags.swift:4-35`) wires `isSyncEnabled` (`MainWindowView.swift:96`) and `isTouchIDGateEnabled` (`AppState+Connections.swift:249`), leaving `isSCPFallbackEnabled` and `isPortForwardingEnabled` unwired (`TD-09`). |
| **7** | **Duplicate Code Review** | **Low** | Repeated `(error as? AppError) ?? .transferFailed(...)` catch assignments across `AppState+Connections/Operations/Imports/TransferHelpers.swift` and `DispatchQueue.main.async { MainActor.assumeIsolated ... }` duplication in `TerminalViewRepresentable.swift` and `ExternalTerminalLauncher.swift`. |
| **8** | **Circular Dependency** | **Pass (`0` Issues)** | Verified acyclic module graph in `Package.swift`; strict separation between `SparkleTransferEngine`, `SparkleNetworking`, `SparklePersistence`, and `Features/`. |
| **9** | **Performance Bottlenecks** | **Medium–High** | 10Hz ticks isolated in `TransferMonitor`, `strings`/`activePalette` cached (`AppState.swift:177-178`), SQLite writes throttled to `>= 2.0s` (`TransferQueue+Checkpoint.swift:71-85`), static formatters/SF Symbols cached. **Open:** `AppState` still acts as a multi-domain `ObservableObject` (`TD-01`), `FilePaneTableView.updateNSView` (`FilePaneTableView.swift:167-174`) runs `O(N)` `cachedFiles != files` + full `tableView.reloadData()` (`TD-04`), and `DualPaneCommanderView.swift:156` copies `Array(visibleFiles)`. |
| **10** | **Security Vulnerabilities** | **Medium** | **CVE-2026-43798** (`swift-nio-ssh 0.15.1`), **CVE-2025-15224** (`ftp,ftps` protocol lock), **CWE-312/522**, **CWE-409**, **CWE-78**, **CWE-93**, **CWE-22/59**, **CWE-532** mitigated. **Open Gaps:** Explicit FTPS relies on libcurl defaults rather than `TLSCertificateValidator` (`TD-10`), `HostTrustStore` lacks OpenSSH `~/.ssh/known_hosts` interoperability (`TD-11`), `Info.plist` uses placeholder `SUPublicEDKey` (`TD-03`), `PrivateKeyParser` omits encrypted/RSA keys (`TD-15`), and Keychain lacks an access group if helper XPCs are introduced later. |
| **11** | **Maintainability** | **Medium** | Clean `Protocols.swift` abstractions in `SparkleCore`, yet `AppState` retains direct lifecycle/coordinator wiring across 6 extension files (`TD-01`), and `TransferJournal` lacks `PRAGMA user_version` forward migrations (`TD-05`). |
| **12** | **Scalability** | **Medium** | `TransferScheduler` (`4` global / `3` per-host) & `8x` SFTP chunk pipelining scale multi-file throughput cleanly; `TransferJournal` prunes at `10,000` rows / `30` days. **Open (`TD-13`):** `SFTPService.listDirectory` accumulates all directory entries in memory prior to wrapping in `PaginatedFileWindow`; `SwiftTerm` scrollback limit (`TerminalOptions.scrollback`) is unconfigured. |
| **13** | **Readability** | **Low (Pass)** | Modular extensions (`AppState+*`, `TransferQueue+*`, `AboutView+*`), concise docstrings, `0` SwiftLint length/line violations. **Watch (`TD-08`):** `.swiftlint.yml` retains default `cyclomatic_complexity` (`10`/`20`) instead of `warning: 6`. |
| **14** | **Linter & CI Gate** | **Medium** | All 4 GitHub Actions workflows & local linters pass with `0` warnings/errors across `135` Swift + `3` C + `27` Markdown files. **Explicit Gap (`TD-08`):** SonarQube server integration (`sonar-project.properties` + `SWIFT_SWIFTLINT_ARGUMENTS: "--reporter sonarqube"` in `.mega-linter.yml`) not configured; Docker live tests disabled in CI (`TD-02`). |

---

## (c) Technical Debt Register (Prioritized with Effort & Impact)

| ID | Debt Item | Code Location | Effort | Impact | Recommended Action |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **TD-01** | Single `AppState: ObservableObject` spanning Commander, Connections, Terminal & Settings *(10Hz transfer ticks & `strings`/`activePalette` resolved)* | `Features/AppState.swift` (`L54-L178`) | Large (2–3 wks) | **High** | Decompose into domain stores (`ConnectionStoreVM`, `CommanderPaneStore`, `TerminalCoordinator`, `AppearanceLocaleStore`); adopt `@Observable` when advancing min OS to macOS 14+. |
| **TD-02** | Docker runner exports `SPARKLESFTP_LIVE_DOCKER_TESTS=1` unused; `:latest` tags; missing FTPS TLS certs & SCP container tests | `Tools/TestServers/run-integration-tests.sh`, `docker-compose.test.yml` | Medium (3–5 days) | **High** | Pin immutable container digests, generate disposable FTPS TLS certs/`vsftpd`/`proftpd` configs, seed `known_hosts`, and wire gated `DockerInteropTests`. |
| **TD-03** | Production Ed25519 `SUPublicEDKey` placeholder, `codesign --deep`, missing `generate_appcast` CI step & key-rotation runbook, unused `customFeedURL` in `SPUUpdater` | `App/Resources/Info.plist:34`, `App/SparkleUpdaterService.swift:58-65`, `Tools/Release/notarize.sh:18`, `.github/workflows/release.yml` | Medium (2–4 days) | **High** | Provision Developer ID + Notary + Ed25519 secrets, switch `notarize.sh` to inside-out signing (`Sparkle.framework` XPCs first), wire `generate_appcast` + `customFeedURL`, and document key rotation. |
| **TD-04** | `FilePaneTableView.updateNSView` executes `O(N)` `cachedFiles != files` comparison + full `reloadData()` and `Array(visibleFiles)` copies | `Features/Commander/FilePaneTableView.swift:167-174`, `DualPaneCommanderView.swift:156` | Medium (3–4 days) | **Medium** | Pass generation-stamped slices and apply `CollectionDifference` incremental `insertRows`/`removeRows`/`reloadData(forRowIndexes:)` deltas. |
| **TD-05** | `TransferJournal` lacks `PRAGMA user_version` migrations, `PRAGMA quick_check` corruption quarantine, `.paused`/`.queued` launch restore, & orphan `.part` GC | `Packages/Persistence/TransferJournal.swift:45-48,125`, `Features/AppState+Connections.swift` | Medium (3–4 days) | **Medium** | Add versioned schema migrations, corrupt DB quarantine fallback, `.paused` reconciliation, and periodic cleanup of unreferenced `.sparklesftp.*.part` files. |
| **TD-06** | `SCPCompatibilityAdapter.download` buffers full base64/gzip output in RAM (`CWE-400`); lacks optional `sudo -n` elevation | `Packages/Networking/SCPCompatibilityAdapter.swift:97-140` | Medium (3 days) | **Medium** | Stream SSH stdout chunks incrementally to `FileHandle` (preserving `CWE-409` bounded decompression) and support opt-in non-interactive `sudo -n`. |
| **TD-07** | `TerminalView` destroyed on hide/split toggles (`MainWindowView.swift:34-37`), lacks Find bar, scrollback cap, 16ms burst coalescing, & `Task { @MainActor }` | `MainWindowView.swift:34-37`, `TerminalViewRepresentable.swift:121-130`, `ExternalTerminalLauncher.swift:80-89`, `TerminalSessionManager.swift` | Medium (4 days) | **Medium** | Preserve NSView instances across drawer/split toggles, set `TerminalOptions(scrollback:)`, batch PTY stdout chunks at 16ms, add Find-in-Terminal, and replace `DispatchQueue.main.async`. |
| **TD-08** | SonarQube server/scanner unconfigured (`sonar-project.properties` absent, `.mega-linter.yml` omits `--reporter sonarqube`); `cyclomatic_complexity` at `10`/`20` | `.swiftlint.yml`, `.mega-linter.yml`, root config | Small (1 day) | **Medium** | Set `SWIFT_SWIFTLINT_ARGUMENTS: "--reporter sonarqube"` in `.mega-linter.yml`, add `sonar-project.properties`, and tighten `cyclomatic_complexity` warning threshold to `<= 6`. |
| **TD-09** | Partial dead feature flags (`isSCPFallbackEnabled`, `isPortForwardingEnabled` unwired; `isSyncEnabled` and `isTouchIDGateEnabled` active) | `Packages/Core/FeatureFlags.swift:4-35` | Small (0.5 day) | **Low** | Enforce `isSCPFallbackEnabled` in `RemoteServiceFactory` and `isPortForwardingEnabled` in `TerminalWorkspaceView`, or remove unused flags. |
| **TD-10** | `.ftpsExplicit` omits `TLSCertificateValidator` (`SecTrust` + OCSP) preflight parity; no active FTP (`PORT`/`EPRT`) fallback | `Packages/Networking/FTPService.swift:45-50`, `CurlClientHelper.swift:68-74` | Medium (4 days) | **Medium** | Add STARTTLS `AUTH TLS` `SecTrustEvaluateWithError` + OCSP validation parity and optional active FTP port configuration. |
| **TD-11** | `HostTrustStore` lacks OpenSSH `~/.ssh/known_hosts` import/export (plain & HMAC-SHA1 hashed entries) & future Keychain access-group support | `Packages/Security/HostTrustStore.swift`, `App/SparkleSFTP.entitlements` | Med (2–3 days) | **Low–Med** | Build `KnownHostsCodec` with user-selected security-scoped `~/.ssh/known_hosts` sync while preserving Apple Keychain backing. |
| **TD-12** | Retry backoff lacks jitter *(2s SQLite checkpoint throttle implemented cleanly)* | `Packages/TransferEngine/TransferQueue+Execution.swift:43`, `TransferQueue+Checkpoint.swift:71-85` | Small (0.5 day) | **Low** | Add randomized jitter (`Double.random(in: 0.7...1.3)`) onto exponential backoff delays to prevent multi-host thundering herds. |
| **TD-13** | `SFTPService.listDirectory` buffers full remote entry array before wrapping into `PaginatedFileWindow` | `Packages/Networking/SFTPService.swift` | Medium (3 days) | **Medium** | Stream `READDIR` batches incrementally to UI window slices with bounded memory (`100K+` entries). |
| **TD-14** | Legacy `DispatchQueue` wrappers outside `CurlClientHelper` blocking C pool (`LocalFileService`, `TLSCertificateValidator`, `SSHClientService+Helpers`) | `LocalFileService.swift:10`, `TLSCertificateValidator.swift:69,81`, `SSHClientService+Helpers.swift:210` | Small–Med (2 days) | **Low** | Migrate bounded watchdog & preflight helpers onto Swift `withTaskGroup` / `AsyncStream` cleanly (`CurlClientHelper` concurrent GCD pool retained intentionally for blocking libcurl C FFI). |
| **TD-15** | `PrivateKeyParser` omits passphrase-encrypted OpenSSH (`bcrypt-pbkdf`) & legacy RSA (`RFC 8332`) keys; `build-universal.sh` defaults `SPARKLE_BUILD_JOBS=4` | `Packages/Security/PrivateKeyParser.swift`, `Tools/Release/build-universal.sh:14` | Med (3–4 days) | **Low–Med** | Add OpenSSH encrypted key decryption (`LAContext` passphrase prompt) and update `SPARKLE_BUILD_JOBS:-2` default for thermal safety on laptops. |

---

## (d) Security Findings with CVE / CWE Mapping

| Finding ID | Reference / Standard | Status | Empirical Code Evidence & Assessment |
| :--- | :--- | :--- | :--- |
| **SEC-CVE-1** | **CVE-2026-43798** (`apple/swift-nio-ssh <= 0.14.0` pre-auth oversized ECDSA OOB stack write, CVSS 9.8) | **Mitigated** | [`Package.swift`](../Package.swift) pins `apple/swift-nio-ssh` `"0.15.1" ..< "0.16.0"` (`>= 0.14.1`), verified in `Package.resolved`. |
| **SEC-CVE-2** | **CVE-2025-15224** (`libcurl` `libssh` SSH-agent bypass) | **Mitigated** | [`CurlClientHelper.swift:45`](../Packages/Networking/CurlClientHelper.swift#L45) restricts libcurl via `CURLOPT_PROTOCOLS_STR = "ftp,ftps"`; optional `libssh2` is strictly a read-only `dlopen` version probe (`ClibcurlSystemLibs.c`). |
| **SEC-CWE-312 / 522** | Clear-text storage / insecure credential transmission | **Compliant (Access Group Note)** | [`KeychainService.swift`](../Packages/Security/KeychainService.swift) enforces `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `.userPresence` Touch ID + `LAContext`, and SwiftLint `no_icloud_keychain_sync` (`severity: error`). Cloning profiles issues independent Keychain `SecretReference`s. Future XPC/helper targets will need shared Keychain access groups + legacy delete-before-update migration handling. |
| **SEC-CWE-295** | Improper Certificate Validation (`FTPS`) | **Partial (`TD-10`)** | `TLSCertificateValidator` enforces `SecTrustEvaluateWithError` (`SecPolicyCreateSSL` + `kSecRevocationOCSPMethod`) and `.TLSv12` minimum via `NWProtocolTLS` for `.ftpsImplicit`. `.ftpsExplicit` relies on libcurl `CURLOPT_SSL_VERIFYPEER = 1` / `VERIFYHOST = 2` rather than preflight `SecTrust` callback extraction. |
| **SEC-CWE-300 / 295** | SSH Host Key Verification (TOFU MITM) | **Compliant (`KnownHosts` Gap `TD-11`)** | `HostTrustStore` enforces all 6 states (`unknown`, `pendingUserDecision`, `trusted`, `rejected`, `mismatch`, `corrupted`), hard-blocks `.mismatch`, and `acceptAnyHostKey` is prohibited by SwiftLint. |
| **SEC-CWE-78** | OS Command Injection (`SCP` & External Terminal) | **Compliant** | Both [`SCPCompatibilityAdapter.swift`](../Packages/Networking/SCPCompatibilityAdapter.swift) and [`ExternalTerminalLauncher.swift:115-159`](../Packages/Terminal/ExternalTerminalLauncher.swift#L115-L159) reject `< 0x20` / `0x7F` control characters and escape every argument via POSIX `'\\''` single-quoting; App Sandbox falls back cleanly to RFC `ssh://` URLs. |
| **SEC-CWE-409** | Improper Handling of Highly Compressed Data (Zip Bomb) | **Compliant** | [`ClibcurlSystemLibs.c`](../Packages/Clibcurl/ClibcurlSystemLibs.c) & [`ZlibAndLibraryProbes.swift:64-85`](../Packages/Networking/ZlibAndLibraryProbes.swift#L64-L85) enforce `max_output_bytes` (`64 MB` default cap) and `UINT32_MAX` chunk truncation checks across `.zlib` & `.gzip` streams, verified in [`ToolchainAndConflictTests.swift`](../Tests/IntegrationTests/ToolchainAndConflictTests.swift). |
| **SEC-CWE-93** | CRLF Injection in FTP Control Channel | **Compliant** | `FTPService.sanitizeControlPath` inspects raw UTF-8 bytes (`0x00`, `0x0A`, `0x0D`) rather than Unicode grapheme clusters. |
| **SEC-CWE-22 / 59** | Path Traversal & Symlink Escape | **Compliant** | `PathValidator` canonicalizes paths, rejects pre-existing local destination symlinks, and `DirectoryScanner` detects circular symlinks via `visitedInodes`. |
| **SEC-CWE-494** | Download Without Integrity Verification (Updates) | **Mitigated (Production Key Gap `TD-03`)** | `UpdateConfigurationValidator` blocks non-HTTPS feeds & placeholder `SUPublicEDKey` (`Info.plist:34`), failing closed to read-only TLS GitHub Releases API version lookup until production Ed25519 keys are provisioned. |
| **SEC-CWE-400** | Uncontrolled Resource Consumption | **Open (`TD-06`, `TD-07`, `TD-13`)** | Whole-payload buffering in `SCPCompatibilityAdapter.download`, unconfigured `SwiftTerm` scrollback cap, and full `READDIR` memory accumulation in `SFTPService.listDirectory`. |
| **SEC-CWE-532** | Sensitive Info in Logs | **Compliant** | `DiagnosticsLogger` uses `OSLog` `.private` redaction; SwiftLint `no_password_in_logs` (`severity: error`) reports `0` violations across `135` files. |

---

## (e) Swift 6 Concurrency & SwiftUI Performance Sustainability Assessment

### Swift 6 Strict Concurrency Audit (`swiftLanguageModes: [.v6]`)

- **Isolation & Actor Boundaries:** Protocol services (`SSHClientService`, `SFTPService`, `FTPService`, `SCPCompatibilityAdapter`), transfer orchestration (`TransferQueue`, `TransferScheduler`, `ConflictResolver`), security stores (`HostTrustStore`), and SQLite persistence (`TransferJournal`) are strict actors. UI coordinators (`AppState`, `TransferMonitor`, `TerminalSessionManager`, `EditorSessionManager`, `QuickLookCoordinator`, `SparkleUpdaterService`) are strictly `@MainActor`.
- **Pipelined SFTP Actor Freedom:** [`SFTPServiceHelpers.swift:136-313`](../Packages/Networking/SFTPServiceHelpers.swift#L136-L313) isolates `withThrowingTaskGroup` sliding-window loops inside `nonisolated` `SFTPPipelinedTransfer`, preventing `#SendingRisksDataRace` region-isolation errors and removing per-chunk actor hops across `32 KB` blocks.
- **`@unchecked Sendable` Audit (`17` production + `5` test helpers):** Every production `@unchecked Sendable` (`TransferJournal`, `LocalDirectoryWatcher`, `SFTPChannelBridge`, 4 boxes in `SSHChannelHandlers`, `CurlCancellationToken`, `SSHPTYChannel`, `ShutdownResumeOnceBox`, 2 boxes in `SSHClientService+Forwarding`, `TLSHandshakeBox`, `TunnelRelayHandlers`, `UploadChunkCursor`, `PTYResourceBox`, `PortForwardingManager`) is protected by `NSLock` / NIO `EventLoop` confinement and carries an enforced `// JUSTIFICATION:` comment.
- **`DispatchQueue` Migration Watchlist (`6` source files):**
  - *Intentional C FFI Isolation:* `CurlClientHelper` (`CurlClientHelper.swift:14-32`) offloads synchronous blocking `curl_easy_perform` operations onto a bounded concurrent GCD worker queue (`runOffCooperativePool`) rather than starving Swift's cooperative thread pool.
  - *Recommended Modernizations (`TD-07`, `TD-14`):* Replace `DispatchQueue.main.async { MainActor.assumeIsolated ... }` in [`TerminalViewRepresentable.swift:121-130`](../Packages/Terminal/TerminalViewRepresentable.swift#L121-L130) and [`ExternalTerminalLauncher.swift:80-89`](../Packages/Terminal/ExternalTerminalLauncher.swift#L80-L89) with `Task { @MainActor [weak self] in ... }` to eliminate manual `assumeIsolated` runtime assertions; gradually replace GCD queues in [`TLSCertificateValidator.swift:69,81`](../Packages/Security/TLSCertificateValidator.swift#L69-L81), [`LocalFileService.swift:10`](../Packages/FileManager/LocalFileService.swift#L10), and [`SSHClientService+Helpers.swift:210`](../Packages/Networking/SSHClientService+Helpers.swift#L210).

### SwiftUI & AppKit `NSTableView` Performance Audit Checklist

| Checklist Item | Current Status | Empirical Code Citation | Debt & Remediation Path |
| :--- | :--- | :--- | :--- |
| **No expensive formatters created in `body`** | **Pass** | [`FilePaneTableView.swift:199-210`](../Features/Commander/FilePaneTableView.swift#L199-L210) & `TransferQueueView.swift` cache `static let` formatters. | Compliant. |
| **No per-render `AppStrings` / palette rebuild or heavy sorting in `body`** | **Pass (Mitigated)** | [`AppState.swift:177-178`](../Features/AppState.swift#L177-L178) caches stored `strings` & `activePalette`; sorting executes off-`MainActor`. `ConnectionManagerView` pre-groups via `Dictionary(grouping:)`. | Compliant. |
| **No broad observation fan-out** | **Partial (`TD-01`)** | 10Hz ticks isolated in `TransferMonitor` (`AppState.swift:72`), yet `AppState` still publishes 25+ unrelated Commander, Connection, Terminal & Settings properties together. | Split domain `ObservableObject` stores (and evaluate `@Observable` upon macOS 14+ floor bump). |
| **Stable `ForEach` identity without index/`.self` bugs** | **Pass** | Domain entities conform to `Identifiable`; `.self` used only on deduplicated immutable strings (`families`, sorted host keys, locale codes). | Compliant. |
| **Avoid top-level conditional view swapping** | **Fail (`TerminalWorkspaceView`, `TD-07`)** | [`MainWindowView.swift:34-37`](../Features/Dashboard/MainWindowView.swift#L34-L37) uses `if appState.isTerminalVisible`, destroying/recreating `TerminalView` & losing scrollback. | Retain hosted `NSView` instances or collapse splitter height cleanly without teardown. |
| **No synchronous image decoding on main thread** | **Pass** | Cached static SF Symbols (`FilePaneTableView.swift:195-197`); full previews defer to `QLPreviewPanel`. | Compliant. |
| **AppKit `NSTableView` cell dequeue reuse & incremental diffs** | **Partial (`TD-04`)** | Strict `makeView(withIdentifier:)` cell reuse in `FilePaneTableView` & `ConnectionListTableView`; **however**, `FilePaneTableView.updateNSView` (`L167-174`) runs `cachedFiles != files` (`O(N)`) + full `reloadData()` and `DualPaneCommanderView.swift:156` allocates `Array(visibleFiles)`. | Introduce generation stamps + `CollectionDifference` `insertRows`/`removeRows`. |

---

## (f) Terminal (`SwiftTerm`), Protocols, Transfer Engine & `TransferJournal` Assessment

- **SFTP / SCP / FTP / FTPS Architecture:** All protocol adapters implement uniform `RemoteConnection` & `RemoteFileSystem` contracts (`SparkleCore`) without UI coupling. **Debt (`TD-06`, `TD-10`, `TD-13`, `TD-15`):** `SFTPService.listDirectory` loads full listings into RAM before slicing; `SCPCompatibilityAdapter.download` buffers base64/gzip payloads in RAM without chunked streaming or optional `sudo -n` support; `.ftpsExplicit` omits custom `SecTrust` + OCSP preflight & active-mode config; `PrivateKeyParser` lacks encrypted/RSA key support.
- **Terminal (`SwiftTerm 1.20.0`):** `PTYResourceBox`, `dismantleNSView`, 100-tab teardown verification, OSC 52 read denial, HTTP/HTTPS link validation, and `LocalShellTerminalRepresentable` / `ExternalTerminalLauncher` (`iTerm2` / `Terminal.app`) provide a solid foundation. **Debt (`TD-07`):** Unconfigured `TerminalOptions(scrollback:)`, per-chunk `MainActor.run` hops in `attachPTYChannel`, scrollback wipe when hiding drawer (`MainWindowView.swift:34-37`), missing Find-in-Terminal bar, partial ANSI 16-color sync (only fg/bg/caret/selection mapped via `TerminalThemeColors`), and direct `appState` coupling in `TerminalWorkspaceView`.
- **Transfer Engine & `TransferJournal`:** Actor-isolated `TransferQueue`, `TransferScheduler` (`4` global / `3` per-host), `8x` pipelined SFTP chunks, FIFO serialized `pendingConflictQueue`, FileZilla policies, off-MainActor `SHA256Verifier` (`100MB` benchmark), `ResumeValidator` size+mtime verification, and `2.0s` throttled SQLite WAL checkpoints deliver high durability. **Debt (`TD-05`, `TD-12`):** Missing `PRAGMA user_version` schema migrations, `PRAGMA quick_check` corruption quarantine, `.paused`/`.queued` crash recovery, orphan `.part` sweeping, and randomized retry jitter.

---

## (g) Test Coverage & Docker Integration Fixture Gaps

- **Verified Automated Suite (`71 tests across 18 suites`, `0.833s`):** Unit and real in-process loopback SSH/SFTP/tunnel suites verify SFTP v3 framing, 8x pipelined `512 KB` SHA-256 transfers, `zlib`/`gzip` `CWE-409` overflow blocking, `ToolchainInspector` (`libcurl`, `zlib`, `libssh2` `dlopen`, shells, host report), `ExternalTerminalLauncher` `CWE-78` sanitization, FileZilla conflict rules & FIFO serialized queue auto-drain, TOFU/MITM key rotation blocking, `ProxyJump`, `SOCKS5`/`HTTP 200` proxy handshakes, `-L`/`-R` port forwarding, self-signed X.509 rejection, `100MB` SHA-256, mid-transfer cancel & partial disk resume, 28 SparkNotePad palettes WCAG AA + theme propagation, `309`-key EN/ID parity, FileZilla/WinSCP BOM importers, Notepad2 editor models, bidirectional sync, and 100-tab PTY teardown.
- **Remaining Gaps (`TD-02`):**
  1. `Tools/TestServers/run-integration-tests.sh` exports `SPARKLESFTP_LIVE_DOCKER_TESTS=1`, **yet zero tests consume that variable** (`docker-compose.test.yml` also uses floating `:latest` tags across `atmoz/sftp`, `linuxserver/openssh-server`, `fauria/vsftpd`, `instantlinux/proftpd`).
  2. `Tools/TestServers/fixtures/` contains no disposable FTPS TLS certificates, `vsftpd.conf`, `proftpd.conf`, or pre-seeded host-key fixtures, leaving live `FTPService` / `SCPCompatibilityAdapter` protocol handshakes unexecuted in CI.
  3. Zero automated AppKit `NSTableView` / `TerminalView` / `NotepadTextView` UI harness tests or `100K`-row XCTest `measure` benchmarks exist.

---

## (h) Release, Update & CI/CD Operational Risks

- **Universal 2 Packaging & CI Workflows:** `build-universal.sh` cleanly compiles `arm64` + `x86_64` release binaries, builds Universal 2 binaries via `lipo`, copies `SparkleSFTP_*.bundle` bundles into `Contents/Resources/` + `Sparkle.framework` into `Contents/Frameworks/`, and `.github/workflows/{ci,mega-linter,codeql,release,jekyll-gh-pages}.yml` use tight permissions and concurrency groups.
- **Operational Single Points of Failure (`TD-03`, `TD-15`):**
  1. [`Info.plist:34`](../App/Resources/Info.plist#L34) ships placeholder `SUPublicEDKey = REPLACE_WITH_PRODUCTION_ED25519_PUBLIC_KEY`; release builds run in ad-hoc/community mode without Gatekeeper notarization unless `DEVELOPER_ID_APP` / `APPLE_NOTARY_PROFILE` are supplied manually outside GitHub Secrets.
  2. `build-universal.sh:59` and `notarize.sh:18` use `codesign --deep`; Apple notarization and Sparkle 2 documentation recommend **inside-out signing** (signing `Sparkle.framework/Versions/B/XPCServices/*.xpc`, `Autoupdate`, `Updater.app`, and `Sparkle.framework` individually before the outer `.app`).
  3. `.github/workflows/release.yml` packages `.dmg` + `.sha256` without running Sparkle's `generate_appcast` to publish signed `appcast.xml`, lacks a documented **Ed25519 key rotation** bridge procedure, omits GitHub Secrets provisioning docs (`MACOS_CERTIFICATE_P12`, `APP_STORE_CONNECT_API_KEY_P8`, `SPARKLE_ED_PRIVATE_KEY`), and `SparkleUpdaterService.applySettings` skips forwarding `customFeedURL`.
  4. `build-universal.sh:14` defaults `SPARKLE_BUILD_JOBS=4` instead of conservative `2` (`-j 2`) when executed locally on thermally constrained laptops.

---

## (i) Prioritized 90-Day & 12-Month Remediation Roadmap

### 90-Day Stabilization & High-ROI Hardening Plan

1. **Days 1–21 — Release Signing, Inside-Out Notarization & Sparkle Appcast (`TD-03`, `TD-15`)**:
   - Replace `codesign --deep` in `Tools/Release/notarize.sh` & `build-universal.sh` with inside-out signing of `Sparkle.framework` XPCs/helpers; change `SPARKLE_BUILD_JOBS` default to `2`.
   - Provision offline-escrowed Ed25519 keys + Apple Developer ID secrets, populate `SUPublicEDKey`, add `generate_appcast` + `appcast.xml` publishing to `release.yml`, forward `customFeedURL` to `SPUUpdater`, and document certificate + Ed25519 key rotation in `SECURITY.md`.
2. **Days 15–45 — Activate Pinned Docker Interop Suite (`TD-02`)**:
   - Pin exact container tags/digests in `Tools/TestServers/docker-compose.test.yml`, generate self-signed FTPS TLS fixtures, seed non-interactive test host keys, and implement `SPARKLESFTP_LIVE_DOCKER_TESTS=1`-gated `DockerInteropTests` covering SFTP, SCP, Plain FTP, Explicit FTPS (`AUTH TLS`), and Implicit FTPS.
3. **Days 30–60 — Durability, Streaming SCP & Terminal Resilience (`TD-05`, `TD-06`, `TD-07`, `TD-12`)**:
   - Add `PRAGMA user_version` schema migrations, `PRAGMA quick_check` DB quarantine, `.paused` reconciliation, orphan `.part` cleanup, and jittered retry delays.
   - Stream SCP downloads incrementally via `FileHandle` chunks + optional `sudo -n`, preserve `TerminalView` NSViews across hide toggles (`MainWindowView`), configure `TerminalOptions(scrollback:)`, batch PTY output over 16ms frames, and convert `DispatchQueue.main.async` delegate bridges to `Task { @MainActor }`.
4. **Days 60–90 — SonarQube Pipeline, Complexity Caps & Flag Cleanup (`TD-08`, `TD-09`)**:
   - Configure `SWIFT_SWIFTLINT_ARGUMENTS: "--reporter sonarqube"` in `.mega-linter.yml` + `sonar-project.properties`, tighten `.swiftlint.yml` `cyclomatic_complexity` warning to `<= 6`, and enforce or remove `isSCPFallbackEnabled` / `isPortForwardingEnabled`.

### 12-Month Architectural Evolution Roadmap

1. **Q1–Q2 (`TD-01`, `TD-04`, `TD-13`) — Domain Store Split, `NSTableView` Diffing & Streaming `READDIR`**:
   - Decompose `AppState` into focused `@MainActor` stores, apply `CollectionDifference` incremental updates in `FilePaneTableView`, stream `SFTPService.listDirectory` incrementally, and add CI performance benchmarks for 100K-row folders.
2. **Q3 (`TD-10`, `TD-11`, `TD-15`) — Security Parity Across Explicit FTPS & OpenSSH Interop**:
   - Enforce `SecTrustEvaluateWithError` + OCSP revocation parity on Explicit FTPS (`AUTH TLS`), support passphrase-encrypted OpenSSH / RSA keys (`RFC 8332`) in `PrivateKeyParser`, and add user-authorized OpenSSH `~/.ssh/known_hosts` sync (`KnownHostsCodec`).
3. **Q4 — `.macOS(.v14)` Evaluation (`Observation` Framework)**:
   - When macOS 13 Ventura exits community support, evaluate raising `Package.swift` floor `.macOS(.v13)` -> `.macOS(.v14)` to adopt fine-grained `@Observable` tracking cleanly.

---

## (j) Authoritative External Research Baseline

- **Swift 6 Concurrency & Region-Based Isolation**: Official Swift Documentation (`docs.swift.org`) on complete strict concurrency, actor reentrancy check-effects-after-await validation, region-based isolation, `@unchecked Sendable` restraint, and `@MainActor` UI boundaries.
- **macOS Keychain, Trust & Notarization**: Apple Developer Security documentation on `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `SecTrustEvaluateWithError`, App Sandbox container boundaries vs `~/.ssh/known_hosts`, Hardened Runtime, and `notarytool` stapling requirements.
- **SSH Security (`CVE-2026-43798`)**: `apple/swift-nio-ssh` advisory fixing out-of-bounds stack write in ECDSA signature integer decoding in `0.14.1` (exceeded via `0.15.1` pin).
- **SwiftTerm (`migueldeicaza/SwiftTerm`)**: `LocalProcessTerminalView` & `TerminalOptions` scrollback memory scaling, viewport `yBase`/`yDisp` tracking, and PTY delegate teardown.
- **Sparkle 2 (`sparkle-project.org`)**: Ed25519 `SUPublicEDKey` signing, multi-key/bridge key rotation strategies, and inside-out code signing for nested XPC helpers (`sparkle_inside_out_signing`).
- **MegaLinter & SonarQube**: MegaLinter v10 `SWIFT_SWIFTLINT` descriptor integration and `swiftlint --reporter sonarqube` Generic Issue Import (`sonar.externalIssuesReportPaths`).
