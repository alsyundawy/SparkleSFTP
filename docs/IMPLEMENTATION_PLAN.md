# 🖥️ SparkleSFTP — Implementation Plan, Workground & Task List

## Native macOS SFTP/FTP/SCP/SSH Commander — Swift 6 + SwiftUI

> [!IMPORTANT]
> Dokumen ini adalah sintesis mendalam dari analisis file spesifikasi awal (`aplikasi MacSFTP.txt`, yang kini distandardisasi menjadi **SparkleSFTP**) + riset web dan audit manifest terhadap sumber resmi GitHub (`apple/swift-nio-ssh`, `SwiftTerm`, `Sparkle`), Apple Developer Documentation, dan praktik komunitas Swift terkini (2024–2026).
>
> **Reconciled Implementation Baseline:** Sesuai hasil audit empiris dependensi dan target **macOS 13+** ([ADR-004](ADR/0004-direct-swift-nio-ssh-and-sftp-codec.md), [ADR-005](ADR/0005-macos13-sqlite3-journal-and-observable-object.md), [`TECHNICAL_SPECIFICATION.md`](TECHNICAL_SPECIFICATION.md)):
>
> - SSH & SFTP menggunakan **`apple/swift-nio-ssh` (`0.15.1` >= `0.14.1`)** + SFTP v3 binary codec internal (menggantikan `Citadel` yang mensyaratkan `.macOS(.v14)` dan fork `0.3.x`).
> - Secrets & TOFU menggunakan Apple **`Security.framework`** + **`LAContext`** langsung (menggantikan `GlasSecretStore` `.macOS(.v26)`).
> - Persistensi menggunakan **JSON (`ConnectionStore`)** + **`SQLite3` WAL (`TransferJournal`)** (menggantikan `SwiftData` macOS 14+).
> - State presentation menggunakan **`@MainActor ObservableObject`** (kompatibel macOS 13+).
> - Lihat status eksekusi terkini di [`TASK_LIST.md`](TASK_LIST.md), [`WORKGROUND.md`](WORKGROUND.md), [`../TODO.md`](../TODO.md), dan [`../DOCNOTE.md`](../DOCNOTE.md).

---

## 🎯 Visi Produk

**SparkleSFTP** adalah aplikasi native macOS yang menggabungkan:

- **Dual-pane Commander** (WinSCP-style) dengan UI modern & elegan
- **Protokol lengkap**: SFTP, FTP, FTPS (Explicit/Implicit), SCP, SSH Terminal
- **Keamanan sejak hari pertama**: Keychain + Touch ID, tanpa Electron, tanpa overhead runtime asing

---

## 🏗️ Tech Stack Final (Evidence-Based)

| Lapisan | Teknologi | Alasan |
| :-------- | :---------- | :------- |
| **Bahasa** | Swift 6 | Strict concurrency, actor isolation, Sendable enforcement |
| **UI** | SwiftUI + AppKit Bridge | Native macOS HIG; `NSTableView` via `NSViewRepresentable` untuk performa file list |
| **SSH/SFTP** | `apple/swift-nio-ssh 0.15.1` + Native SFTP v3 Codec | Async/await SFTP v3 (`SFTPPacketCodec`), PTY, Jump/Forwarding, patch CVE-2026-43798, macOS 13+ |
| **FTP/FTPS** | `libcurl` (`Clibcurl` C Bridge + `SecTrust`) | FTP + Explicit/Implicit TLS 1.2+; `CURLOPT_PROTOCOLS_STR="ftp,ftps"` (tanpa `libssh`) |
| **Terminal** | `SwiftTerm 1.20.0` (`migueldeicaza/SwiftTerm`) | VT100/xterm engine matang; integrasi SwiftUI via `NSViewRepresentable` |
| **Keychain** | Apple `Security.framework` + `LocalAuthentication` | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + Touch ID (`LAContext`) |
| **Persistence** | JSON (`ConnectionStore`) + `SQLite3` WAL (`TransferJournal`) | Pemisahan tegas metadata ↔ rahasia, kompatibel penuh macOS 13+ |
| **Concurrency** | Swift Actors + async/await + AsyncStream | Thread-safe tanpa GCD; `TransferQueue` sebagai actor terisolasi |
| **Testing** | Swift Testing + Docker SSH/FTP fixtures | Integration test deterministik terhadap server disposable |
| **CI/CD** | GitHub Actions | Build + unit test otomatis |
| **Distribusi** | Developer ID + Notarization + Sparkle | DMG direct distribution; opsional Mac App Store |

> [!NOTE]
> **Mengapa Citadel vs libssh2?** Citadel memiliki API async/await yang bersih, dukungan PTY, jump host, dan dokumentasi aktif. libssh2 adalah kandidat fallback untuk SCP legacy. Apple DTS sendiri merekomendasikan SwiftNIO SSH sebagai dasar.

---

## 📐 Arsitektur Sistem

```mermaid
flowchart TD
    UI["🖥️ UI LAYER\nSwiftUI Views\nDualPaneView · SessionSidebar\nTransferQueueView · TerminalView"]
    VM["📦 VIEW MODEL / STATE\n@Observable ViewModels\nConnectionVM · PaneVM · TransferManager"]
    SL["⚙️ SERVICE LAYER\nRemoteFileService Protocol\nSessionCoordinator · TransferScheduler"]
    PA["🔌 PROTOCOL ADAPTERS\nSFTPService (Citadel)\nFTPService (libcurl)\nSSHService (Citadel PTY)"]
    SEC["🔐 SECURITY LAYER\nKeychainService · HostTrustStore\nTLS Certificate Validation\nApp Sandbox Bookmarks"]
    PERS["💾 PERSISTENCE\nSwiftData (session metadata)\nTransferJournal (durable state)"]

    UI --> VM
    VM --> SL
    SL --> PA
    SL --> SEC
    SL --> PERS
    PA --> SEC
```

### Aturan Dependensi (Non-Negotiable)

```text
App → ApplicationCore → Domain
ProtocolAdapters → Domain
Security → Domain
Persistence → Domain
```

> [!CAUTION]
> **UI tidak boleh pernah** memanggil Citadel, libcurl, atau Keychain secara langsung. View tidak menyimpan password. Transfer tidak bergantung pada lifecycle sebuah window.

---

## 🗂️ Struktur Repository

