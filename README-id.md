<p align="center">
  <img src="App/Resources/AppIcon.png" width="144" height="144" alt="Logo SparkleSFTP">
</p>

<h1 align="center">SparkleSFTP</h1>

<p align="center">
  <b>Klien SFTP, FTP/FTPS, SCP &amp; SSH Commander Dual-Pane Native macOS — Dibangun dengan Swift 6 &amp; SwiftUI</b><br>
  <i>Manajemen berkas berkinerja tinggi, keamanan Keychain + Touch ID, terminal PTY SwiftTerm terintegrasi, dan transfer atomik tahan crash tanpa beban Electron</i>
</p>

<p align="center">
  <a href="README.md"><b>English</b></a> &nbsp;|&nbsp; <b>Bahasa Indonesia</b>
</p>

<p align="center">
  <a href="docs/ROADMAP.md"><img src="https://img.shields.io/badge/Tahap-Full_MVP_Terealisasi-16a34a?style=for-the-badge&logo=github&logoColor=white" alt="Tahap: Full MVP Terealisasi"></a>
  <a href="https://apple.com/macos"><img src="https://img.shields.io/badge/Platform-macOS_13%2B_(Universal_2)-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Platform: macOS 13+ Universal 2"></a>
  <a href="https://developer.apple.com/swift/"><img src="https://img.shields.io/badge/Bahasa-Swift_6-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Bahasa: Swift 6"></a>
  <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/UI-SwiftUI_%2B_AppKit-007AFF?style=for-the-badge&logo=apple&logoColor=white" alt="UI: SwiftUI dan AppKit"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/Lisensi-MIT-2ea44f?style=for-the-badge" alt="Lisensi: MIT"></a>
  <a href="https://github.com/alsyundawy/SparkleSFTP/actions"><img src="https://img.shields.io/badge/CI%2FCD-GitHub_Actions-2088FF?style=for-the-badge&logo=githubactions&logoColor=white" alt="CI/CD GitHub Actions"></a>
</p>

