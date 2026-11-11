# SparkleSFTP — Post-Completion Long-Term Architecture, Security & Sustainability Review

- **Review Date:** 2026-11-11
- **Reviewed Baseline:** Repository `main` (post-`v0.2.0` release, updated through Third-Party Toolchain Bridge `-lcurl -lz` / dynamic `libssh2` / `OpenSSL` / `OpenSSH` / `LocalShell` / `iTerm2`, Multi-Thread Pipelined SFTP, FileZilla Conflict Dialog + FIFO Queue, Language Card Switcher Layout, 7-Tab About, Keychain Remember Password & Performance Hardening across `71 tests in 18 suites` and `135` Swift files)
- **Target Platform & Toolchain:** `macOS 13.0+` (`.macOS(.v13)`), Swift 6 (`swiftLanguageModes: [.v6]`, `swift-tools-version: 6.0`)
- **Review Methodology:** All **14 Review Pillars** (`docs/CODE_REVIEW_14_PILLARS.md`) and **14 macOS Engineering Skills** grounded in empirical static scans, SwiftLint SonarQube reporter checks, live `swift test -j 2` verification, and source inspection.

---

## (a) Executive Summary of Architectural Health

**Overall Verdict: Strong Foundation (`B+` / Production-Grade Core with Tracked Multi-Month Maintenance Debt)**

SparkleSFTP establishes a notably disciplined Swift 6 architecture for a native macOS dual-pane SFTP/SCP/FTP/FTPS client:

- **Module & Layer Discipline Holds**: [`Package.swift`](../Package.swift) cleanly enforces an acyclic dependency graph (`App -> SparkleFeatures -> Packages/*`). `SparkleCore` depends only on `Foundation`; `SparkleTransferEngine` depends only on `SparkleCore`, `SparkleSecurity`, and `Crypto`, isolating transport behind `RemoteFileSystem` closures (`CIRC-001`); no `Packages/*` target imports `Features/` (`CIRC-002`).
- **Security Posture Exceeds Typical OSS Baselines**: `apple/swift-nio-ssh` (`0.15.1` >= `0.14.1`) mitigates **CVE-2026-43798**; `Clibcurl` locks `CURLOPT_PROTOCOLS_STR` to `"ftp,ftps"` (avoiding **CVE-2025-15224**); `KeychainService` enforces `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (verified by SwiftLint error rule `no_icloud_keychain_sync`); `HostTrustStore` implements a full 6-state TOFU machine with `.mismatch` hard-blocking; `PathValidator` and `SCPCompatibilityAdapter` block path traversal, destination symlinks, and POSIX shell injection (`CWE-22`, `CWE-59`, `CWE-78`).
- **One Critical Packaged-App Regression Fixed During Review**: Inspection of SwiftPM's generated `resource_bundle_accessor.swift` revealed that [`LocalizationCatalog.loadBundledStrings`](../Packages/DesignSystem/LocalizationCatalog.swift#L32-L60) and [`AppDelegate.configureApplicationIcon`](../App/AppDelegate.swift#L17-L27) previously invoked `Bundle.module` directly, while [`build-universal.sh`](../Tools/Release/build-universal.sh) omitted `.bundle` resources inside `Contents/Resources/`. Outside `swift test`/`swift run` (when packaged in `.app`), `Bundle.module` executes `Swift.fatalError(...)` on end-user Macs. Both callers and the Universal 2 packager were fixed cleanly during this review.
- **Targeted Runtime & Quit Fixes Landed Post-Review**: Isolated 10Hz transfer progress ticks into dedicated [`TransferMonitor`](../Features/Transfers/TransferMonitor.swift), cached `AppState.strings` and `activePalette` (`Features/AppState+Settings.swift`), switched local folder enumeration to single-`lstat` POSIX calls (`LocalFileService.swift`), cached static SF Symbol `NSImage`s in `FilePaneTableView`, pre-grouped Connection List rows via `Dictionary(grouping:)`, throttled active SQLite `TransferJournal` progress writes to `>= 2.0s` per transfer, and replaced the deadlocking `@MainActor` exit semaphore in [`AppDelegate.swift`](../App/AppDelegate.swift) with instant `applicationShouldTerminate` + bounded parallel NIO teardown. Remaining `TD-01` scope focuses on decomposing remaining commander/terminal properties if deployment targets advance to `@Observable`.
  2. Live Docker multi-server test runner (`Tools/TestServers/run-integration-tests.sh`) exports `SPARKLESFTP_LIVE_DOCKER_TESTS=1` without any test suite consuming that flag yet, plus missing FTPS container TLS certificates and SCP live container verification.
  3. Sparkle 2 native auto-update shipping in community fallback mode (`SUPublicEDKey` placeholder, missing appcast generation/signing + Ed25519 key-rotation runbook in `release.yml`).
  4. SonarQube server integration (`sonar-project.properties` / `sonar-scanner` CI step) is not configured in the repository despite `swiftlint lint --reporter sonarqube` producing valid SonarQube JSON (`0` issues).

---

## (b) Post-Release Linter Sweep & 14-Pillar Findings

### Post-Release Linter & SonarQube Verification Results

| Tool / Gate | Scope | Command / Config | Empirical Result |
| :--- | :--- | :--- | :--- |
| **SwiftLint (Strict)** | 135 Swift files (`Package.swift`, `App/`, `Packages/`, `Features/`, `Tests/`) | `swiftlint lint --strict` (`.swiftlint.yml`) | `0` violations, `0` serious errors |
| **SwiftFormat** | 135 Swift files | `swiftformat --lint .` (`.swiftformat`) | `0/135` files require formatting |
| **SwiftLint SonarQube Reporter** | All Swift files | `swiftlint lint --reporter sonarqube --quiet` | `sonarqube_issues=0` (valid JSON) |
| **SonarQube Server / Scanner** | Project root | Check `sonar-project.properties` / `.github/` | **Gap: Not configured** (`NO_SONARQUBE_CONFIG_FOUND`) |
| **MarkdownLint** | 25 Markdown files (`*.md`, `docs/`, `tasks/`) | `npx --yes markdownlint-cli2 "**/*.md" ...` | `0` issues |
| **YAMLlint** | CI workflows, Docker Compose, linter configs | `yamllint -c .yamllint.yml .` | `0` issues (exit `0`) |
| **Actionlint** | `.github/workflows/*.yml` (5 workflows) | `actionlint` | `0` issues (exit `0`) |
| **Bash / ShellCheck / Shfmt** | `Tools/Release/*.sh`, `Tools/TestServers/*.sh` | `bash -n`, `shellcheck -s bash`, `shfmt -d -i 2 -ci` | `0` issues across all 4 scripts |
| **JSON / XML Validation** | `.json`, `.resolved`, `Info.plist`, `.entitlements` | `python3 -m json.tool`, `xmllint --noout` | `0` syntax errors |
| **Clibcurl C Hygiene** | `Packages/Clibcurl/*`, `.clangd`, `.clang-format` | `cppcheck`, `clang-format --dry-run --Werror`, `clang -fsyntax-only -xc -std=c11` | `0` errors / formatting issues |
| **Swift Testing Suite** | 8 test targets (unit + live loopback SSH/SFTP) | `nice -n 10 swift test -j 2 --disable-xctest --enable-swift-testing` | **71 tests in 18 suites passed (`0.800s`)** |

> **SonarQube Configuration Gap Explicit Note:** Neither `sonar-project.properties` nor a `sonarcloud`/`sonarqube` GitHub Actions job is configured in `.github/workflows/`. Only `swiftlint lint --reporter sonarqube` format compatibility is verified locally (`0` issues). Notice also `.swiftlint.yml` uses SwiftLint's default `cyclomatic_complexity` (`warning: 10`, `error: 20`), whereas long-term maintainability prefers lowering `cyclomatic_complexity` warning to `<= 6`.

### Per-Pillar Assessment (14 Pillars)

| # | Pillar | Severity | Empirical Findings & Citations |
| :--- | :--- | :--- | :--- |
| **1** | **Bug Review** | **Critical** *(Fixed)* / **Med** | **Fixed:** `LocalizationCatalog.loadBundledStrings` (`Packages/DesignSystem/LocalizationCatalog.swift:33`) and `AppDelegate.configureApplicationIcon` (`App/AppDelegate.swift:19`) risked SwiftPM `Bundle.module` `fatalError` crashes when packaged as `.app` because `build-universal.sh` omitted `.bundle` files from `Contents/Resources/`. **Open:** Reconciling interrupted transfers on launch misses `.queued` and `.paused` rows (`TransferJournal.swift:125`), and `FTPService.connect` does not extract `lastVerifiedCertificate` on `.ftpsExplicit` (`FTPService.swift:45-50`). |
| **2** | **Syntax Review** | **Low (Pass)** | Zero syntax errors or compiler warnings under Swift 6 language mode (`swiftLanguageModes: [.v6]`), `Package.swift` resolves cleanly on CLT macOS SDK and `macos-15` Xcode runners. |
| **3** | **Runtime Review** | **High** | `AppState.strings` (`Features/AppState.swift:140-142`) reconstructs `AppStrings` on every view body read; `MainWindowView.swift:35-38` destroys/recreates `TerminalView` (`SwiftTerm`) when toggling terminal drawer visibility, losing terminal scrollback; `SCPCompatibilityAdapter.download` (`SCPCompatibilityAdapter.swift:96-101`) buffers entire remote files in memory (`stdout` base64). |
| **4** | **Logic Review** | **Medium** | `TransferQueue.runWithRetry` (`TransferQueue+Execution.swift:32`) uses deterministic `1 << (attempt - 1)` backoff without jitter; `SparkleUpdaterService.applySettings` (`App/SparkleUpdaterService.swift:58-65`) ignores custom feed URLs; `WinSCPAndFileReader` & `FileZillaImporter` now pass edge cases after fixing BOM/folder bugs. |
| **5** | **Memory & Concurrency** | **Medium** | All 11 `@unchecked Sendable` conformances carry `// JUSTIFICATION:` comments and `NSLock`/actor serialization; however, `TerminalViewRepresentable.Coordinator.runOnMain` (`TerminalViewRepresentable.swift:53-62`) uses legacy `DispatchQueue.main.async { MainActor.assumeIsolated ... }`, and `TerminalSessionManager.attachPTYChannel` awaits `MainActor.run` per individual byte chunk without burst coalescing. `TLSCertificateValidator` (`TLSCertificateValidator.swift:69,81`) and `LocalDirectoryWatcher` (`LocalFileService.swift:9`) retain GCD `DispatchQueue` usage. |
| **6** | **Dead Code Review** | **Low** | `FeatureFlags` (`Packages/Core/FeatureFlags.swift:4-34`) defines `isSCPFallbackEnabled`, `isPortForwardingEnabled`, and `isTouchIDGateEnabled`, but only `isSyncEnabled` (`MainWindowView.swift:93`) is ever checked at runtime. |
| **7** | **Duplicate Code Review** | **Low** | Connection error-mapping (`AppState+*.swift` catching errors -> `lastError = (error as? AppError) ?? ...`) repeats across `AppState+Connections`, `AppState+Operations`, `AppState+Imports`, and `AppState+TransferHelpers`. `Preferences*` tabs duplicate file-picker helpers cleanly enough via `AppState+Settings`. |
| **8** | **Circular Dependency** | **Pass (`0` Issues)** | Verified strict DAG in `Package.swift`: `SparkleCore` (`Foundation` only) at root; `TransferEngine` decoupled from `Networking` and `Persistence` via closures/`TransferJournalProtocol`. |
| **9** | **Performance Bottlenecks** | **High** | `AppState` is a monolithic `ObservableObject` injected across all views; `transferSnapshots` ticks every `100ms` during transfers, invalidating unconnected panes (`ConnectionManagerView`, `DualPaneCommanderView`). `FilePaneTableView.updateNSView` compares full `[RemoteFile]` equality and calls `tableView.reloadData()` instead of diffed row updates (`FilePaneTableView.swift:99-115`). |
| **10** | **Security Vulnerabilities** | **Medium** | Zero CRITICAL CVEs/CWEs in production paths; **Gap L4:** `HostTrustStore` stores proprietary JSON in Keychain rather than importing/exporting OpenSSH `~/.ssh/known_hosts`; **Gap L5:** `FTPS Explicit` relies on `libcurl` trust defaults rather than custom OCSP `SecTrust` callback extraction; **Gap L6:** `Info.plist` carries placeholder `SUPublicEDKey`. |
| **11** | **Maintainability** | **Medium** | Clean Architecture protocols exist in `Packages/Core/Protocols.swift`, yet `AppState` concentrates both presentation bindings and repository/lifecycle wiring directly rather than delegating to focused feature stores/use-cases; `SQLite3` schema lacks `PRAGMA user_version` migrations (`TransferJournal.swift:45-48`). |
| **12** | **Scalability** | **Medium** | `PaginatedFileWindow` caps rendered Commander rows cleanly at incremental slices; `TransferScheduler` caps global (`3`) and per-host (`2`) concurrency; `TransferJournal` prunes at `10,000` entries / `30` days. Gaps: `SFTPService.listDirectory` accumulates all entries in memory before wrapping into `PaginatedFileWindow`; `SwiftTerm` leaves unbounded or default scrollback buffer unmanaged during high-output floods. |
| **13** | **Readability** | **Low (Pass)** | Descriptive English identifiers, clean multi-file extensions (`AppState+*`, `InternalEditorBars`), `<= 400`-line file discipline, `0` SwiftLint body-length/line-length violations. |
| **14** | **Linter & CI Gate** | **Medium** | Local & GitHub Actions CI/MegaLinter/CodeQL pass cleanly (`0` warnings/errors across `118` Swift files); gap exists only for external SonarQube server (`sonar-project.properties` absent) and explicit `cyclomatic_complexity <= 6` cap. |

---

## (c) Technical Debt Register (Prioritized with Effort & Impact)

| ID | Debt Item | Location | Effort | Impact | Recommended Action |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **TD-01** | Monolithic `AppState: ObservableObject` causing 100ms SwiftUI observation fan-out & repeated `AppStrings`/`activePalette` struct reconstruction | `Features/AppState.swift` (`L49-L152`) | Large (2–3 wks) | **High** | Split into domain-scoped stores (`TransferQueueStore`, `ConnectionStoreVM`, `CommanderPaneStore`, `ThemeLocaleStore`) and cache `cachedStrings`/`cachedPalette`; target `@Observable` if minimum OS moves to macOS 14+. |
| **TD-02** | Live Docker test runner ignores `SPARKLESFTP_LIVE_DOCKER_TESTS=1`; missing FTPS TLS certs & SCP container tests | `Tools/TestServers/run-integration-tests.sh` (`L25`), `docker-compose.test.yml` | Medium (3–5 days) | **High** | Add gated Docker interop suite in `Tests/IntegrationTests/` with pinned container image digests, pre-baked self-signed FTPS fixture certs, non-interactive known-host seeding, and SCP/FTPS assertions. |
| **TD-03** | Production Sparkle Ed25519 appcast signing & key rotation pipeline incomplete | `App/Resources/Info.plist` (`L34`), `.github/workflows/release.yml`, `App/SparkleUpdaterService.swift` | Medium (2–4 days) | **High** | Provision Developer ID cert + Notary API secrets + Sparkle Ed25519 key pair in GitHub Secrets; add `generate_appcast` & dual-key rotation runbook; pass `customFeedURL` through to `SPUUpdater`. |
| **TD-04** | `FilePaneTableView.updateNSView` uses full `cachedFiles != files` compare + full `reloadData()` & array copying | `Features/Commander/FilePaneTableView.swift` (`L99-L116`), `DualPaneCommanderView.swift` (`L151`) | Medium (3–4 days) | **Medium** | Compute `CollectionDifference` row insertions/removals cleanly before calling `insertRows`/`removeRows` on `NSTableView`, and compare generation counters instead of deep array equality. |
| **TD-05** | `TransferJournal` lacks `PRAGMA user_version` schema migrations, `PRAGMA quick_check` corruption fallback, and `.paused`/`.queued` restore | `Packages/Persistence/TransferJournal.swift` (`L45-L48`, `L124-L138`) | Medium (3–4 days) | **Medium** | Add versioned schema migration table (`user_version >= 1`), fallback corrupt-DB quarantine (`mv transfer_journal.sqlite3 .corrupt`), and restore `.paused` jobs + orphan `.part` sweeping. |
| **TD-06** | `SCPCompatibilityAdapter.download` buffers whole base64 stream in RAM; no optional `sudo -n` elevation support | `Packages/Networking/SCPCompatibilityAdapter.swift` (`L87-L120`) | Medium (3 days) | **Medium** | Stream SSH stdout chunks incrementally to `FileHandle` (matching `upload`'s 24KB chunk pattern) and add opt-in restricted `SCP` wrapper without interactive password echo. |
| **TD-07** | `TerminalView` destroyed on hide/split toggle & lacks search bar / burst coalescing / scrollback bound | `Features/Dashboard/MainWindowView.swift` (`L35-L38`), `Packages/Terminal/TerminalViewRepresentable.swift` (`L53-L62`), `TerminalSessionManager.swift` (`L75-L90`) | Medium (4 days) | **Medium** | Preserve `TerminalView` instances cleanly across split/drawer toggles (frame visibility instead of conditional removal), enforce bounded scrollback history, coalesce PTY output batches at 16–33ms, replace `DispatchQueue.main.async` with `Task { @MainActor }`, and expose search UI. |
| **TD-08** | SonarQube server config missing (`sonar-project.properties`) & `.swiftlint.yml` `cyclomatic_complexity` at default `10` | `.swiftlint.yml`, CI workflows | Small (1 day) | **Medium** | Set `cyclomatic_complexity: warning: 6` iteratively across new code, add `sonar-project.properties` importing `swiftlint --reporter sonarqube` output when SonarCloud/SonarQube token is provisioned. |
| **TD-09** | Dead `FeatureFlags` properties (`isSCPFallbackEnabled`, `isPortForwardingEnabled`, `isTouchIDGateEnabled`) | `Packages/Core/FeatureFlags.swift` (`L5-L8`) | Small (0.5 day) | **Low** | Wire checks into `RemoteServiceFactory`, `TerminalWorkspaceView`, and `KeychainService` gating or remove unused flags. |
| **TD-10** | `FTPS Explicit` (`AUTH TLS`) skips `TLSCertificateValidator` OCSP `SecTrust` callback & lacks active-mode fallback | `Packages/Networking/FTPService.swift` (`L45-L50`), `CurlClientHelper.swift` (`L42-L48`) | Medium (4 days) | **Medium** | Perform explicit `AUTH TLS` STARTTLS preflight or custom libcurl `CURLOPT_SSL_CTX_FUNCTION` callback wiring `SecTrustEvaluateWithError` cleanly across explicit and implicit FTPS. |
| **TD-11** | `HostTrustStore` lacks OpenSSH `~/.ssh/known_hosts` interoperable parser/exporter | `Packages/Security/HostTrustStore.swift` (`L68-L169`) | Small–Med (2–3 days) | **Low–Med** | Add `KnownHostsCodec` supporting standard `[host]:port` & hashed `known_hosts` entries while maintaining Keychain as primary encrypted backing store. |
| **TD-12** | Retry backoff lacks jitter *(SQLite 2s checkpoint throttle resolved)* | `Packages/TransferEngine/TransferQueue+Execution.swift` (`L32`), `TransferQueue+Checkpoint.swift` (`L71`) | Small (0.5–1 day) | **Low–Med** | **Done:** Decoupled SQLite progress writes to `>= 2.0s` / `statusCode` transitions. **Open:** Add full jitter (`Double.random(in: 0.7...1.3)`) to exponential retry backoff. |

---

## (d) Security Findings with CVE / CWE Mapping

| Finding ID | Reference / Standard | Status | Code Evidence & Assessment |
| :--- | :--- | :--- | :--- |
| **SEC-CVE-1** | **CVE-2026-43798** (`apple/swift-nio-ssh` pre-auth oversized ECDSA OOB stack write) | **Mitigated** | [`Package.swift`](../Package.swift) pins `apple/swift-nio-ssh` `"0.15.1" ..< "0.16.0"` (`>= 0.14.1`), verified in `Package.resolved`. |
| **SEC-CVE-2** | **CVE-2025-15224** (`libcurl` `libssh` SSH-agent auth bypass) | **Mitigated** | [`CurlClientHelper.swift:25`](../Packages/Networking/CurlClientHelper.swift#L25) strictly locks `CURLOPT_PROTOCOLS_STR = "ftp,ftps"`, disabling SCP/SFTP protocols inside libcurl entirely. |
| **SEC-CWE-312 / 522** | Clear-text storage / insecure credential transmission | **Compliant (Gap: Access Group)** | [`KeychainService.swift:32,41`](../Packages/Security/KeychainService.swift#L32-L41) enforces `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `.userPresence` ACL + `LAContext`, and SwiftLint `no_icloud_keychain_sync` error rule. Future Helper XPC extensions will need `kSecAttrAccessGroup` support (`KeychainAccessGroups` entitlement). |
| **SEC-CWE-295** | Improper Certificate Validation (`FTPS`) | **Partial** | `TLSCertificateValidator` enforces `SecPolicyCreateSSL` + `kSecRevocationOCSPMethod` + `.TLSv12` minimum via `NWProtocolTLS` for `.ftpsImplicit`. **Residual Risk (`TD-10`):** `.ftpsExplicit` sets `CURLOPT_USE_SSL = CURLUSESSL_ALL`, `CURLOPT_SSL_VERIFYPEER = 1`, `CURLOPT_SSL_VERIFYHOST = 2`, relying on macOS system libcurl TLS backend rather than invoking `TLSCertificateValidator.validateServerCertificate` (`SecTrust` + OCSP). |
| **SEC-CWE-300 / 295** | SSH Host Key Verification (TOFU MITM) | **Compliant (`KnownHosts` Interop Gap)** | [`HostTrustStore.swift:107-147`](../Packages/Security/HostTrustStore.swift#L107-L147) enforces 6-state TOFU (`unknown`, `pendingUserDecision`, `trusted`, `rejected`, `mismatch`, `corrupted`) and hard-blocks `.mismatch` (`acceptAnyHostKey` banned by SwiftLint). **Residual Risk (`TD-11`):** No parser for OpenSSH `~/.ssh/known_hosts`. |
| **SEC-CWE-78** | OS Command Injection (`SCP` fallback) | **Compliant** | [`SCPCompatibilityAdapter.swift:32-38`](../Packages/Networking/SCPCompatibilityAdapter.swift#L32-L38) rejects NUL bytes and applies `'\\''` single-quoting across every remote path argument (`ls`, `stat`, `readlink`, `base64`, `rmdir`, `rm`, `mv`, `mkdir`, `chmod`). |
| **SEC-CWE-93** | CRLF Injection in FTP Control Channel | **Compliant** | [`FTPService.swift:196-202`](../Packages/Networking/FTPService.swift#L196-L202) scans raw UTF-8 bytes (`0x00`, `0x0A`, `0x0D`) rather than Unicode `Character` clusters (preventing `\r\n` graphemes from slipping past `Character` equality checks). |
| **SEC-CWE-22 / 59** | Path Traversal & Symlink Escape | **Compliant** | [`PathValidator`](../Packages/Security/PathValidator.swift) canonicalizes remote/local destinations, rejects pre-existing local destination symlinks, and `DirectoryScanner` detects circular symlinks via `visitedInodes`. |
| **SEC-CWE-494** | Download of Code Without Integrity Check (Updates) | **Mitigated (`Key Rotation Gap`)** | [`UpdateConfigurationValidator.swift:5-34`](../Packages/Security/UpdateConfigurationValidator.swift#L5-L34) rejects HTTP feeds and placeholder `SUPublicEDKey` values (`Info.plist:34`); signed in-app Sparkle updates remain disabled until production Ed25519 signing is provisioned (`TD-03`). |
| **SEC-CWE-400** | Uncontrolled Resource Consumption | **Open (`TD-06`, `TD-07`)** | `SCPCompatibilityAdapter.download` buffers unbounded base64 `stdout`; `TerminalView` has no configured history line cap. |
| **SEC-CWE-532** | Sensitive Info in Logs | **Compliant** | `DiagnosticsLogger` uses `OSLog` `.private` annotations; SwiftLint `no_password_in_logs` rule passes with `0` violations across `118` files. |

---

## (e) Swift 6 Concurrency & SwiftUI Performance Sustainability Assessment

### Swift 6 Strict Concurrency Audit

- **Compiler Enforcement:** All targets compile cleanly under `swiftLanguageModes: [.v6]` with zero compiler warnings on both Command Line Tools Swift 6.2.4 and GitHub Actions `macos-15` Xcode runners.
- **Actor Boundaries & Isolation:**
  - Protocol adapters (`SFTPService`, `FTPService`, `SCPCompatibilityAdapter`, `SSHClientService`), transfer execution (`TransferQueue`, `TransferScheduler`, `ConflictResolver`), trust (`HostTrustStore`), and SQLite persistence (`TransferJournal`) are proper `actor` types.
  - All UI coordinators (`AppState`, `TerminalSessionManager`, `EditorSessionManager`, `QuickLookCoordinator`) are strictly `@MainActor`.
  - **Transfer Reentrancy (`TransferQueue`):** Post-`await` cancellation and task-membership guards (`guard isStillActive(id:)`) execute deterministically across every suspension point, verified by `TransferEngineTests` and `TransferEngineResumeTests`.
  - **C Bridge Lifetime (`FTPService` / `CurlClientHelper`):** `Unmanaged.passUnretained(box)` is safely scoped synchronously within `CurlClientHelper.executeCurl(...)` inside a blocking `Task.detached`, keeping `box` alive on stack throughout `curl_easy_perform`, while `CurlCancellationToken` uses `NSLock` inside `withTaskCancellationHandler` `onCancel`.
- **Legacy Concurrency / Evolution Watchlist:**
  1. [`TerminalViewRepresentable.swift:53-62`](../Packages/Terminal/TerminalViewRepresentable.swift#L53-L62): `DispatchQueue.main.async { ... MainActor.assumeIsolated { ... } }` inside `nonisolated` `TerminalViewDelegate` should migrate to `Task { @MainActor [weak self] in ... }` to eliminate manual `assumeIsolated` runtime assertions under future Swift executor strictness.
  2. [`LocalFileService.swift:5-9`](../Packages/FileManager/LocalFileService.swift#L5-L9): `LocalDirectoryWatcher` uses `DispatchSourceFileSystemObject` + `DispatchQueue` + `NSLock`; safe and isolated, though an `AsyncStream` / actor wrapper is cleaner long-term.
  3. [`TLSCertificateValidator.swift:69,81`](../Packages/Security/TLSCertificateValidator.swift#L69-L81): `NWConnection` preflight uses raw `DispatchQueue` + `TLSHandshakeBox` (`@unchecked Sendable` + `NSLock`); safe today, replaceable cleanly with Swift concurrency continuation helpers over an internal actor/lock wrapper.
  4. [`AppDelegate.swift:29-55`](../App/AppDelegate.swift#L29-L55): **Fixed** — migrated `applicationWillTerminate` `DispatchSemaphore` deadlock onto `applicationShouldTerminate` with synchronous `prepareFastShutdown()`, instant `.terminateNow` when idle, and bounded `<= 350ms` parallel NIO teardown via `SSHClientService.closeChannelAndShutdownGroup`.

### SwiftUI Performance Audit Checklist

| Checklist Item | Status in SparkleSFTP | Empirical Location & Notes | Remediation Pattern & Debt |
| :--- | :--- | :--- | :--- |
| **No formatters instantiated inside `body`** | **Pass** | [`FilePaneTableView.swift:136-142`](../Features/Commander/FilePaneTableView.swift#L136-L142) and [`TransferQueueView.swift:9-13`](../Features/Transfers/TransferQueueView.swift#L9-L13) cache `static let` `ByteCountFormatter` / `DateFormatter`. | None needed (`FileInspectorSheet` `.formatted()` runs only in modal sheets). |
| **No heavy sorting/filtering inside `body`** | **Mitigated (Partial)** | Directory sorting runs off-MainActor via `FileSortDescriptor` + `DirectoryScanner`; connection sidebar rows are pre-grouped cleanly in `ConnectionManagerView.buildTableRows` via `Dictionary(grouping:)` for AppKit `ConnectionListTableView`, while `DualPaneCommanderView` still slices array state on re-eval (`TD-01`). | Pre-compute visible array buffers when moving to `@Observable` (`TD-01`). |
| **Stable identity (`ForEach` without index/`.self` misuse)** | **Pass** | Domain models conform to `Identifiable`; `.self` is used solely for distinct immutable string keys (`families`, `trustedHosts.keys.sorted()`). | None needed. |
| **Avoid top-level conditional view swapping** | **Fail (`TerminalWorkspaceView`)** | [`MainWindowView.swift:35-38`](../Features/Dashboard/MainWindowView.swift#L35-L38) conditionally creates/destroys `TerminalWorkspaceView` via `if appState.isTerminalVisible`, tearing down `TerminalView` NSViews and losing scrollback. | Keep terminal view hosted cleanly or preserve NSView instances inside `TerminalSessionManager` (`TD-07`). |
| **No synchronous image decoding on main thread** | **Pass (Warning)** | Icons use SF Symbols (`NSImage(systemSymbolName:)`); custom app icon decodes once on launch (`AppDelegate.swift`). Custom image previews defer to `QLPreviewPanel`. | None needed. |
| **No broad observation fan-out (`ObservableObject` vs `@Observable`)** | **Mitigated (Partial)** | 10Hz transfer ticks isolated in [`TransferMonitor`](../Features/Transfers/TransferMonitor.swift), `AppState.strings`/`activePalette` cached (`Features/AppState+Settings.swift`), and sidebar grouping computed in O(N) via `Dictionary(grouping:)`; commander/terminal still observe `AppState`. | Split remaining commander/terminal sub-stores when targeting `.macOS(.v14)` (`TD-01`). |
| **`NSTableView` cell dequeue reuse & incremental updates** | **Partial** | `FilePaneTableView` uses AppKit `NSTableView` with strict `makeView(withIdentifier:)` cell reuse (`FilePaneTableView.swift:170-290`), preventing SwiftUI `List` hangs on 10K+ rows. **However**, `updateNSView` compares full `cachedFiles != files` (`O(N)`) and invokes full `tableView.reloadData()` instead of diffed row updates (`TD-04`). | Diff row indices with `CollectionDifference` + generation IDs (`TD-04`). |

---

## (f) Terminal (`SwiftTerm`) & Transfer Engine / `TransferJournal` Assessment

### Terminal (`SwiftTerm 1.20.0`) Maintainability (`Packages/Terminal/`, `Features/Terminal/`)

- **Strengths:** Clean `NSViewRepresentable` wrapper ([`TerminalViewRepresentable.swift`](../Packages/Terminal/TerminalViewRepresentable.swift)) clears `terminalDelegate = nil` in `dismantleNSView`, `PTYResourceBox` guarantees deterministic `SSHPTYChannel` & `Task` teardown on tab close or `deinit` (verified by the 100-tab teardown stress test in [`IntegrationTests.swift`](../Tests/IntegrationTests/IntegrationTests.swift)), links validated against `http`/`https` schemes before `NSWorkspace.shared.open`, and decoupling via `PortForwardingManager` + `CommandSnippetStore`.
- **Technical Debt (`TD-07`):**
  1. **Scrollback Memory Growth:** Default `TerminalView` buffer behavior is unconfigured (`changeHistorySize`), risking sustained memory growth during multi-hour `tail -f` log sessions.
  2. **Lack of Burst Coalescing:** `attachPTYChannel` (`TerminalSessionManager.swift:75-90`) schedules a separate `MainActor.run` hop for every raw NIOSSH `outputStream` chunk. High-speed stdout floods should batch chunks over ~16ms frames.
  3. **Pane Lifecycle & State Loss:** Toggling `appState.isTerminalVisible` or `splitTerminalMode` (`TerminalWorkspaceView.swift:81-90`) recreates `TerminalView(frame: .zero)`, wiping scrollback and scroll position even though the underlying SSH channel stays alive.
  4. **Missing Find-in-Terminal & Partial ANSI Styling:** `TerminalViewRepresentable` now syncs live `SparkleThemePalette` background, foreground, caret, and selection colors via `TerminalThemeColors`, though full 16-color ANSI palette customization and scrollback search remain future enhancements (`TD-07`).
  5. **Coupling:** `TerminalWorkspaceView` reads `appState.currentSession?.sshClient`, `appState.splitTerminalMode`, and `appState.snippets` directly through `@ObservedObject appState` instead of an isolated `TerminalCoordinator`.

### Transfer Engine & `TransferJournal` Durability (`Packages/TransferEngine/`, `Packages/Persistence/`)

- **Strengths:**
  - Crash-safe temporary files (`.\(name).sparklesftp.\(id).part` locally; remote temp upload paths), off-MainActor streaming `SHA256Verifier` (`100MB` benchmark verified in `0.85s` cleanly), atomic replacement via `FileManager.default.replaceItemAt`, `ResumeValidator` checking both remote size and mtime delta (`<= 1.0s`) + exact local partial byte count before resuming (`LOG-002`), bounded FIFO+per-host `TransferScheduler`, and `TransferJournal` using `SQLite3` WAL mode (`FULLMUTEX`) + automatic pruning (`10,000` rows / `30` days).
- **Durability Risks (`TD-05`, `TD-12`):**
  1. **Missing Schema Versioning (`PRAGMA user_version`):** Adding columns or altering JSON schemas inside `metadata_json` / `checkpoint_json` lacks an automated forward migration gate (`TransferJournal.swift:189-203`).
  2. **Corrupt Database Recovery:** If `transfer_journal.sqlite3` or its `-wal` file suffers hardware/power-cut corruption, `AppState.bootstrap()` (`Features/AppState+Connections.swift:62`) uses `try?` on `restoreInterruptedFromJournal()` (avoiding launch crash cleanly!), yet leaves the corrupted file permanently unrecoverable until manually deleted. Adding `PRAGMA quick_check` on `init` with quarantine & recreation restores durability cleanly.
  3. **Partial Recovery Scope (`queued` / `paused` Tasks & Orphan `.part` Cleanup):** `reconcileInterruptedOnLaunch()` only transitions `'preparing'`, `'connecting'`, `'transferring'`, `'verifying'`, `'finalizing'` to `'interrupted'`. User-paused transfers (`.paused`) or `.queued` transfers persisted prior to crash are ignored on launch, and stale `.sparklesftp.*.part` files from pruned/cancelled records can accumulate on disk.
  4. **SQLite Checkpoint Write Frequency:** [`TransferQueue+Checkpoint.swift:66`](../Packages/TransferEngine/TransferQueue+Checkpoint.swift#L66) invokes `persistSnapshot` (a SQLite `INSERT ... ON CONFLICT DO UPDATE` disk write) on every `updateSnapshot` (`100ms` progress throttler ticks!), creating ~10 SQLite WAL transactions/sec per active transfer instead of persisting checkpoints only on state changes or multi-megabyte thresholds (`TD-12`).
  5. **Backoff Without Jitter:** `1 << (attempt - 1)` retries without jitter (`TD-12`).

---

## (g) Test Coverage & Docker Fixture Gaps

- **Current Verified Coverage (`71 tests across 18 suites`):** Strong unit and in-process encrypted loopback tests covering `RemotePath`, `AppStrings` & `309`-key `en`/`id` JSON parity, `28` SparkNotePad palettes WCAG AA contrast + full workspace theme sync & `TerminalThemeColors`, 7-tab `AboutView` diagnostics, `ZlibCompressionCodec` `.zlib`/`.gzip` round-trip & `CWE-409` zip-bomb overflow guard, `ToolchainInspector` (`libcurl`, `zlib`, `libssh2` `dlopen`, `OpenSSL`, `OpenSSH`, POSIX shells, `iTerm2`), `ExternalTerminalLauncher` `CWE-78` sanitization, 8x pipelined 512 KB SFTP multi-chunk upload/download SHA-256 verification, FileZilla conflict rules (`ConflictResolver`) + serialized FIFO `pendingConflictQueue` drain, Keychain Remember Password & `FTPService` prompt flows, `KeychainService`, 6-state TOFU & MITM blocking, `PathValidator`, self-signed X.509 rejection (`SecTrust`), `FileZilla`/`WinSCP` BOM/nested folder importers, `SFTPPacketCodec`, `ProxyJump`, `DirectTCPIP`/`tcpip-forward` `-R`, `SOCKS5`/`HTTP 200` proxy checks, `SCPCompatibilityAdapter` single-quote escaping, FTP `MLSD`/`LIST` parsing & `CWE-93` CRLF sanitizer, `TransferQueue` actor reentrancy / resume / conflicts / `100MB` SHA-256 / 2s journal checkpoint throttling, `SyncPlanner` one-way & bidirectional sync, Notepad2 editor models, unique `ConnectionTableRowItem` section/profile keys, connection cloning & multi-select batch deletion, single-`lstat` POSIX enumeration, and 100-tab `TerminalSessionManager` teardown.
- **Identified Regression Gaps:**
  1. **Docker Harness Disconnect (`TD-02`):** [`Tools/TestServers/run-integration-tests.sh`](../Tools/TestServers/run-integration-tests.sh) starts `atmoz/sftp`, `linuxserver/openssh-server`, `fauria/vsftpd`, and `instantlinux/proftpd` with `:latest` image tags and sets `SPARKLESFTP_LIVE_DOCKER_TESTS=1`, **but zero tests read `SPARKLESFTP_LIVE_DOCKER_TESTS`**. Furthermore, `Tools/TestServers/fixtures/` contains no TLS certificate/vsftpd.conf/proftpd.conf mounts for testing live Explicit/Implicit FTPS, nor deterministic host-key seeding files (`ssh-keyscan`) for non-interactive CI runs.
  2. **No Live SCP / FTP / FTPS Wire Protocol Execution:** `FTPService` and `SCPCompatibilityAdapter` are tested via parser/sanitizer unit tests rather than live local `vsftpd`/`proftpd`/`openssh` protocol handshakes.
  3. **AppKit / SwiftUI Representation Runtime Tests Missing:** `FilePaneTableView`, `NotepadTextView`, `NotepadLineNumberRuler`, and `TerminalViewRepresentable` layout/responder chains are verified manually/via models rather than XCTest UI / ViewInspector harness runs.
  4. **No Automated Performance Regression Benchmarks in CI:** While `PaginatedFileWindow` slices 10K items and `SHA256Verifier` hashes `100MB`, there is no XCTest `measure` baseline tracking 100K-row `FilePaneTableView` updates or 1GB SFTP streaming throughput.

---

## (h) Release & Update Infrastructure Risks

- **Developer ID Certificate Lifecycle & Storage:** [`Tools/Release/notarize.sh`](../Tools/Release/notarize.sh) relies on environment variables (`DEVELOPER_ID_APP`, `APPLE_NOTARY_PROFILE`) outside CI. GitHub Actions [`release.yml`](../.github/workflows/release.yml) runs `build-universal.sh` ad-hoc (`-`) without Apple secrets, requiring manual `xattr -dr com.apple.quarantine` for users. Missing CI secret provisioning runbook (`MACOS_CERTIFICATE_P12`, `APP_STORE_CONNECT_API_KEY_P8`) and certificate expiry rotation calendar.
- **Notarization Signing Order (`--deep` Flag Warning):** Both `build-universal.sh` (`L53`) and `notarize.sh` (`L18`) use `codesign --deep` across `SparkleSFTP.app`. While sufficient for ad-hoc verification, Apple notarization strictly recommends signing nested frameworks and Sparkle 2 XPC helpers (`Sparkle.framework/Versions/B/XPCServices/*.xpc`, `Autoupdate`, `Updater.app`) individually inside-out before signing the outer bundle, rather than `--deep`.
- **Sparkle Ed25519 Key Management & Appcast Gap (`TD-03`):**
  - [`Info.plist:34`](../App/Resources/Info.plist#L34) ships placeholder `SUPublicEDKey = REPLACE_WITH_PRODUCTION_ED25519_PUBLIC_KEY`. `release.yml` produces `.dmg` + `.sha256` without running Sparkle's `generate_appcast` or uploading `appcast.xml` to GitHub Releases.
  - Because `SUPublicEDKey` holds a single Ed25519 public key, migrating/rotating keys later without stranding old clients requires maintaining an intermediate bridge release signed by the old key that updates `SUPublicEDKey` (or dual-signing appcasts during transition). Currently no key-escrow or rotation runbook exists.
- **Universal 2 Reproducibility & Resource Bundles (Fixed):** Fixed `Tools/Release/build-universal.sh` during this audit to copy SwiftPM `SparkleSFTP_*.bundle` artifacts into `Contents/Resources/` and hardened `LocalizationCatalog` / `AppDelegate` against SwiftPM's `Bundle.module` `fatalError` accessor. Note that `SwiftTerm`, `swift-crypto`, and `swift-nio` `.bundle` outputs do not carry runtime lookups in this codebase today, whereas `Package.swift` uses mutable branchless version ranges (`..<"0.16.0"`, `..<"1.99.0"`) backed accurately by committed `Package.resolved` for build reproducibility.

---

## Prioritized 90-Day & 12-Month Remediation Roadmap

### 90-Day Stabilization & High-ROI Hardening Plan

1. **Provision Signing, Notarization & Live Sparkle Appcast Pipeline (`Days 1–21`, `TD-03`)**
   - Add inside-out signing of `Sparkle.framework` XPCs in `notarize.sh` (replacing `--deep`).
   - Generate production Ed25519 key pair in offline HSM/1Password escrow, populate `SUPublicEDKey` in `Info.plist`, wire `generate_appcast` into `.github/workflows/release.yml` using `SPARKLE_ED_PRIVATE_KEY` secret, propagate `AutoUpdateSettings.customFeedURL` to `SPUUpdater`, and document rotation procedure in `SECURITY.md`.
2. **Activate Deterministic Docker Interop Suite (`Days 15–45`, `TD-02`)**
   - Pin Docker image tags/digests in `Tools/TestServers/docker-compose.test.yml`, generate disposable FTPS TLS certs & `vsftpd`/`proftpd` configs in `fixtures/`, and implement gated `DockerInteropTests` reading `SPARKLESFTP_LIVE_DOCKER_TESTS=1` covering SFTP, SCP, Plain FTP, Explicit FTPS (`AUTH TLS`), and Implicit FTPS.
3. **Transfer Durability & Terminal Hygiene Polish (`Days 30–60`, `TD-05`, `TD-06`, `TD-07`, `TD-12`)**
   - Add `PRAGMA user_version`, `PRAGMA quick_check` corrupt-DB quarantine, `.paused` restore, jittered retry backoff, and state-transition checkpoint throttling (`TransferJournal` / `TransferQueue`).
   - Stream SCP downloads in chunks instead of buffering `stdout`; preserve `TerminalView` instances across split/drawer toggles, enforce scrollback line limit, coalesce PTY output batches, and migrate `TerminalViewRepresentable` `DispatchQueue.main.async` to `Task { @MainActor }`.
4. **Static Gate Tightening (`Days 60–90`, `TD-08`, `TD-09`)**
   - Decide & wire or prune unused `FeatureFlags` (`isSCPFallbackEnabled`, `isPortForwardingEnabled`, `isTouchIDGateEnabled`).
   - Lower `.swiftlint.yml` `cyclomatic_complexity` warning threshold toward `6` and configure `sonar-project.properties` if SonarCloud/SonarQube hosting is adopted.

### 12-Month Architectural Evolution Roadmap

1. **Q1–Q2: `AppState` Sub-Store Decomposition & `NSTableView` Diffing (`TD-01`, `TD-04`)**
   - Break `AppState` into domain-scoped observable stores (`ConnectionStoreVM`, `TransferQueueVM`, `CommanderPaneVM`, `AppearanceLocaleVM`) and cache `AppStrings`/`activePalette` to eliminate 100ms progress fan-out across unrelated panes.
   - Replace full `NSTableView.reloadData()` with `CollectionDifference` row deltas (`TD-04`) plus CI performance benchmarks for 100K-entry directories.
2. **Q3: Security Parity Across Explicit FTPS & OpenSSH `known_hosts` (`TD-10`, `TD-11`)**
   - Implement explicit FTPS STARTTLS `SecTrust` + OCSP validation parity (`TLSCertificateValidator`) plus optional active FTP port configuration.
   - Add bidirectional OpenSSH `~/.ssh/known_hosts` import/export (including hashed `|1|` entries) cleanly into `HostTrustStore`.
3. **Q4: Platform Evaluation (`.macOS(.v14)` Migration Readiness)**
   - Once macOS 13 Ventura exits community support window, evaluate bumping `.macOS(.v13)` -> `.macOS(.v14)` in `Package.swift` to unlock zero-boilerplate `@Observable` property-level tracking (`Observation`), eliminating remaining `ObservableObject` fan-out cleanly.