```text
SparkleSFTP/
├── App/
│   ├── SparkleSFTPApp.swift
│   ├── AppDelegate.swift
│   ├── AppEnvironment.swift           # Dependency injection root
│   └── AppLifecycle.swift
│
├── Packages/
│   ├── Core/                          # Domain models, interfaces, errors
│   │   ├── Domain/
│   │   ├── Interfaces/                # RemoteFileSystem, TransferEngine, CredentialStore
│   │   ├── Models/                    # Session, RemoteFile, TransferTask, CredentialRef
│   │   └── Errors/                    # AppError enum, user-friendly messages
│   │
│   ├── Networking/                    # Protocol adapters (tidak import SwiftUI)
│   │   ├── SSH/                       # SSHService.swift (Citadel)
│   │   ├── SFTP/                      # SFTPService.swift + SCPCompatibilityAdapter.swift
│   │   ├── FTP/                       # FTPService.swift (libcurl C bridge)
│   │   ├── FTPS/                      # Explicit + Implicit TLS
│   │   └── Proxy/                     # ProxyJump / bastion support
│   │
│   ├── TransferEngine/
│   │   ├── Queue/                     # TransferQueue actor
│   │   ├── Scheduler/                 # Admission, concurrency, priority
│   │   ├── Workers/                   # TransferWorker (satu job per worker)
│   │   ├── Resume/                    # Checkpoint & partial file handling
│   │   ├── Recovery/                  # TransferJournal, crash recovery
│   │   └── Verification/             # SHA-256, atomic rename, finalization
│   │
│   ├── FileManager/
│   │   ├── Local/                     # LocalFileService (FileManager + FSEvents)
│   │   ├── Remote/                    # RemoteFileService implementations
│   │   ├── Commander/                 # DualPane state, focus management
│   │   ├── Comparison/               # DirCompare, SyncPlanner, SyncExecutor
│   │   └── Operations/               # Copy, move, delete, rename
│   │
│   ├── Security/
│   │   ├── Keychain/                  # KeychainService, SecretReference
│   │   ├── HostKeys/                  # HostTrustStore, TOFU fingerprint
│   │   ├── Certificates/             # TLS validation, SecTrust
│   │   ├── Identity/                  # Private key import (PEM/OpenSSH)
│   │   └── Audit/                    # Credential redaction logging
│   │
│   ├── Terminal/
│   │   ├── Sessions/                  # TerminalSession, PTY lifecycle
│   │   ├── Emulator/                  # SwiftTerm NSViewRepresentable wrapper
│   │   ├── Snippets/                  # Command templates
│   │   └── Forwarding/               # Port forwarding manager
│   │
│   ├── Synchronization/
│   │   ├── Scanner/                   # Snapshot enumerator
│   │   ├── Comparator/               # Size/time/hash comparison
│   │   ├── Planner/                   # Pure sync plan (no mutations)
│   │   └── Executor/                  # Plan execution via TransferEngine
│   │
│   ├── Persistence/
│   │   ├── SwiftData/                 # Session metadata models
│   │   ├── Repositories/             # SessionStore, TransferJournal
│   │   └── Migrations/               # Schema versioning
│   │
│   └── DesignSystem/
│       ├── Components/               # Reusable SwiftUI components
│       ├── Colors/                    # Semantic color tokens
│       ├── Typography/               # Font scale
│       └── Themes/                    # Light/Dark/Custom accent
│
├── Features/                          # Feature-level SwiftUI Views + ViewModels
│   ├── Dashboard/
│   ├── Connections/                   # ConnectionManagerView, ConnectionEditorView
│   ├── Commander/                     # DualPaneView, FilePaneView, PathBar
│   ├── Transfers/                     # TransferQueueView, TransferRowView
│   ├── Terminal/                      # TerminalTabView, TerminalSplitView
│   ├── Synchronization/              # SyncProfileView, SyncPreviewView
│   ├── Settings/                      # Preferences, keyboard shortcuts
│   └── Diagnostics/                  # Connection health, security dashboard
│
├── Tests/
│   ├── UnitTests/
│   ├── IntegrationTests/             # Docker SSH/FTP server fixtures
│   ├── ProtocolTests/                # SFTP/FTP/SCP compatibility matrix
│   ├── SecurityTests/                # Host key, TLS, secret leakage
│   └── UITests/                      # Connect → Browse → Transfer → Disconnect
│
├── Tools/
│   ├── TestServers/                   # Docker Compose: OpenSSH, vsftpd, ProFTPD
│   └── Release/                       # Notarization, Sparkle scripts
│
└── docs/
    ├── ARCHITECTURE.md
    ├── CODE_REVIEW_14_PILLARS.md
    ├── IMPLEMENTATION_PLAN.md
    ├── ADR/                           # Architecture Decision Records
    └── ROADMAP.md
```

---

## 🔑 Domain Interfaces Utama

> [!CAUTION]
> **CRITICAL FIXES dari Code Review** — Interface di bawah sudah diperbaiki berdasarkan 14-pillar review. Lihat [CODE_REVIEW_14_PILLARS.md](CODE_REVIEW_14_PILLARS.md) untuk detail lengkap setiap finding.