> Pengembang Utama & Pemelihara:<br>
> **[`HARRY DERTIN SUTISNA ALSYUNDAWY (@alsyundawy)`](https://github.com/alsyundawy)** — [`ALSYUNDAWY IT SOLUTION`](https://alsyundawy.com)<br>
>
> 📋 **[`Rencana Implementasi`](docs/IMPLEMENTATION_PLAN.md)** &nbsp;|&nbsp;
> 🔍 **[`Review Kode 14 Pilar`](docs/CODE_REVIEW_14_PILLARS.md)** &nbsp;|&nbsp;
> 📐 **[`Arsitektur`](docs/ARCHITECTURE.md)** &nbsp;|&nbsp;
> 🗺️ **[`Roadmap & Release Gate`](docs/ROADMAP.md)** &nbsp;|&nbsp;
> 🔐 **[`Kebijakan Keamanan`](SECURITY.md)** &nbsp;|&nbsp;
> 📜 **[`Changelog`](CHANGELOG.md)** &nbsp;|&nbsp;
> 🤝 **[`Panduan Kontribusi`](CONTRIBUTING.md)** &nbsp;|&nbsp;
> 💖 **[`Dukungan via PayPal`](https://www.paypal.me/alsyundawy)**

---

> [!IMPORTANT]
>
> ### Status Repositori: Full MVP Terealisasi (Swift 6 + macOS 13+)
>
> Seluruh modul SwiftPM (`Package.swift`, `App/`, `Packages/*`, `Features/`, `Tests/*`, `Tools/*`) telah diimplementasikan dan diverifikasi dengan `swift build` serta `swift test`. Lihat [`docs/TECHNICAL_SPECIFICATION.md`](docs/TECHNICAL_SPECIFICATION.md), [`DOCNOTE.md`](DOCNOTE.md), [`TODO.md`](TODO.md), dan [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md).
>
> **Asal-Usul Proyek:** Awalnya dirancang dengan nama kerja `MacSFTP` dan distandardisasi menjadi **SparkleSFTP** dengan seluruh 55 temuan dari [`docs/CODE_REVIEW_14_PILLARS.md`](docs/CODE_REVIEW_14_PILLARS.md) terintegrasi sebelum penulisan kode dimulai.

---

## Navigasi

- [Ringkasan & Visi](#ringkasan--visi)
- [Tumpukan Teknologi](#tumpukan-teknologi)
- [Arsitektur Sistem](#arsitektur-sistem)
- [Garis Dasar Keamanan & Hardening](#garis-dasar-keamanan--hardening)
- [Struktur Repositori](#struktur-repositori)
- [Ringkasan Roadmap](#ringkasan-roadmap)
- [Dokumentasi & ADR](#dokumentasi--adr)
- [Kontribusi & Gerbang Kualitas](#kontribusi--gerbang-kualitas)
- [Lisensi](#lisensi)

---

## Ringkasan & Visi

**SparkleSFTP** adalah aplikasi Commander transfer berkas dan SSH native untuk macOS yang dirancang bagi engineer, sysadmin, dan alur kerja DevOps yang menginginkan produktivitas dual-pane bergaya WinSCP dengan ergonomi native macOS:

- **Pengalaman Commander Dual-Pane**: Panel Lokal ↔ Remote maupun Remote ↔ Remote berbasis AppKit `NSTableView` untuk daftar 100.000+ berkas yang mulus, pintasan papan ketik (`Tab`, `F5`–`F8`), Quick Look (`QLPreviewPanel`), dan seret-lepas Finder.
- **Dukungan Protokol Lengkap**: SFTP, Terminal SSH (PTY), FTPS Explicit/Implicit, FTP biasa (dengan peringatan keamanan eksplisit), serta fallback SCP terisolasi (`SCPCompatibilityAdapter`).
- **Mesin Transfer Terisolasi Actor**: Konkurensi terbatas per-host dan global, jeda/lanjutkan berbasis checkpoint dengan revalidasi metadata remote, pemulihan crash `TransferJournal`, serta unggahan atomik (tulis sementara → verifikasi SHA-256 → ganti nama atomik).
- **Keamanan Sejak Hari Pertama**: Apple Keychain terkunci perangkat (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), pembukaan opsional Touch ID, state machine verifikasi host key TOFU yang ketat, validasi TLS `SecTrust`, dan redaksi log `OSLog` tanpa kebocoran rahasia.

---

## Tumpukan Teknologi

| Lapisan | Teknologi | Tujuan & Standar Keamanan |
| :--- | :--- | :--- |
| **Bahasa** | Swift 6 | Strict concurrency, isolasi actor, penegakan `Sendable` |
| **Antarmuka UI** | SwiftUI + AppKit (`NSTableView`) | HIG macOS native dengan reuse sel tabel (`ObservableObject` untuk macOS 13+) |
| **SSH & SFTP** | `apple/swift-nio-ssh` (`0.15.1` >= `0.14.1`) + Codec SFTP v3 | SFTP v3 async/await, PTY, port forwarding; mitigasi CVE-2026-43798 & macOS 13+ |
| **FTP & FTPS** | Sistem `libcurl` (`Clibcurl` + `SecTrust`) | FTP TLS explicit/implicit terkunci `ftp,ftps` (tanpa `libssh` / CVE-2025-15224) |
| **Terminal SSH** | `SwiftTerm` (`1.20.0`) | Emulasi VT100/xterm via `NSViewRepresentable` + pembersihan PTY eksplisit |
| **Rahasia & Trust** | Apple `Security.framework` | Keychain ACL native (`WhenUnlockedThisDeviceOnly`), Touch ID (`LAContext`), `SecTrustEvaluateWithError` |
| **Persistensi** | JSON (`Codable`) + `SQLite3` WAL | JSON ringan untuk profil (`ConnectionStore`) + `TransferJournal` ACID (macOS 13+) |
| **Pengujian** | Swift Testing + Docker Compose | Fixture deterministik OpenSSH, vsftpd, dan ProFTPD |
| **Distribusi** | Universal 2 DMG + Sparkle | `arm64` + `x86_64`, notarized Developer ID, pembaruan bertanda Ed25519 |

---

## Arsitektur Sistem

```mermaid
flowchart TD
    UI["Lapisan UI (SwiftUI + NSTableView + SwiftTerm)"]
    VM["ViewModel (@MainActor ObservableObject)"]
    APP["Inti Aplikasi (AppState · TransferQueue · TransferScheduler)"]
    DOM["Lapisan Domain (RemoteConnection · RemoteFileSystem · AppError)"]
    PA["Adaptor Protokol (SFTP · SSH · FTP/FTPS · SCP)"]
    SEC["Lapisan Keamanan (KeychainService · HostTrustStore · SecTrust)"]
    PERS["Persistensi (ConnectionStore JSON · TransferJournal SQLite3)"]

    UI --> VM
    VM --> APP
    APP --> DOM
    PA --> DOM
    SEC --> DOM
    PERS --> DOM
    APP --> PA
    APP --> SEC
    APP --> PERS
    PA --> SEC
```

### Aturan Lapisan Wajib (Non-Negotiable)

1. `App -> SparkleFeatures -> Packages/*`; `ProtocolAdapters -> Domain`, `Security -> Domain`, `Persistence -> Domain`.
2. View dan ViewModel **dilarang** memanggil `NIOSSH`, `Clibcurl`, `SQLite3`, atau Keychain secara langsung.
3. Modul di `Packages/` **dilarang** mengimpor modul dari `Features/`.
4. Siklus hidup transfer berjalan di dalam `TransferQueue` actor — terpisah sepenuhnya dari siklus hidup jendela maupun tab.

---

## Garis Dasar Keamanan & Hardening

Setiap keputusan desain di SparkleSFTP menegakkan hasil audit pada [`docs/CODE_REVIEW_14_PILLARS.md`](docs/CODE_REVIEW_14_PILLARS.md):

| Kontrol | Standar / Referensi | Penegakan |
| :--- | :--- | :--- |
| **Keamanan Pre-Auth SSH** | CVE-2026-43798 | Pin `apple/swift-nio-ssh >= 0.15.1` (`>= 0.14.1`) di `Package.swift` |
| **Keamanan Auth SSH libcurl** | CVE-2025-15224 | Kunci `Clibcurl` ke `ftp,ftps` (`CURLOPT_PROTOCOLS_STR`); tanpa permukaan `libssh` |
| **Isolasi Keychain Perangkat** | CWE-312 / CWE-522 | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + aturan SwiftLint |
| **Validasi Sertifikat TLS** | CWE-295 | `SecTrustEvaluateWithError` + OCSP + tanpa auto-downgrade FTPS |
| **Kepercayaan Host SSH** | State Machine TOFU | Siklus 6-state; perubahan host key langsung memblokir koneksi |
| **Keamanan Path & Symlink** | CWE-22 / CWE-59 | Kanonisasi path ketat + validasi target symlink & loop |
| **Integritas Pembaruan** | Ed25519 + TLS | `UpdateConfigurationValidator` menolak feed non-HTTPS & key placeholder |
| **Redaksi Log** | CWE-532 | Label privasi `OSLog` + aturan SwiftLint `no_password_in_logs` |

---

## Struktur Repositori

### Struktur Repositori Swift 6 Terealisasi (Full MVP)

```text
SparkleSFTP/
├── Package.swift              # Manifest Swift 6.0 (.macOS(.v13), dependensi SPM ter-pin)
├── App/                       # Entry point executable, AppDelegate, SparkleUpdaterService, Info.plist, Entitlements
├── Packages/
│   ├── Clibcurl/              # Wrapper helper C non-variadik untuk libcurl sistem
│   ├── Core/                  # Model domain, RemotePath, AppError, Protocols, FeatureFlags
│   ├── DesignSystem/          # Token tema, komponen UI ulang, lokalisasi EN/ID AppStrings
│   ├── FileManager/           # LocalFileService, LocalDirectoryWatcher, POSIXPermissions, DualPaneState
│   ├── Networking/            # SFTPPacketCodec, SFTPService, SSHClientService, SCP, FTPService, Proxy
│   ├── Persistence/           # ConnectionStore (JSON), TransferJournal (SQLite3 WAL), Importer Konfigurasi
│   ├── Security/              # KeychainService, HostTrustStore, SecTrust, PathValidator, KeyParser, UpdateValidator
│   ├── Synchronization/       # DirectoryScanner, SyncPlanner (TTL 60 detik), SyncExecutor
│   ├── Terminal/              # SwiftTerm TerminalViewRepresentable, SessionManager, PortForwardingManager
│   └── TransferEngine/        # TransferQueue actor, TransferScheduler, ResumeValidator, SHA256Verifier
├── Features/                  # View SwiftUI + AppKit (Commander, Connections, Terminal, Transfers, Sync, Settings) & AppState
├── Tests/                     # 8 target uji (45 test di 11 suite Swift Testing, termasuk loopback SSH/SFTP terenkripsi)
├── Tools/
│   ├── Release/               # Skrip Universal 2 build-universal.sh, create-dmg.sh, notarize.sh
│   └── TestServers/           # Fixture Docker Compose (OpenSSH, vsftpd, ProFTPD) & skrip smoke test
├── .github/workflows/         # ci.yml, release.yml, mega-linter.yml, codeql.yml, jekyll-gh-pages.yml
└── docs/                      # Arsitektur, Spesifikasi Teknis, Model Keamanan, Workground, Review 14 Pilar, ADR 0001–0005
```

---

## Ringkasan Roadmap

| Fase | Tonggak | Fokus Utama & Status |
| :--- | :--- | :--- |
| **Fase 00** | Bootstrap Repositori | Tata kelola, spesifikasi, perbaikan 14 pilar, ADR, pagar CI & lint *(Selesai)* |
| **Fase 01–02** | Riset & Fondasi | Audit graf SPM ([ADR-004](docs/ADR/0004-direct-swift-nio-ssh-and-sftp-codec.md), [ADR-005](docs/ADR/0005-macos13-sqlite3-journal-and-observable-object.md)), `Package.swift`, `Core`, `DesignSystem` *(Selesai)* |
| **Fase 03** | Koneksi & Keamanan | `ConnectionStore`, `KeychainService`, TOFU `HostTrustStore`, `SecTrust`, Touch ID *(Selesai)* |
| **Fase 04** | Mesin Protokol | `SSHClientService` (`swift-nio-ssh 0.15.1`), codec SFTP v3, SCP, `Clibcurl` FTP/FTPS *(Selesai)* |
| **Fase 05** | Antarmuka Commander | `NSTableView` dual-pane, pintasan F5–F8, Quick Look, seret-lepas Finder *(Selesai)* |
| **Fase 06** | Mesin Transfer | `TransferQueue` actor, limit per-host, `SQLite3` `TransferJournal`, unggah atomik SHA-256 *(Selesai)* |
| **Fase 07** | Terminal & Sinkronisasi | PTY multi-tab/split `SwiftTerm`, port forwarding `-L`/`-R`, dry-run sync, EN/ID *(Selesai)* |
| **Fase 08** | QA & Rilis | 45 test di 11 suite, DMG Universal 2 (`release.yml`), CI/lint hijau; notarization produksi menunggu Developer ID *(Berjalan)* |

---

## Dokumentasi & ADR

- **[Rencana Implementasi (`docs/IMPLEMENTATION_PLAN.md`)](docs/IMPLEMENTATION_PLAN.md)** — Cetak biru lengkap, kontrak protokol, workground, 125 tugas, dan matriks pengujian Docker.
- **[Spesifikasi Teknis (`docs/TECHNICAL_SPECIFICATION.md`)](docs/TECHNICAL_SPECIFICATION.md)** — Graf target, kontrak toolchain, dan gerbang penerimaan milestone.
- **[Model Keamanan (`docs/SECURITY_MODEL.md`)](docs/SECURITY_MODEL.md)** — Kontrol ancaman, state machine TOFU, ACL Keychain, dan aturan TLS.
- **[Workground Breakdown (`docs/WORKGROUND.md`)](docs/WORKGROUND.md)** — Alur kerja domain (`WG-1`–`WG-9`) dan graf dependensi modul.
- **[Daftar Tugas (`docs/TASK_LIST.md`)](docs/TASK_LIST.md)** — Daftar tugas eksekusi di seluruh Milestone M1–M6.
- **[Catatan Teknis (`DOCNOTE.md`)](DOCNOTE.md)** — Temuan dependensi terverifikasi dan solusi kompatibilitas SDK.
- **[Review Kode 14 Pilar (`docs/CODE_REVIEW_14_PILLARS.md`)](docs/CODE_REVIEW_14_PILLARS.md)** — 55 temuan berbasis bukti di 14 pilar (bug, concurrency, memori, CVE keamanan, skalabilitas, dan linter).
- **[Arsitektur Sistem (`docs/ARCHITECTURE.md`)](docs/ARCHITECTURE.md)** — Batasan dependensi modul dan aturan concurrency.
- **[Roadmap & Gerbang Rilis (`docs/ROADMAP.md`)](docs/ROADMAP.md)** — Jadwal fase dan syarat mutlak gerbang rilis MVP.
- **[ADR-001: Tech Stack & Protokol](docs/ADR/0001-tech-stack-and-protocols.md)**
- **[ADR-002: Isolasi Keychain & Host Trust](docs/ADR/0002-security-keychain-and-host-trust.md)**
- **[ADR-003: Strategi Persistensi (JSON vs SwiftData)](docs/ADR/0003-metadata-persistence-swiftdata-vs-json.md)**
- **[ADR-004: Direct `swift-nio-ssh` & Engine SFTP v3 Native](docs/ADR/0004-direct-swift-nio-ssh-and-sftp-codec.md)**
- **[ADR-005: Jurnal SQLite3 & `ObservableObject` macOS 13+](docs/ADR/0005-macos13-sqlite3-journal-and-observable-object.md)**

---

## Kontribusi & Gerbang Kualitas

Kontribusi sangat terbuka! Harap baca [`CONTRIBUTING.md`](CONTRIBUTING.md) dan [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) sebelum mengirim pull request.

Pemeriksaan build, pengujian, dan linter lokal repositori dapat dijalankan dengan:

```bash
swiftlint lint --strict
swiftformat --lint .
swift build -j 2
swift test -j 2
markdownlint-cli2 "**/*.md" "#.build" "#DerivedData" "#.trunk"
yamllint -c .yamllint.yml .
shellcheck -s bash Tools/**/*.sh
actionlint
```

---

## Lisensi

Didistribusikan di bawah **Lisensi MIT**. Lihat berkas [`LICENSE`](LICENSE) untuk teks lengkapnya.

---

<p align="center">
  Dibuat untuk engineer macOS oleh <a href="https://github.com/alsyundawy"><b>@alsyundawy</b></a>
</p>