```swift
// MARK: - Rich Progress Type (FIX: BUG-001, SYN-002)
// Gunakan typed struct, bukan AsyncStream<Double> sebagai parameter
struct TransferProgress: Sendable {
    let bytesTransferred: Int64
    let totalBytes: Int64
    let bytesPerSecond: Int64
    var percentage: Double { guard totalBytes > 0 else { return 0 }; return Double(bytesTransferred) / Double(totalBytes) }
    var estimatedTimeRemaining: Duration? {
        guard bytesPerSecond > 0 else { return nil }
        return .seconds((totalBytes - bytesTransferred) / bytesPerSecond)
    }
}

// MARK: - Strongly-Typed Remote Path (FIX: READ-002)
struct RemotePath: Sendable, Hashable, ExpressibleByStringLiteral {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue.hasPrefix("/") ? rawValue : "/" + rawValue }
    init(stringLiteral value: String) { self.init(rawValue: value) }
    var filename: String { URL(fileURLWithPath: rawValue).lastPathComponent }
    var parent: RemotePath { RemotePath(rawValue: URL(fileURLWithPath: rawValue).deletingLastPathComponent().path) }
}

// MARK: - Core Protocol Contract (FIX: BUG-001 — closure, bukan AsyncStream sebagai param)
protocol RemoteFileSystem: Sendable {
    func connect() async throws
    func listDirectory(at path: RemotePath) async throws -> [RemoteFile]
    // FIX: Gunakan callback closure, bukan AsyncStream sebagai input parameter
    func download(
        from: RemotePath,
        to: URL,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws
    func upload(
        from: URL,
        to: RemotePath,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws
    func delete(at path: RemotePath) async throws
    func rename(from source: RemotePath, to destination: RemotePath) async throws
    func createDirectory(at path: RemotePath) async throws
    func metadata(at path: RemotePath) async throws -> RemoteFileMetadata
    func disconnect(policy: DisconnectPolicy) async throws  // FIX: LOG-006 + SYN-001
}

enum DisconnectPolicy: Sendable {
    case cancelAllTransfers
    case waitForCompletion
    case pauseAndDisconnect
}

// MARK: - AppError (FIX: BUG-002 — explicit Sendable conformance)
enum AppError: Error, Sendable, LocalizedError {
    case connectionTimeout(host: String)
    case hostUnreachable(host: String)
    case hostKeyMismatch(expected: String, got: String)
    case authenticationFailed(method: String)
    case credentialNotFound(service: String)
    case transferFailed(reason: String)
    case diskFull(requiredBytes: Int64, availableBytes: Int64)
    case permissionDenied(path: String)
    case checksumMismatch(expected: String, actual: String)
    case pathTraversal(attempted: String)      // SEC-003 CWE-22
    case symlinkTraversal(destination: String) // SEC-004 CWE-59
    case planExpired                           // LOG-003
    case syncConflict(path: String)
    var errorDescription: String? { /* localized */ return String(describing: self) }
}

// MARK: - Transfer Task (FIX: BUG-003 — pisahkan metadata statis dari state dinamis)
struct TransferTaskMetadata: Identifiable, Sendable {  // Jarang berubah
    let id: UUID
    let source: TransferEndpoint
    let destination: TransferEndpoint
    let totalBytes: Int64
    let priority: TransferPriority
    let createdAt: Date
}

// MARK: - Transfer Status (Sendable, explicit associated values)
enum TransferStatus: Sendable {
    case queued, preparing, connecting
    case transferring(bytesPerSecond: Int64)
    case verifying, finalizing, completed
    case paused, interrupted, cancelled
    case failed(AppError), needsReview
}

// MARK: - Host Trust State Machine (FIX: LOG-001 — complete state machine)
enum HostTrustState: Sendable {
    case unknown
    case pendingUserDecision(fingerprint: String)
    case trusted(fingerprint: String, since: Date)
    case rejected
    case mismatch(expected: String, got: String)
    case corrupted
}

// MARK: - Sync Plan with Expiry (FIX: LOG-003)
struct SyncPlan: Sendable {
    let createdAt: Date
    let expiresAt: Date   // Default: createdAt + 60 seconds
    let actions: [SyncAction]
    var isStale: Bool { Date() > expiresAt }
}
```

---

## 🗺️ Workground (Area Kerja)

| # | Workground | Deskripsi | Dependensi |
| :-- | :----------- | :---------- | :----------- |
| **WG-1** | Fondasi Proyek & Domain Layer | Xcode setup, modul, model domain, protocol kontrak, error handling, CI | — |
| **WG-2** | Core SSH & SFTP Engine | Citadel integration, auth (password/key/2FA), SFTP client, host key TOFU | WG-1 |
| **WG-3** | FTP/FTPS Engine | libcurl C bridge, async/await wrapper, explicit/implicit TLS | WG-1 |
| **WG-4** | UI Shell & Dual-Pane | SwiftUI window, NavigationSplitView, HSplitView, sidebar, toolbar, FilePaneView | WG-1 |
| **WG-5** | Terminal SSH Terintegrasi | SwiftTerm NSViewRepresentable, PTY channel via Citadel, multi-tab | WG-2, WG-4 |
| **WG-6** | Transfer Queue & Drag-and-Drop | TransferQueue actor, progress via AsyncStream, drag-drop, conflict dialog | WG-2, WG-3, WG-4 |
| **WG-7** | Persistensi & Keamanan | GlasSecretStore/Keychain, SessionStore JSON, Touch ID, SSH config parser | WG-1 |
| **WG-8** | Fitur Lanjutan | Remote editor, port forwarding, command snippets, dir compare, S3 opsional | WG-2, WG-5, WG-6 |
| **WG-9** | Testing, Polish & Distribusi | Unit/integration/UI tests, notarization, Sparkle, dokumentasi | Semua WG |

---

## 📋 Phased Roadmap (8 Fase)

```mermaid
flowchart LR
    P1["Phase 01\nResearch &\nArchitecture\nMinggu 1–2"]
    P2["Phase 02\nFoundation &\nUI Framework\nMinggu 3–4"]
    P3["Phase 03\nConnection &\nSecurity\nMinggu 5–7"]
    P4["Phase 04\nProtocol Engine\nMinggu 8–11"]
    P5["Phase 05\nCommander\nFile Manager\nMinggu 12–14"]
    P6["Phase 06\nTransfer Engine\nMinggu 15–17"]
    P7["Phase 07\nAdvanced Features\nMinggu 18–21"]
    P8["Phase 08\nQA & Release\nMinggu 22–24"]

    P1 --> P2 --> P3 --> P4 --> P5 --> P6 --> P7 --> P8
```

### Phase 01 — Research & Architecture (Minggu 1–2)

- Audit library dan lisensi (Citadel MIT, SwiftTerm MIT, libcurl MIT/curl)
- Proof-of-concept: SSH connect → auth → SFTP listing → upload/download → cancel
- Proof-of-concept: libcurl FTP/FTPS → TLS valid & invalid certificate test
- Threat modeling: trust boundary, attack surface, credential lifecycle
- Finalisasi minimum macOS (target: **macOS 13 Ventura**, ideal: **macOS 14 Sonoma**)
- Pilihan ADR: backend SSH, database metadata, distribusi, file table, transfer recovery

### Phase 02 — Foundation & UI Framework (Minggu 3–4)

- Xcode project (Swift 6, Universal Binary arm64+x86_64)
- SPM dependencies: Citadel, SwiftTerm, GlasSecretStore
- SwiftUI + AppKit integration skeleton
- Design system: color tokens, typography, SF Symbols 6, dark/light
- SwiftData schema v1 + Keychain wrapper
- CI/CD (GitHub Actions: build + test)

### Phase 03 — Connection & Security (Minggu 5–7)

- ConnectionProfile CRUD (SwiftData)
- KeychainService: save/load/delete password, passphrase, private key
- Host key TOFU: fingerprint SHA-256, known_hosts style, changed-key blocking
- SSH auth: password, ed25519/RSA key, keyboard-interactive (2FA)
- TLS certificate validation: chain + hostname + expiry verification
- SSH config parser (`~/.ssh/config`)

### Phase 04 — Protocol Engine (Minggu 8–11)

- SFTPService: listDirectory, download, upload, rename, delete, mkdir, stat
- SCPCompatibilityAdapter.swift: SCP fallback via `execCommand`
- SSHService: PTY channel, session lifecycle, reconnect, keepalive
- FTPService via libcurl: listing, upload, download, explicit/implicit FTPS
- Protocol capability detection (resume, rename, permissions)
- Integration tests terhadap Docker server fixtures

### Phase 05 — Commander File Manager (Minggu 12–14)

- MainWindow: `NavigationSplitView` sidebar + `HSplitView` dual pane
- `FilePaneView` (reusable local/remote): `NSTableView` via `NSViewRepresentable`
- PathBar + breadcrumb + Back/Forward/Up navigation
- Multi-select, range select, keyboard shortcuts (Tab switch pane)
- Commander keys: F5 Copy, F6 Move, F7 New Folder, F8 Delete
- Context menu, Quick Look (`QLPreviewPanel`), Inspector view
- Drag-and-drop: local ↔ remote, Finder interop

### Phase 06 — Transfer Engine (Minggu 15–17)

- `TransferQueue` actor: bounded concurrency (max 3 simultaneous), priority
- `TransferJournal`: durable state, crash recovery, interrupted job reconciliation
- Progress via `AsyncStream<Double>`, throttled UI updates (tidak flood MainActor)
- Conflict resolution: Ask/Skip/Rename/Overwrite
- Pause/resume: checkpoint-based, hanya jika backend mendukung
- Atomic upload: download ke temp file → verify → rename atomik
- `TransferQueueView`: progress bar, speed, ETA, retry, cancel

### Phase 07 — Advanced Features (Minggu 18–21)

- SwiftTerm integration: `TerminalViewRepresentable`, PTY dari SSHService
- Multi-tab terminal, horizontal/vertical split
- Port forwarding: local/remote tunnel, preset layanan
- Directory comparison: snapshot enumerator + pure SyncPlanner
- Sync dry-run preview UI (create/update/delete terpisah, destructive confirmation)
- Remote file editor: temp workspace + FSEvents + auto-upload on save
- Import FileZilla sitemanager.xml, WinSCP .ini
- Localization (EN + ID)

### Phase 08 — QA & Release (Minggu 22–24)

- Full protocol regression terhadap semua Docker fixtures
- Security audit: credential leakage, log redaction, path traversal
- Performance profiling: 10K+ file listing, 10GB transfer, memory bounds
- Accessibility: VoiceOver, keyboard-only navigation
- Code signing + notarization (`xcrun notarytool`)
- Sparkle framework auto-update
- DMG packaging + Universal Binary verification
- Beta distribution + feedback triage

---

## ✅ Master TODO & Task List (122+ Tasks)

### EPIC-01 — Project Foundation

- [x] **TASK-001** Create SwiftPM / macOS App manifest (`Package.swift`, SwiftUI lifecycle, Swift 6 — per [ADR-004](ADR/0004-direct-swift-nio-ssh-and-sftp-codec.md))
- [x] **TASK-002** Configure deployment target (macOS 13+, Universal Binary `x86_64 arm64` verified via `lipo -archs`)
- [x] **TASK-003** Configure Swift Package Manager with **PINNED VERSIONS** (reconciled per [ADR-004](ADR/0004-direct-swift-nio-ssh-and-sftp-codec.md) & [ADR-005](ADR/0005-macos13-sqlite3-journal-and-observable-object.md))
  - `apple/swift-nio-ssh`: **`0.15.1` (`>= 0.14.1`)** + internal RFC SFTP v3 binary codec (`SFTPPacketCodec`), patching **CVE-2026-43798** (supersedes `Citadel`)
  - `SwiftTerm`: **`1.20.0`** (`"1.19.0" ..< "1.99.0"`)
  - `Sparkle`: **`2.10.1`** (`"2.10.1" ..< "3.0.0"`)
  - `KeychainService` native over Apple `Security.framework` + `LAContext` (`WhenUnlockedThisDeviceOnly`, supersedes `GlasSecretStore`)
  - `Clibcurl` locked to `ftp,ftps` (`CURLOPT_PROTOCOLS_STR`) over macOS `libcurl` (`libssh2`, zero `libssh` surface — mitigates **CVE-2025-15224**)
- [x] **TASK-004** Configure SwiftLint (`swiftlint --strict`, `0` violations) + SwiftFormat (`.swiftformat`)
- [x] **TASK-005** Configure unit testing (`Swift Testing` framework — 35 tests in 9 suites)
- [x] **TASK-006** Configure CI/CD (GitHub Actions: `.github/workflows/ci.yml`, verified by `actionlint`)
- [ ] **TASK-007** Configure production Apple Developer ID code signing (`Tools/Release/notarize.sh` ready; local ad-hoc `codesign` verified)
- [x] **TASK-008** Create architecture documentation (`README.md`, `README-id.md`, `docs/ADR/0001`–`0005`)
- [x] **TASK-009** Create App Sandbox entitlements (`App/SparkleSFTP.entitlements`):

  ```xml
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.files.user-selected.read-write</key><true/>
  ```

- [x] **TASK-010** Define domain contracts: `RemoteFileSystem`, `TransferEngine`, `CredentialStoreProtocol`, `HostTrustStoreProtocol`

### EPIC-02 — Design System

- [x] **TASK-011** Design color system (`SparkleTheme.Colors` semantic tokens, light/dark)
- [x] **TASK-012** Design typography scale (`SparkleTheme.Typography` SF Pro, SF Mono)
- [x] **TASK-013** Design icon system (`SparkleTheme.Symbols` SF Symbols)
- [x] **TASK-014** Create reusable components: `StatusPill`, `TransferProgressBar`, `SecurityWarningBanner`
- [x] **TASK-015** Create navigation sidebar (`NavigationSplitView` sidebar in `MainWindowView`)
- [x] **TASK-016** Create toolbar (Connect, Disconnect, Terminal, Sync, Security Diagnostics)
- [x] **TASK-017** Create tab system (multi-session tabs in `MainWindowView`)
- [x] **TASK-018** Create status bar (protocol, host, connection state, toggles)
- [x] **TASK-019** Create `HSplitView` dual-pane container (`DualPaneCommanderView`)
- [x] **TASK-020** Implement dark/light appearance + `.ultraThinMaterial` background
- [x] **TASK-021** Implement keyboard shortcuts (`.keyboardShortcut` `Cmd+T`, `Cmd+K`, `Cmd+R`, `Cmd+Shift+S`, `Cmd+Shift+N`, `Tab`)
- [x] **TASK-022** Implement accessibility labels + VoiceOver annotations

### EPIC-03 — Connection Manager

- [x] **TASK-023** Create `ConnectionProfile` model (`Sendable`, `Codable`)
- [x] **TASK-024** Create `ConnectionStore` (atomic JSON CRUD per [ADR-005](ADR/0005-macos13-sqlite3-journal-and-observable-object.md))
- [x] **TASK-025** Create `ConnectionManagerView` (sidebar list)
- [x] **TASK-026** Create `ConnectionEditorView` (form: host, port, user, auth, path)
- [x] **TASK-027** Implement protocol selector (SFTP/FTP/Explicit FTPS/Implicit FTPS/SCP)
- [x] **TASK-028** Implement authentication selector (password/key/agent/keyboard-interactive/anonymous)
- [x] **TASK-029** Implement server groups + favorites (`ServerGroup`, `isFavorite`)
- [x] **TASK-030** Implement connection search (`AppState.filteredProfiles`)
- [x] **TASK-031** Implement recent connections (`ConnectionProfile.lastConnectedAt`)
- [x] **TASK-032** Implement SSH config parser (`SSHConfigParser` `~/.ssh/config` → Host, HostName, Port, User, IdentityFile, ProxyJump)
- [x] **TASK-033** Implement FileZilla XML importer (`FileZillaImporter`)
- [x] **TASK-034** Implement WinSCP `.ini` importer (`WinSCPIniImporter`)

### EPIC-04 — Security Engine

- [x] **TASK-035** Implement `KeychainService` (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, zero iCloud sync)
- [x] **TASK-036** Implement `SecretReference` (`ConnectionProfile` never persists secrets)
- [x] **TASK-037** Implement private key loader (`PrivateKeyParser` + `SecurityScopedBookmarkManager`)
- [x] **TASK-038** Implement `HostTrustStore` (fingerprint SHA-256, 6-state TOFU flow)
- [x] **TASK-039** Implement host key verification UI (`HostKeyVerificationSheet`: Unknown → confirm; Changed → block)
- [x] **TASK-040** Implement TLS certificate validation (`TLSCertificateValidator` chain + hostname + OCSP)
- [x] **TASK-041** Implement secure logging (`DiagnosticsLogger` via `OSLog` privacy)
- [x] **TASK-042** Implement secure temporary file handling (`SecureTempDirectory` `0700` isolated dirs)
- [x] **TASK-043** Implement security-scoped bookmarks (`SecurityScopedBookmarkManager`)
- [x] **TASK-044** Implement Touch ID gate opsional (`LAContext` + biometric prompt)
- [x] **TASK-045** Implement security diagnostics view (`SecurityDiagnosticsView`)

### EPIC-05 — Protocol Engine

- [x] **TASK-046** Define `RemoteCapability` matrix + `RemoteConnection`
- [x] **TASK-047** Define `RemoteConnection` lifecycle interface + disconnect policy
- [x] **TASK-048** Define `RemoteFileSystem` interface
- [x] **TASK-049** Implement `SFTPService` (listDir, download, upload, metadata, rename, delete, mkdir, chmod)
- [x] **TASK-050** Implement `SSHClientService` (connect with `UserAuthSuccessEvent`, auth, exec, keepalive timeout, PTY, DirectTCPIP)
- [x] **TASK-051** Implement `SCPCompatibilityAdapter` (SCP fallback + POSIX single-quote escaping)
- [ ] **TASK-052** Implement multi-hop SSH jump host tunnel chaining in `SSHClientService` (model field `jumpHostProfileID` & parser ready; post-MVP enhancement)
- [x] **TASK-053** Implement `Clibcurl` C bridge (`Package.swift` + `Clibcurl.h` + `ClibcurlHelpers.c` linking `-lcurl`)
- [x] **TASK-054** Implement `FTPService` via libcurl (listing, upload, download, CWE-93 CRLF sanitizer)
- [x] **TASK-055** Implement explicit FTPS (`CURLOPT_USE_SSL` = `CURLUSESSL_ALL`, port 21)
- [x] **TASK-056** Implement implicit FTPS (`ftps://`, port 990, TLS preflight)
- [x] **TASK-057** Implement connection timeout + stall timeout watchdog
- [x] **TASK-058** Implement proxy support (`ProxyConfiguration`: SOCKS5, HTTP)
- [x] **TASK-059** Implement server capability detection matrix (`RemoteService` capabilities)

### EPIC-06 — File Manager

- [x] **TASK-060** Implement `LocalFileService` + `LocalDirectoryWatcher` (`DispatchSource`)
- [x] **TASK-061** Superseded mock stub via real `LocalFileService` + `MockRemoteFS` + `LoopbackSSHServer`
- [x] **TASK-062** Implement `FilePaneTableView` (`NSTableView` via `NSViewRepresentable` dengan cell reuse)
- [x] **TASK-063** Implement path bar (`DualPaneCommanderView` editable path input + parent navigation)
- [x] **TASK-064** Implement dual-pane navigation (focus tracking, `Tab` switch panel)
- [x] **TASK-065** Implement file sorting (`FileSortDescriptor`, folder-first stable sort)
- [x] **TASK-066** Implement multi-selection (`NSTableView` `allowsMultipleSelection`)
- [x] **TASK-067** Implement drag-and-drop upload (`.onDrop(of: [.fileURL])` Local → Remote)
- [x] **TASK-068** Implement file operations (upload, download, delete, rename, chmod)
- [x] **TASK-069** Implement permissions editor (`PermissionsEditorSheet` octal + symbolic `POSIXPermissions`)
- [x] **TASK-070** Implement Quick Look (`QuickLookCoordinator` + `QLPreviewPanel`)
- [x] **TASK-071** Implement remote file editor (`AppState.openRemoteFileInEditor` + `LocalDirectoryWatcher` auto-upload)
- [x] **TASK-072** Implement directory comparison & sync (`SyncPlanner` + `DirectoryScanner`)

### EPIC-07 — Transfer Engine

- [x] **TASK-073** Create `TransferTaskMetadata` / `TransferSnapshot` models (`Identifiable`, `Sendable`, full state machine)
- [x] **TASK-074** Create `TransferQueue` actor (bounded concurrency, priority queue, reentrancy guard, `deinit` cancel, per-host cap)
- [x] **TASK-075** Create `TransferScheduler` (admission control, global=3 / per-host=2 configurable limits)
- [x] **TASK-076** Implement upload flow (temp `.part` write → verify size → atomic rename)
- [x] **TASK-077** Implement download flow (temp `.part` write → `SHA256Verifier` → `PathValidator` → atomic move)
- [x] **TASK-078** Implement batch transfers (`enqueueSelectedTransfer` + multi-drop + `SyncExecutor`)
- [x] **TASK-079** Implement configurable concurrent transfers (`PreferencesView` Stepper → `TransferQueue.updateConcurrencyLimits`)
- [x] **TASK-080** Implement pause/resume (`ResumeValidator` remote mtime+size+partial verify)
- [x] **TASK-081** Implement retry (exponential backoff, skip auth/trust/integrity errors)
- [x] **TASK-082** Implement cancellation (clean task/socket/cURL teardown, no hanging sessions)
- [x] **TASK-083** Implement conflict resolver (`ConflictResolver` + `ConflictResolutionSheet`)
- [x] **TASK-084** Implement atomic upload (`.part` rename hanya setelah verifikasi)
- [x] **TASK-085** Implement `TransferJournal` actor (`SQLite3` WAL)
- [x] **TASK-086** Implement crash recovery (`reconcileInterruptedOnLaunch` → `interrupted`)
- [x] **TASK-087** Implement transfer statistics (speed, ETA, 100ms throttled stream)
- [x] **TASK-088** Create `TransferQueueView` (progress bar, speed, pause/resume/cancel/retry)
- [x] **TASK-089** Implement system notifications (`UNUserNotificationCenter` saat aplikasi ter-bundle `.app`)

### EPIC-08 — SSH Terminal Workspace

- [x] **TASK-090** Create `TerminalViewRepresentable` (`NSViewRepresentable` wrapping SwiftTerm `TerminalView` + cleanup + 100-tab test)
- [x] **TASK-091** Implement PTY channel (`SSHClientService.openPTYChannel` ↔ `TerminalSessionManager`)
- [x] **TASK-092** Implement `TerminalViewDelegate` (`sizeChanged` → `WindowChangeRequest`, `clipboardCopy`/`Read` → `NSPasteboard`)
- [x] **TASK-093** Implement terminal tabs (`TerminalWorkspaceView`)
- [x] **TASK-094** Implement split terminal (`HSplitView` split mode)
- [ ] **TASK-095** Implement SSH agent socket forwarding (post-MVP enhancement)
- [ ] **TASK-096** Implement interactive 2FA keyboard-interactive challenge sheet (post-MVP enhancement)
- [ ] **TASK-097** Implement ProxyJump multi-hop bastion execution (post-MVP enhancement)
- [x] **TASK-098** Implement local port forwarding (`PortForwardingManager` + live `DirectTCPIP` loopback test)
- [ ] **TASK-099** Implement remote `-R` port forwarding (`tcpip-forward` global request negotiation; post-MVP enhancement)
- [x] **TASK-100** Implement command snippets (`CommandSnippetStore` + `SnippetsSheet`)

### EPIC-09 — Synchronization

- [x] **TASK-101** Create `SyncProfile` / `SyncPlan` model
- [x] **TASK-102** Implement `DirectoryScanner` (async, cancel-safe, circular symlink loop guard)
- [x] **TASK-103** Implement tiered file comparison (size, mtime, SHA-256)
- [x] **TASK-104** Implement pure `SyncPlanner` (`expiresAt` 60s TTL tanpa mutasi)
- [x] **TASK-105** Implement sync preview UI (`SyncPreviewSheet` create/update/delete terpisah)
- [x] **TASK-106** Implement dry-run mode
- [x] **TASK-107** Implement one-way synchronization (`SyncExecutor` via `TransferQueue`)
- [ ] **TASK-108** Implement bidirectional sync (planned v1.5+)
- [x] **TASK-109** Implement exclusion patterns (`.git`, `.DS_Store`, glob `*.ext`)
- [x] **TASK-110** Implement deletion protection + explicit confirmation & pre-delete remote revalidation

### EPIC-10 — Quality Assurance & Release

- [x] **TASK-111** Unit tests: state machine, path parser, conflict rules, SSH config & importers (`CoreTests`, `PersistenceTests`, `FileManagerTests`, `SynchronizationTests`)
- [ ] **TASK-112** Live Docker Compose integration test execution (`Tools/TestServers/` tersedia; butuh container runtime Docker)
- [x] **TASK-113** SFTP interoperability tests via real encrypted `LoopbackSSHServer` (listing, upload, download, mkdir, rename, chmod, delete)
- [ ] **TASK-114** Live Docker FTPS server interop run (TLS self-signed rejection & FTP CRLF sanitizer terverifikasi; live FTPS container deferred ke Docker env)
- [x] **TASK-115** SSH authentication tests via real encrypted loopback SSH (password + Ed25519 public key)
- [x] **TASK-116** Host-key mismatch tests (TOFU unknown prompt, trusted reuse, rotated key `.hostKeyMismatch` hard block)
- [x] **TASK-117** TLS certificate validation test (ephemeral X.509 untrusted cert rejected by `TLSCertificateValidator`)
- [x] **TASK-118** Large-file SHA-256 verification test (`100MB` off-MainActor streaming tanpa memblokir UI thread)
- [x] **TASK-119** Interrupted-transfer recovery & cancel reentrancy tests (`TransferJournal` crash recovery + mid-transfer cancel)
- [x] **TASK-120** Memory & performance tests (10K+ `PaginatedFileWindow`, 100 PTY tab teardown)
- [x] **TASK-121** Security audit & automated tests (`PathValidator`, `KeychainService`, CRLF sanitizer, `swiftlint --strict`)
- [ ] **TASK-122** Apple Developer ID notarization (`xcrun notarytool submit` via `Tools/Release/notarize.sh` di release host; ad-hoc signing & entitlements terverifikasi lokal)
- [ ] **TASK-123** Live Sparkle signed update feed verification dengan `SUPublicEDKey` & appcast HTTPS rilis
- [x] **TASK-124** DMG packaging + Universal Binary verification (`lipo -archs` `x86_64 arm64`, `.app` + embedded `Sparkle.framework`, `.dmg` + `.sha256` terverifikasi lokal)
- [ ] **TASK-125** Beta distribution + feedback triage

---

## 🔐 Security Architecture (Non-Negotiable)

```mermaid
flowchart TD
    CP["ConnectionProfile\nhost, port, user, protocol\nkeyReference (ID only)"]
    KC["Apple Keychain\npassword · passphrase · private key\nprotected by ACL + optional Touch ID"]
    AS["Authenticated Session\nsecret loaded only when needed\ncleared after use"]
    LOG["DiagnosticsService\nOSLog privacy labels\nNO secrets in logs"]

    CP -->|"ref ID only"| KC
    KC -->|"secret on demand"| AS
    AS -->|"sanitized info"| LOG
```

### SSH Security Rules

| Aturan | Implementasi |
| :------- | :------------- |
| TOFU (Trust On First Use) | Fingerprint SHA-256 ditampilkan saat koneksi pertama; pengguna harus mengkonfirmasi secara eksplisit |
| Known-hosts database | Simpan fingerprint di Keychain (bukan UserDefaults) |
| Changed host key | Blokir koneksi; tampilkan peringatan berbeda dari "unknown" |
| Modern algorithms only | Disable algoritma usang (MD5, SHA-1) secara default |
| **DILARANG** | `acceptAnyHostKey = true` / `.acceptAnything()` di kode produksi |

### FTPS Security Rules

- TLS 1.2 minimum, TLS 1.3 preferred
- Certificate chain + hostname + expiry validation WAJIB
- **Tidak ada auto-downgrade** dari FTPS ke FTP plaintext
- Plain FTP → tampilkan warning merah eksplisit di UI

---

## ⚡ Testing Environment (Docker Compose)

```yaml
# docker-compose.test.yml
services:
  sftp-server:
    image: atmoz/sftp
    ports: ["2222:22"]
    # Test: password auth, key auth, SFTP-only account

  openssh-server:
    image: linuxserver/openssh-server
    ports: ["2223:2222"]
    # Test: SSH terminal, SCP, SFTP, ProxyJump

  ftp-server:
    image: fauria/vsftpd
    ports: ["21:21", "21100-21110:21100-21110"]
    environment:
      - FTP_USER=testuser
      - PASV_ADDRESS=127.0.0.1
    # Test: plain FTP, explicit FTPS with valid & invalid cert

  proftpd:
    image: instantlinux/proftpd
    ports: ["2121:21"]
    # Test: implicit FTPS port 990
```

**Wajib diuji per server:**

- File kecil 1KB · 100MB · 1GB · 10GB
- Filename Unicode · spasi · hidden files · symlink
- Permission denied · disk full · network disconnect · server restart
- TLS cert expired · host key changed · wrong password · interrupted transfer

---

## 📊 Fitur Priority Matrix

| Fitur | Priority | Phase |
| :------ | :--------- | :------ |
| **SFTP connection + Keychain** | P0 — MVP | Phase 03–04 |
| **Dual-pane file browser** | P0 — MVP | Phase 05 |
| **Upload/Download queue** | P0 — MVP | Phase 06 |
| **SSH host key verification** | P0 — MVP | Phase 03 |
| **SSH terminal (SwiftTerm)** | P0 — MVP | Phase 07 |
| FTP + explicit FTPS | P1 — v1.0 | Phase 04 |
| Transfer resume + recovery | P1 — v1.0 | Phase 06 |
| Directory comparison + sync | P1 — v1.0 | Phase 07 |
| FileZilla/SSH config import | P1 — v1.0 | Phase 03 |
| Implicit FTPS (port 990) | P1 — v1.0 | Phase 04 |
| Multi-tab sessions | P1 — v1.0 | Phase 07 |
| Touch ID vault unlock | P2 — v1.1 | Phase 08 |
| Port forwarding | P2 — v1.1 | Phase 07 |
| S3-compatible storage | P2 — v2.0 | Post-release |
| Remote-to-remote server transfer | P2 — v2.0 | Post-release |

---

## ⚠️ Risk Matrix

| Risiko | Level | Mitigasi |
| :------- | :------ | :--------- |
| SwiftUI `Table` performa (ribuan file) | 🔴 Tinggi | AppKit `NSTableView` via `NSViewRepresentable` |
| SSH algorithm compatibility | 🔴 Tinggi | Protocol compatibility test suite + Docker fixtures |
| FTPS passive connection (NAT/firewall) | 🔴 Tinggi | PASV mode testing, EPSV fallback |
| Large-file transfer (memory bounds) | 🔴 Tinggi | Streaming chunks, bounded buffer, backpressure |
| Transfer recovery (data integrity) | 🔴 Tinggi | TransferJournal actor + durable state + reconciliation |
| SFTP server differences (capability) | 🔴 Tinggi | Capability detection; tidak assume universal support |
| App Sandbox restrictions | 🔴 Tinggi | Security-scoped bookmarks; entitlements tepat |
| Library dependency updates | 🔴 Tinggi | Pinned SPM versions + security review per update |
| Keychain permission prompts | 🟡 Sedang | Credential lifecycle design; batch access per session |
| SSH terminal rendering edge cases | 🟡 Sedang | SwiftTerm + PTY tests + scrollback stress test |

---

## 🚦 MVP Acceptance Criteria (Release Gate)

**Aplikasi TIDAK boleh dirilis jika masih ada:**

- [ ] Host key berubah tetapi koneksi tetap dilanjutkan otomatis
- [ ] FTPS menerima sertifikat tidak valid secara default
- [ ] Password/private key muncul dalam log
- [ ] Transfer gagal ditandai `completed`
- [ ] Crash recovery menyebabkan overwrite tidak terkonfirmasi
- [ ] Sync menghapus target yang berbeda dari preview tanpa revalidasi
- [ ] Cancel menyebabkan session atau worker tidak pernah selesai
- [ ] Dependency atau lisensi distribusi belum jelas

**Semua item inti MVP terverifikasi hijau:**

- [x] Engine SFTP, FTP, explicit/implicit FTPS, dan SSH terminal tersedia dalam [`SparkleNetworking`](../Packages/Networking/) & [`SparkleTerminal`](../Packages/Terminal/) (interop SFTP & DirectTCPIP teruji live loopback; container Docker FTPS deferred ke host Docker)
- [x] Host key verification berjalan benar (`LoopbackSFTPIntegrationTests` memverifikasi unknown prompt, trusted reuse, dan blokir host key berubah via `.hostKeyMismatch`)
- [x] TLS certificate validation (`TLSCertificateValidator` menolak sertifikat self-signed X.509 di `SecurityTests`)
- [x] Dual-pane lokal/remote berfungsi + keyboard Commander shortcuts (`Cmd+T`, `Cmd+K`, `Cmd+R`, `Cmd+Shift+S`, `Cmd+Shift+N`, `Tab`)
- [x] Upload/download + batch + pause/resume + cancel + retry (`TransferEngineTests` + `LoopbackSFTPIntegrationTests`)
- [x] Conflict resolution + atomic upload (`ConflictResolver` + `.part` verify -> atomic rename)
- [x] Credentials tersimpan di Keychain, TIDAK di database (`ConnectionStoreTests` + `KeychainService`)
- [x] Interrupted transfer dapat direkonsiliasi setelah restart (`TransferJournal` SQLite3 WAL di `PersistenceTests`)
- [x] Tidak ada secret dalam log (`DiagnosticsLogger` + rule `no_password_in_logs` 0 pelanggaran)
- [x] Streaming SHA-256 & chunked I/O tanpa alokasi buffer penuh (`100MB` off-MainActor verified di `TransferEngineTests`)
- [x] Build Universal `arm64` + `x86_64` terverifikasi (`lipo -archs` `x86_64 arm64` + DMG `SparkleSFTP-0.2.0-mvp-universal.dmg`); [ ] notarization Apple Developer ID (`xcrun notarytool`) menunggu sertifikat produksi
- [x] `apple/swift-nio-ssh` `0.15.1` >= `0.14.1` terverifikasi (**CVE-2026-43798** mitigated)
- [x] `Clibcurl` mengunci `CURLOPT_PROTOCOLS_STR = "ftp,ftps"` (macOS `libcurl` memakai `libssh2/1.11.1`, permukaan SSH libcurl dimatikan — mitigasi **CVE-2025-15224**)
- [x] Semua Keychain items pakai `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (`SecurityTests` + `no_icloud_keychain_sync`)
- [x] Path traversal test: download dengan `../` → rejected (`CWE-22`) & FTP CRLF (`CWE-93`) teruji di `SecurityTests` / `NetworkingTests`
- [x] Symlink attack test: recursive download malicious symlink → rejected (`CWE-59`) teruji di `SecurityTests` & `SynchronizationTests`
- [x] Actor reentrancy test: cancel mid-transfer → `.cancelled` deterministik (`TransferEngineTests`)
- [x] PTY leak test: open/close 100 terminal tabs → clean teardown (`NetworkingTests`)
- [x] SHA-256 verification: off-MainActor untuk file `100MB` (`TransferEngineTests`)
- [ ] Sparkle runtime live appcast update check dengan kunci Ed25519 produksi & feed HTTPS (adapter `SparkleUpdaterService` sudah memblokir check tanpa `SUPublicEDKey` + HTTPS feed)
- [x] OSLog privacy redaction diaudit via `DiagnosticsLogger` & SwiftLint `no_password_in_logs`

---

## 📅 Timeline Estimasi

| Fase | Workground | Durasi |
| :----- | :----------- | :------- |
| Phase 01–02 | WG-1 (fondasi) | 2–4 minggu |
| Phase 03 | WG-7 (security + connection) | 3 minggu |
| Phase 04 | WG-2 + WG-3 (protocol engines) | 4 minggu |
| Phase 05 | WG-4 (UI dual-pane) | 3 minggu |
| Phase 06 | WG-6 (transfer engine) | 3 minggu |
| Phase 07 | WG-5 + WG-8 (terminal + advanced) | 4 minggu |
| Phase 08 | WG-9 (QA + release) | 3–4 minggu |
| **Total MVP** | **Semua kecuali WG-8 advanced** | **~18–22 minggu** |

> [!TIP]
> **Solo developer:** Fokus MVP dulu (Phase 01–06 = ~15 minggu). Gunakan `LocalFileService` stub agar UI dapat dikembangkan paralel dengan backend protocol engine. Jangan bangun semua protokol sekaligus.

---

## 📚 Referensi Resmi

| Sumber | URL |
| :------- | :---- |
| Citadel (SSH/SFTP) | <https://github.com/orlandos-nl/Citadel> |
| SwiftNIO SSH | <https://github.com/apple/swift-nio-ssh> |
| SwiftTerm | <https://github.com/migueldeicaza/SwiftTerm> |
| Apple Keychain Services | <https://developer.apple.com/documentation/security/keychain_services> |
| App Sandbox Entitlements | <https://developer.apple.com/documentation/security/app_sandbox> |
| RFC 959 (FTP) | <https://datatracker.ietf.org/doc/html/rfc959> |
| RFC 4217 (FTPS) | <https://datatracker.ietf.org/doc/html/rfc4217> |
| RFC 4251 (SSH Architecture) | <https://datatracker.ietf.org/doc/html/rfc4251> |
| libcurl Documentation | <https://curl.se/libcurl/c/> |
| Swift 6 Concurrency | <https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/> |

---

*Generated: 2026-11-11 | SparkleSFTP Implementation Plan v1.1 (originally drafted as MacSFTP, standardized to SparkleSFTP)*
*Skills applied: spec-driven-development · architecture-patterns · backend-architect · security-auditor · frontend-ui-engineering · source-driven-development · planning-and-task-breakdown · systematic-debugging · verification-before-completion · token-efficiency-zero-hallucination*
