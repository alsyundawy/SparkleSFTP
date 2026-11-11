# 🔍 SparkleSFTP — 14-Pillar Implementation Plan Code Review

## Critical Review Checklist — Evidence-Based, Web-Research-Grounded

> [!CAUTION]
> Ini adalah review **KRITIS** terhadap Implementation Plan SparkleSFTP. Setiap temuan didukung oleh riset web terhadap CVE database, Swift Evolution proposals, Apple Developer Documentation, dan GitHub issue trackers terkini (2024–2026). Semua harus ditangani sebelum eksekusi implementasi dimulai.

---

## 📊 Executive Summary

| Dimensi Review | Temuan | Severity Tertinggi |
| :--------------- | :------- | :------------------- |
| 🐛 Bug Review | 4 temuan | 🔴 CRITICAL |
| 📝 Syntax Review | 3 temuan | 🟡 MEDIUM |
| ⚡ Runtime Review | 5 temuan | 🔴 CRITICAL |
| 🧠 Logic Review | 6 temuan | 🔴 CRITICAL |
| 🧠 Memory Review | 4 temuan | 🔴 CRITICAL |
| 💀 Dead Code Review | 2 temuan | 🟡 MEDIUM |
| 🔁 Duplicate Code Review | 3 temuan | 🟡 MEDIUM |
| 🔄 Circular Dependency Review | 2 temuan | 🔴 CRITICAL |
| ⚡ Performance Bottleneck Review | 5 temuan | 🔴 CRITICAL |
| 🛡️ Security CVE/CWE Review | 7 temuan | 🔴 CRITICAL |
| 🔧 Maintainability Review | 4 temuan | 🟡 MEDIUM |
| 📈 Scalability Review | 3 temuan | 🟡 MEDIUM |
| 👁️ Readability Review | 3 temuan | 🟢 LOW |
| 🔎 Linter Review | 4 temuan | 🟡 MEDIUM |
| **TOTAL** | **55 temuan** | — |

---

## 1. 🐛 BUG REVIEW

### BUG-001 🔴 CRITICAL — `AsyncStream<Double>` sebagai parameter protocol salah arah

**Lokasi:** Domain Interface, `RemoteFileSystem` protocol

```swift
// ❌ BUGGY — Plan saat ini
protocol RemoteFileSystem: Sendable {
    func download(from: RemotePath, to: URL, progress: AsyncStream<Double>) async throws
    func upload(from: URL, to: RemotePath, progress: AsyncStream<Double>) async throws
}
```

**Masalah:** `AsyncStream` adalah *consumer* (penerima), bukan *producer* yang dipass sebagai parameter. Kalau `AsyncStream` dipass ke dalam fungsi, implementor tidak tahu siapa yang menulis ke stream tersebut. Ini adalah design bug fundamental: stream harus dibuat *di dalam* implementasi, bukan dipass dari luar.

**Fix yang Benar:**

```swift
// ✅ CORRECT — gunakan continuation callback atau return AsyncStream
protocol RemoteFileSystem: Sendable {
    func download(
        from: RemotePath,
        to: URL,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws

    // ATAU: kembalikan AsyncStream dari luar fungsi
    func makeDownloadStream(from: RemotePath, to: URL) -> AsyncThrowingStream<TransferProgress, Error>
}
```

---

### BUG-002 🔴 CRITICAL — `TransferStatus.failed(AppError)` tidak conform `Sendable`

**Lokasi:** Domain Model `TransferStatus`

```swift
// ❌ BUGGY
enum TransferStatus: Sendable {
    case failed(AppError), needsReview  // AppError belum tentu Sendable!
}
```

**Masalah:** `AppError` di plan belum didefinisikan sebagai `Sendable`. Jika `AppError` berisi `Error` (protocol non-Sendable) atau referensi ke objek non-thread-safe, ini akan gagal kompilasi di Swift 6 strict mode atau menciptakan data race tersembunyi.

**Fix:**

```swift
// ✅ CORRECT
enum AppError: Error, Sendable {
    case networkError(String)
    case authenticationFailed
    case hostKeyMismatch(expected: String, got: String)
    case permissionDenied(path: String)
    // Semua associated values HARUS value types atau Sendable
}
```

---

### BUG-003 🟡 MEDIUM — `TransferTask` mutable struct di dalam actor: CoW trap

**Lokasi:** `TransferTask` model + `TransferQueue` actor

```swift
// ❌ POTENTIAL BUG
struct TransferTask: Identifiable, Sendable {
    var totalBytes: Int64         // var di struct = copy-on-write
    var transferredBytes: Int64   // setiap update = new copy
    var status: TransferStatus
}
```

**Masalah:** Ketika `TransferQueue` actor menyimpan array `[TransferTask]` dan mengupdate `transferredBytes` secara intensif (ribuan kali per detik per transfer), Copy-on-Write semantics akan membuat alokasi heap berulang. Untuk state yang sering diupdate, gunakan `class` (reference type) dengan isolation, atau pisahkan `TransferProgress` (sering berubah) dari `TransferTask` metadata (jarang berubah).

**Fix:**

```swift
// ✅ CORRECT — pisahkan state statis dan dinamis
struct TransferTaskMetadata: Identifiable, Sendable { // jarang berubah
    let id: UUID
    let source: TransferEndpoint
    let destination: TransferEndpoint
    let totalBytes: Int64
    let priority: TransferPriority
}

actor TransferProgressTracker { // sering berubah, terisolasi
    var transferredBytes: Int64 = 0
    var status: TransferStatus = .queued
    var currentSpeed: Int64 = 0
}
```

---

### BUG-004 🟡 MEDIUM — Plan menyebut `GlasSecretStore` tanpa verifikasi aktif maintenance

**Lokasi:** TASK-003 SPM Dependencies

**Masalah:** Repository `msitarzewski/GlasSecretStore` adalah library kecil dengan maintainer tunggal dan activity GitHub yang tidak terdokumentasikan dalam plan. Jika library ini abandonware atau tidak update ke Swift 6, seluruh security layer akan terganggu.

**Fix:**

- Jadikan `GlasSecretStore` opsional; buat `KeychainService` sendiri menggunakan `Security.framework` native sebagai fallback utama
- Tambahkan TASK baru: audit `GlasSecretStore` activity + fallback plan ke native Security.framework

---

## 2. 📝 SYNTAX REVIEW

### SYN-001 🟡 MEDIUM — Missing `throws` variant untuk `disconnect()`

**Lokasi:** `RemoteFileSystem` protocol

```swift
// Plan saat ini:
func disconnect() async  // non-throwing

// Masalah: disconnect() bisa gagal (timeout, network error)
// tetapi tidak ada cara melaporkan error ke caller
```

**Fix:**

```swift
func disconnect() async throws  // atau gunakan Result type
// ATAU: buat disconnect() selalu sukses tetapi dengan internal cleanup log
```

---

### SYN-002 🟡 MEDIUM — `progress: AsyncStream<Double>` — tipe `Double` tidak informatif

**Lokasi:** Protocol Interface

**Masalah:** `Double` untuk progress tidak membawa info apa yang sedang terjadi (bytes, kecepatan, ETA). Ini "stringly typed" dari sisi informasi.

**Fix:**

```swift
// ✅ Rich progress info
struct TransferProgress: Sendable {
    let bytesTransferred: Int64
    let totalBytes: Int64
    let bytesPerSecond: Int64
    var percentage: Double { Double(bytesTransferred) / Double(totalBytes) }
    var estimatedTimeRemaining: Duration? {
        guard bytesPerSecond > 0 else { return nil }
        let remaining = totalBytes - bytesTransferred
        return .seconds(remaining / bytesPerSecond)
    }
}
```

---

### SYN-003 🟢 LOW — Docker Compose file menggunakan deprecated `ports` tanpa `volumes`

**Lokasi:** Testing Environment Docker Compose

```yaml
# Plan saat ini — INCOMPLETE
services:
  sftp-server:
    image: atmoz/sftp
    ports: ["2222:22"]
    # ❌ Tidak ada volume untuk test fixtures
    # ❌ Tidak ada SSH key setup
    # ❌ Tidak ada healthcheck
```

**Fix:**

```yaml
# ✅ Complete test fixture
services:
  sftp-server:
    image: atmoz/sftp:latest
    ports: ["2222:22"]
    volumes:
      - ./fixtures/sftp-users.conf:/etc/sftp/users.conf:ro
      - ./fixtures/ssh-host-keys:/etc/ssh/keys:ro
      - ./fixtures/test-files:/home/testuser/upload
    healthcheck:
      test: ["CMD", "ssh", "-o", "StrictHostKeyChecking=no", "localhost", "exit"]
      interval: 10s
      timeout: 5s
      retries: 3
```

---

## 3. ⚡ RUNTIME REVIEW

### RUN-001 🔴 CRITICAL — `CVE-2026-43798`: SwiftNIO SSH Out-of-Bounds Stack Write

**Lokasi:** TASK-003 SPM Dependencies (Citadel → swift-nio-ssh)

**Masalah Nyata (CVE):** Ditemukan vulnerability **CVE-2026-43798** di `swift-nio-ssh` yang memungkinkan **unauthenticated attacker** memicu out-of-bounds stack write via oversized ECDSA signature — **sebelum autentikasi selesai**. Ini adalah pre-auth memory corruption.

> Source: swift.org security advisories — fixed in `swift-nio-ssh 0.14.1`

**Dampak pada Plan:** Plan saat ini **tidak menyebutkan minimum version pinning** untuk `swift-nio-ssh`. Jika Citadel resolves ke versi lama, aplikasi rentan.

**Fix Wajib:**

```swift
// Package.swift — WAJIB tambahkan explicit version constraint
.package(
    url: "https://github.com/orlandos-nl/Citadel",
    from: "0.9.0"  // Pastikan Citadel versi ini depend pada swift-nio-ssh >= 0.14.1
),
// Tambahkan explicit override jika perlu:
.package(
    url: "https://github.com/apple/swift-nio-ssh",
    from: "0.14.1"  // MINIMUM — patch CVE-2026-43798
),
```

**Tambahkan ke TASK-003 dan Security checklist secara eksplisit.**

---

### RUN-002 🔴 CRITICAL — `CVE-2025-15224`: libcurl SSH Agent Auth Bypass

**Lokasi:** TASK-053 libcurl C bridge + FTPService

**Masalah (CVE):** `CVE-2025-15224` — libcurl dengan `libssh` backend (bukan `libssh2`) secara keliru fallback ke SSH agent yang berjalan lokal meski tidak diminta.

**Dampak:** Jika macOS user memiliki SSH agent aktif (`ssh-agent`), koneksi SFTP/SCP via libcurl bisa *autentikasi tanpa password* ke server yang seharusnya memerlukan password — **silent auth bypass**.

**Fix:**

- Pastikan libcurl dikompilasi dengan `libssh2` backend (bukan `libssh`) untuk SFTP
- Tambahkan test: koneksi ke server yang hanya accept password auth — pastikan gagal jika password tidak disupply
- Update plan: tambahkan `CURLOPT_SSH_AUTH_TYPES` = `CURLSSH_AUTH_PASSWORD` untuk enforced password-only connections

---

### RUN-003 🔴 CRITICAL — Actor reentrancy pada `TransferQueue` setelah `await`

**Lokasi:** TASK-074 `TransferQueue` actor design

**Masalah (Teori + Bukti Web):** Plan menyebutkan `TransferQueue` sebagai actor dengan bounded concurrency, tetapi **tidak mendokumentasikan reentrancy guard** setelah `await`.

```swift
// ❌ REENTRANCY TRAP — plan tidak mencegah ini
actor SFTPTransferQueue {
    private var activeTransfers: [UUID: TransferTask] = [:]

    func enqueueAndProcess(task: TransferTask) async throws {
        guard activeTransfers.count < maxConcurrent else { return }
        activeTransfers[task.id] = task

        try await performTransfer(task)  // ← SUSPENSION POINT

        // ⚠️ State mungkin sudah berubah di sini!
        // Task lain bisa cancel, modify, atau remove activeTransfers[task.id]
        activeTransfers.removeValue(forKey: task.id)
        processNext()  // ← Mungkin double-process atau crash
    }
}
```

**Fix yang Harus Didokumentasikan dalam Plan:**

```swift
// ✅ Post-await re-verification pattern — WAJIB masuk TASK-074
actor SFTPTransferQueue {
    func enqueueAndProcess(task: TransferTask) async throws {
        // ... sebelum await ...
        try await performTransfer(task)

        // RE-VERIFY setelah await
        guard activeTransfers[task.id] != nil else {
            // Task sudah di-cancel saat sedang transfer — tidak perlu cleanup
            return
        }
        activeTransfers.removeValue(forKey: task.id)
        await processNextIfAvailable()
    }
}
```

---

### RUN-004 🔴 CRITICAL — SwiftNIO SSH channel stall saat WINDOW_ADJUST ditolak

**Lokasi:** TASK-050 SSHService, TASK-091 PTY channel

**Masalah (GitHub Issue SwiftNIO SSH):** Child channels dalam SwiftNIO SSH dapat **stall permanen** jika `WINDOW_ADJUST` command ditolak saat key exchange berlangsung. Data yang ditulis tepat saat peer-initiated rekey juga bisa **silently dropped**.

**Dampak:** Transfer SFTP besar dapat hang tanpa timeout. Terminal PTY bisa freeze saat server melakukan rekey.

**Fix:**

- Tambahkan TASK baru: implementasi connection-level timeout watchdog (e.g., `Task.sleep` dengan cancel jika tidak ada progress dalam N detik)
- Tambahkan ke testing: simulasi rekey mid-transfer via Docker + netcat
- Tambahkan `SSHService` heartbeat/keepalive untuk detect stalled channel

---

### RUN-005 🟡 MEDIUM — FSEvents watcher tidak di-cancel saat pane ditutup

**Lokasi:** TASK-060 `LocalFileService` (FileManager + FSEvents)

**Masalah:** Plan menyebutkan FSEvents untuk memantau perubahan lokal, tetapi tidak mendokumentasikan teardown. Jika user menutup pane atau disconnects, FSEvents watcher yang orphaned akan:

1. Terus mengkonsumsi event loop resources
2. Mungkin trigger upload ke server yang sudah disconnect
3. Menyebabkan crashes jika referensi ke `RemoteFileService` sudah deallocated

**Fix:** Tambahkan `deinit` guard dan explicit `cancel()` pada setiap FSEvents stream. Gunakan `withTaskCancellationHandler` untuk memastikan cleanup.

---

## 4. 🧠 LOGIC REVIEW

### LOG-001 🔴 CRITICAL — TOFU flow memiliki logic gap: "siapa yang memutuskan trust?"

**Lokasi:** TASK-038 `HostTrustStore`, TASK-039 host key verification UI

**Masalah:** Plan mendefinisikan TOFU (Trust On First Use) tetapi tidak mendefinisikan **state machine yang lengkap**:

```text
State yang didefinisikan plan:
- Unknown → prompt user → save fingerprint ✅
- Known + matches → lanjut ✅  
- Changed → blokir ✅

State yang HILANG dari plan:
- Known + matches tetapi expiry/algorithm deprecated → apa yang terjadi?
- Known tetapi file corrupt/deleted → fallback ke Unknown atau reject?
- Koneksi ulang setelah user dismiss prompt (tanpa accept/reject) → hanging?
- Concurrent connections ke server sama, host key belum di-trust → race condition?
```

**Fix:** Tambahkan explicit HostTrustStateMachine dengan semua state transitions:

```swift
enum HostTrustState {
    case unknown
    case pendingUserDecision(fingerprint: String)  // NEw state!
    case trusted(fingerprint: String, since: Date)
    case rejected
    case mismatch(expected: String, got: String)   // blocks connection
    case corrupted                                  // treats as unknown after user confirmation
}
```

---

### LOG-002 🔴 CRITICAL — Resume logic tidak memvalidasi remote file setelah resume

**Lokasi:** TASK-080 pause/resume, TASK-009 transfer recovery

**Masalah:** Plan menyebutkan "checkpoint-based resume" tetapi tidak mendokumentasikan **remote file revalidation**:

> Skenario: Download 1GB file, aplikasi crash di 500MB. Saat recovery:
>
> 1. Local file ada 500MB partial
> 2. Remote file mungkin sudah berubah (overwrite oleh orang lain)
> 3. Plan hanya cek local offset, tidak cek remote modification time / size / hash

**Ini akan menyebabkan file corrupt yang tidak terdeteksi.**

**Fix yang Harus Masuk TASK-080:**

```swift
// Revalidation sebelum resume:
func validateResumeConditions(task: TransferTask) async throws -> ResumeDecision {
    let remoteMetadata = try await remoteFS.metadata(at: task.source)
    let localPartial = try localFileSize(at: task.partialDestination)

    // Cek apakah remote masih sama
    guard remoteMetadata.modificationTime == task.checkpoint.remoteModTime,
          remoteMetadata.size == task.checkpoint.remoteSize else {
        return .restart  // Remote berubah → mulai dari awal
    }
    guard localPartial == task.checkpoint.bytesTransferred else {
        return .restart  // Local partial corrupt → mulai dari awal
    }
    return .resume(fromOffset: localPartial)
}
```

---

### LOG-003 🔴 CRITICAL — `SyncPlanner` bisa menghasilkan rencana stale

**Lokasi:** TASK-104 `SyncPlanner`, TASK-107 sync executor

**Masalah:** Plan dengan benar mendefinisikan "pure planner tidak bermutasi", tetapi **tidak mendefinisikan berapa lama rencana masih valid** sebelum eksekusi.

> Gap: User klik "Preview" → rencana dibuat pada T=0 → user baca 5 menit → klik "Execute" → target sudah berubah di T=5 menit → destructive operations dieksekusi terhadap state yang berbeda dari preview

**Fix:** Tambahkan `SyncPlan.expiresAt: Date` dan wajib revalidate sebelum eksekusi destruktif:

```swift
struct SyncPlan {
    let createdAt: Date
    let expiresAt: Date  // e.g., createdAt + 60 seconds
    let actions: [SyncAction]

    var isStale: Bool { Date() > expiresAt }
}

// Executor WAJIB:
func execute(_ plan: SyncPlan) async throws {
    guard !plan.isStale else {
        throw SyncError.planExpired  // User harus re-preview
    }
    // Revalidate setiap destructive action sebelum eksekusi
    for action in plan.actions where action.isDestructive {
        try await revalidate(action)
    }
}
```

---

### LOG-004 🟡 MEDIUM — Conflict resolution "Ask" mode: siapa yang blocking transfer queue?

**Lokasi:** TASK-083 conflict resolver

**Masalah:** Ketika conflict policy = "Ask", dan user sedang offline atau tidak merespons dialog — seluruh transfer queue akan **blocked**. Plan tidak mendefinisikan timeout untuk conflict dialogs.

**Fix:** Tambahkan `conflictDialogTimeout: TimeInterval` (default: tidak ada timeout, tapi konfigurable). Jika timeout, default action = Skip (aman) atau Pause task.

---

### LOG-005 🟡 MEDIUM — Recursive directory transfer tidak ada loop detection untuk symlinks

**Lokasi:** TASK-078 batch transfers, TASK-102 directory scanner

**Masalah:** Plan menyebutkan "symlink guard" tetapi tidak mendefinisikan algoritmanya. Direktori remote bisa mengandung symlink circular (A → B → A) yang akan menyebabkan infinite recursion.

**Fix:**

```swift
// Scanner harus track visited inodes
func scanDirectory(path: RemotePath, visitedInodes: inout Set<String>) async throws -> [RemoteFile] {
    let files = try await remoteFS.listDirectory(at: path)
    return try await files.asyncFlatMap { file in
        if file.isSymlink {
            let resolved = try await remoteFS.resolveSymlink(file)
            guard !visitedInodes.contains(resolved.inode) else {
                return []  // Circular symlink — skip
            }
            visitedInodes.insert(resolved.inode)
        }
        // ... continue
    }
}
```

---

### LOG-006 🟡 MEDIUM — `RemoteFileSystem.disconnect()` tidak ada di state machine

**Lokasi:** Protocol + Session lifecycle

**Masalah:** Plan mendefinisikan `connect()` dan `disconnect()` tapi tidak mendefinisikan **apa yang terjadi jika disconnect dipanggil saat transfer aktif**. Apakah transfer di-cancel? Di-pause? Error?

**Fix:** Tambahkan explicit policy dan dokumentasikan dalam `RemoteSession` interface:

```swift
protocol RemoteSession {
    var connectionState: ConnectionState { get async }
    func disconnect(policy: DisconnectPolicy) async throws
}

enum DisconnectPolicy {
    case cancelAllTransfers    // Hentikan semua transfer aktif
    case waitForCompletion     // Tunggu semua selesai lalu disconnect
    case pauseAndDisconnect    // Pause transfer, bisa resume nanti
}
```

---

## 5. 🧠 MEMORY REVIEW

### MEM-001 🔴 CRITICAL — `Task.detached` di `TransferWorker` = potential retain cycle + leak

**Lokasi:** TASK-074 `TransferQueue` actor + TASK-075 Scheduler

**Masalah (Dikonfirmasi oleh web research):** Jika `TransferWorker` menggunakan `Task.detached` untuk menjalankan I/O, dan closure menangkap `self` (actor) secara strong:

```swift
// ❌ PATTERN BERBAHAYA — dari web research Swift 6 pitfalls
actor TransferQueue {
    func processNext() {
        Task.detached {           // ← Drops actor isolation!
            await self.doWork()   // ← Strong capture of self
        }
    }
    // Jika Task tidak pernah cancel, self tidak pernah deinit
}
```

**Fix:**

```swift
// ✅ CORRECT pattern
actor TransferQueue {
    private var workerTask: Task<Void, Never>?

    func startWorker() {
        workerTask = Task { [weak self] in  // weak capture untuk actor
            guard let self else { return }
            await self.processLoop()
        }
    }

    func stopWorker() {
        workerTask?.cancel()
        workerTask = nil
    }

    deinit { workerTask?.cancel() }  // Explicit cleanup
}
```

---

### MEM-002 🔴 CRITICAL — SwiftTerm PTY file descriptor leak saat tab ditutup

**Lokasi:** TASK-090 `TerminalViewRepresentable`, TASK-093 terminal tabs

**Masalah (Dikonfirmasi oleh web research):** PTY di macOS menggunakan kernel-level file descriptor pairs. Jika `LocalProcessTerminalView` atau SSH `TerminalView` di-dismiss tanpa explicit cleanup:

1. PTY master/slave FD tidak di-`close()`
2. Child process (shell) tetap berjalan sebagai orphan
3. Setiap buka-tutup terminal tab = satu leaked FD + satu zombie process

**Fix yang HARUS masuk TASK-093:**

```swift
class TerminalSessionManager {
    private var activeSessions: [UUID: TerminalSession] = [:]

    func closeSession(_ id: UUID) {
        guard let session = activeSessions.removeValue(forKey: id) else { return }
        session.sshChannel?.close()       // Close SSH channel
        session.terminalView?.delegate = nil  // Break delegate retain cycle
        session.ptyTask?.cancel()         // Cancel async PTY reader task
        // Terminal view harus nil-kan semua references
    }

    deinit {
        activeSessions.keys.forEach { closeSession($0) }
    }
}
```

---

### MEM-003 🟡 MEDIUM — Progress reporting via AsyncStream tanpa backpressure

**Lokasi:** TASK-087 transfer statistics, TASK-088 `TransferQueueView`

**Masalah:** Jika transfer berjalan di 1Gbps network dan progress dilaporkan setiap byte chunk, `AsyncStream<TransferProgress>` bisa menghasilkan **jutaan events per detik**. Buffer AsyncStream akan membesar tak terbatas jika consumer (UI) lebih lambat.

**Fix:**

```swift
// ✅ Throttled progress dengan minimum interval
actor ProgressThrottler {
    private var lastEmitTime: ContinuousClock.Instant = .now
    private let minimumInterval: Duration = .milliseconds(100)  // Max 10 FPS UI update

    func emit(_ progress: TransferProgress, to continuation: AsyncStream<TransferProgress>.Continuation) {
        let now = ContinuousClock.now
        guard now - lastEmitTime >= minimumInterval else { return }
        lastEmitTime = now
        continuation.yield(progress)
    }
}
```

---

### MEM-004 🟡 MEDIUM — `NSTableView` via `NSViewRepresentable` tanpa explicit reuse dequeue

**Lokasi:** TASK-062 `FilePaneView` NSTableView

**Masalah:** Plan menyebutkan `NSTableView` untuk performa, tapi jika implementasi tidak menggunakan cell reuse queue (`tableView.makeView(withIdentifier:owner:)`), dengan 100.000 file akan ada 100.000 `NSTableCellView` instances di memory sekaligus.

**Fix:** Tambahkan explicit note di TASK-062: wajib gunakan cell dequeue pattern dan lazy loading untuk large directories:

```swift
// WAJIB dalam implementasi NSTableView
func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("FileCell"), owner: nil)
        as? FileTableCellView
        ?? FileTableCellView()  // Buat baru hanya jika tidak ada reusable cell
    cell.configure(with: items[row])
    return cell
}
```

---

## 6. 💀 DEAD CODE REVIEW

### DEAD-001 🟡 MEDIUM — `TASK-061` = duplikasi partial dari `TASK-060`

**Lokasi:** EPIC-06, TASK-060 dan TASK-061

```text
TASK-060: Implement LocalFileService (FileManager + FSEvents watcher)
TASK-061: Implement LocalFileService stub (fake remote untuk dev UI awal)
```

**Masalah:** Setelah development selesai, stub dari TASK-061 tidak akan dipakai lagi tetapi tidak ada rencana untuk menghapusnya. Code stub yang tertinggal di production codebase adalah dead code.

**Fix:**

- Rename TASK-061 menjadi "LocalFileServiceStub — HANYA untuk testing, hapus setelah TASK-049 selesai"
- Gunakan `#if DEBUG` guard di implementasi stub
- Tambahkan ke acceptance criteria TASK-049: hapus stub setelah integrasi nyata selesai

---

### DEAD-002 🟡 MEDIUM — `SFTPService+SCP.swift` adalah fallback yang jarang dipakai

**Lokasi:** TASK-051

**Masalah:** Plan dengan benar mengakui SCP via `execCommand` adalah "best-effort fallback yang jarang dipakai". Dalam praktiknya, hampir semua server modern support SFTP. SCP fallback ini berpotensi menjadi dead code yang tidak pernah ditest dengan benar.

**Fix:** Perjelas dalam plan:

- Tambahkan capability check: hanya load SCP adapter jika SFTP subsystem tidak tersedia
- Tambahkan dedicated test: server yang disable SFTP subsystem tapi enable SCP
- Atau: defer SCP ke v1.1 (hindari dead/untested code di MVP)

---

## 7. 🔁 DUPLICATE CODE REVIEW

### DUP-001 🟡 MEDIUM — `RemoteProtocol`, `RemoteSession`, dan `RemoteFileSystem` overlap

**Lokasi:** TASK-046, TASK-047, TASK-048

Plan mendefinisikan tiga interface terpisah untuk hal yang tumpang tindih:

- `RemoteProtocol` — capability matrix
- `RemoteSession` — lifecycle
- `RemoteFileSystem` — file operations

**Masalah:** Tidak ada boundary yang jelas. Misalnya, `RemoteSession.connect()` dan `RemoteFileSystem.connect()` duplikasi? Siapa yang owns `disconnect()`?

**Fix:** Konsolidasi dengan composition:

```swift
// ✅ Clear separation of concerns
protocol RemoteConnection {          // Lifecycle only
    func connect() async throws
    func disconnect(policy: DisconnectPolicy) async throws
    var capabilities: Set<RemoteCapability> { get }
}

protocol RemoteFileSystem {         // File operations only (stateless)
    func listDirectory(at path: RemotePath) async throws -> [RemoteFile]
    // ... (tidak ada connect/disconnect di sini)
}

// Composite — dimiliki oleh service layer
struct RemoteService {
    let connection: RemoteConnection
    let fileSystem: RemoteFileSystem
}
```

---

### DUP-002 🟡 MEDIUM — `KeychainService` dan `GlasSecretStore` adalah duplikasi

**Lokasi:** TASK-035 `KeychainService` + TASK-003 `GlasSecretStore`

**Masalah:** Plan mendefinisikan `KeychainService` (custom wrapper) DAN menggunakan `GlasSecretStore` (third-party). Dua lapisan Keychain abstraction untuk hal yang sama.

**Fix:** Pilih satu:

- **Option A:** Hanya gunakan `GlasSecretStore` (setelah audit aktif maintenance)
- **Option B:** Hanya gunakan custom `KeychainService` via native `Security.framework`
- Jangan gunakan keduanya — ini duplikasi dan creates confusion tentang "mana yang dipakai?"

---

### DUP-003 🟡 MEDIUM — Drag-and-drop didefinisikan di dua lokasi

**Lokasi:** TASK-067 (File Manager) dan WG-6 description (Transfer Queue)

Kedua tempat mendefinisikan drag-and-drop behavior. Potensi inkonsistensi implementasi.

**Fix:** Centralize drag-and-drop dalam satu EPIC, referensi dari EPIC lain.

---

## 8. 🔄 CIRCULAR DEPENDENCY REVIEW

### CIRC-001 🔴 CRITICAL — `TransferEngine` → `RemoteFileSystem` → `TransferEngine` potential cycle

**Lokasi:** Arsitektur dependency graph

**Masalah:** Jika `SFTPService` (implements `RemoteFileSystem`) perlu report progress ke `TransferQueue` (di `TransferEngine`), dan `TransferQueue` calls `SFTPService.upload()`, ini **bisa circular**:

```text
TransferQueue.startTransfer()
    → SFTPService.upload()          ← Protocol call OK
        → SFTPService reports progress
            → needs to call back to TransferQueue
                → CIRCULAR if direct reference
```

**Fix:** Gunakan delegation pattern atau closure callback:

```swift
// ✅ Gunakan closure — tidak ada direct reference cycle
actor SFTPService {
    func upload(
        from: URL,
        to: RemotePath,
        onProgress: @escaping @Sendable (TransferProgress) -> Void  // closure, bukan direct ref
    ) async throws { ... }
}
```

---

### CIRC-002 🟡 MEDIUM — `Features/` layer bisa import `Packages/` yang import `Features/`

**Lokasi:** Repository structure, Packages/ vs Features/

**Masalah:** Plan tidak mendefinisikan secara eksplisit bahwa `Packages/` modules tidak boleh import apapun dari `Features/`. Jika developer tidak hati-hati (misalnya DesignSystem perlu FeatureFlag dari Settings), circular import bisa muncul.

**Fix:** Tambahkan ke TASK-008 (Architecture docs):

```swift
// Package.swift — DesignSystem tidak boleh import Features
// Enforced via SPM dependency graph
// Tambahkan CI check: `swift package show-dependencies --format json | grep circular`
```

---

## 9. ⚡ PERFORMANCE BOTTLENECK REVIEW

### PERF-001 🔴 CRITICAL — Directory listing 100.000+ files pada main thread

**Lokasi:** TASK-062 FilePaneView, TASK-065 file sorting

**Masalah:** Jika `listDirectory()` mengembalikan `[RemoteFile]` sebagai single array dan langsung di-assign ke `@State`, SwiftUI akan mencoba render 100.000 rows sekaligus → UI freeze.

**Fix yang Harus Didokumentasikan:**

```swift
// ✅ Paginated / lazy loading approach
actor RemoteBrowserViewModel {
    private var pageSize = 1000
    private var currentPage = 0
    private(set) var visibleFiles: [RemoteFile] = []
    private var allFiles: [RemoteFile] = []

    func loadPage() async {
        let start = currentPage * pageSize
        let end = min(start + pageSize, allFiles.count)
        let page = Array(allFiles[start..<end])
        await MainActor.run { visibleFiles.append(contentsOf: page) }
        currentPage += 1
    }
}
```

---

### PERF-002 🔴 CRITICAL — SHA-256 verification blocking untuk 10GB file

**Lokasi:** TASK-076/077 upload/download verification, TASK-084 atomic upload

**Masalah:** Plan menyebutkan "SHA-256 verification" tapi untuk file 10GB, SHA-256 pada macOS M1 ≈ 3.5 GB/s. Verifikasi 10GB = ~3 detik blocking. Jika ini di main actor → UI freeze 3 detik.

**Fix:**

```swift
// ✅ Background verification dengan structured concurrency
func verifyAndFinalize(tempURL: URL, expectedHash: String?) async throws {
    if let expectedHash {
        // Jalankan di background, bukan MainActor
        let actualHash = try await Task.detached(priority: .utility) {
            try SHA256.hash(file: tempURL)  // ← background thread
        }.value

        guard actualHash == expectedHash else {
            try FileManager.default.removeItem(at: tempURL)
            throw TransferError.checksumMismatch
        }
    }
    // Atomic rename — cepat, boleh di normal task
    try FileManager.default.moveItem(at: tempURL, to: finalDestination)
}
```

---

### PERF-003 🟡 MEDIUM — `NSTableView` sorting via `sorted()` = O(n log n) setiap tap column

**Lokasi:** TASK-065 file sorting

**Masalah:** Jika user sering tap sort column dengan 50.000 files, setiap tap = `sorted()` O(n log n) di main thread.

**Fix:** Cache sorted results dan sort di background:

```swift
// Sort di background thread
Task.detached(priority: .userInitiated) {
    let sorted = files.sorted(by: sortDescriptor)
    await MainActor.run { self.displayedFiles = sorted }
}
```

---

### PERF-004 🟡 MEDIUM — `AsyncStream<TransferProgress>` tanpa buffer limit = unbounded memory

**Lokasi:** TASK-087 transfer statistics

**Masalah:** `AsyncStream` default `.bufferingNewest(Int.max)`. Jika consumer (UI) pause atau slow, buffer akan tumbuh tak terbatas.

**Fix:**

```swift
// ✅ Bounded buffer dengan .bufferingNewest
let (stream, continuation) = AsyncStream<TransferProgress>.makeStream(
    bufferingPolicy: .bufferingNewest(10)  // Hanya keep 10 latest updates
)
```

---

### PERF-005 🟡 MEDIUM — `SwiftData` untuk session profiles — overkill untuk data kecil

**Lokasi:** TASK-023 `ConnectionProfile` model (SwiftData)

**Masalah:** SwiftData menggunakan CoreData stack yang heavy. Untuk data session profiles (mungkin <1000 records total), JSON file + `Codable` lebih ringan dan tidak memerlukan migration schema yang kompleks.

**Fix/Consideration:**

- Pertimbangkan: JSON + `Codable` untuk connection profiles (simple, portable, no migration headache)
- Keep SwiftData untuk `TransferJournal` (lebih complex, perlu query, perlu migration)
- Atau: document trade-off dan buat ADR tentang keputusan ini

---

## 10. 🛡️ SECURITY CVE/CWE VULNERABILITY REVIEW

### SEC-001 🔴 CRITICAL — CWE-295: Improper Certificate Validation — tidak ada explicit SecTrust policy

**Lokasi:** TASK-040 TLS certificate validation

**Masalah:** Plan hanya menyebutkan "chain + hostname + expiry validation" tapi tidak mendefinisikan **bagaimana** implementasinya. Menggunakan `URLSession` default validation (tidak berlaku untuk libcurl C bridge) atau implementasi `SecTrust` custom yang bisa salah.

**Fix yang Harus Explicit di TASK-040:**

```swift
// ✅ WAJIB: Explicit SecTrust policy chain
func validateServerCertificate(_ trust: SecTrust, host: String) throws {
    var policies: [SecPolicy] = [
        SecPolicyCreateSSL(true, host as CFString),  // hostname check
        SecPolicyCreateRevocation(kSecRevocationOCSPMethod)  // OCSP revocation
    ]
    SecTrustSetPolicies(trust, policies as CFArray)

    var error: CFError?
    guard SecTrustEvaluateWithError(trust, &error) else {
        throw TLSError.certificateValidationFailed(error.map { $0.localizedDescription } ?? "Unknown")
    }
    // JANGAN gunakan: SecTrustGetTrustResult dengan kSecTrustResultProceed saja
    // itu bypass beberapa checks
}
```

---

### SEC-002 🔴 CRITICAL — CWE-312: Keychain accessibility terlalu permissive

**Lokasi:** TASK-035 `KeychainService`

**Masalah:** Plan tidak menyebutkan `kSecAttrAccessible` attribute. Default Keychain accessibility di banyak tutorial adalah `kSecAttrAccessibleWhenUnlocked` yang **bisa sync ke iCloud** (CWE-522).

**Fix yang Harus Masuk TASK-035:**

```swift
// ✅ WAJIB: ThisDeviceOnly untuk prevent iCloud sync
let attributes: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.alsyundawy.SparkleSFTP",
    kSecAttrAccount as String: accountKey,
    kSecValueData as String: secretData,
    // CRITICAL: Prevent credential sync to iCloud/other devices
    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    // CRITICAL: Restrict to this application only
    kSecAttrAccessControl as String: try! SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        .privateKeyUsage,  // atau .userPresence untuk Touch ID
        nil
    )
]
```

---

### SEC-003 🔴 CRITICAL — CWE-22: Path Traversal dalam SFTP listing

**Lokasi:** TASK-049 SFTPService listDirectory, TASK-078 batch transfers

**Masalah:** Server jahat bisa mengirimkan path response yang mengandung `../` traversal. Jika `RemoteFile.path` tidak divalidasi sebelum digunakan untuk operasi download, file bisa ditulis ke luar intended directory.

**Fix:**

```swift
// ✅ Path canonicalization sebelum setiap operasi
func canonicalize(_ remotePath: RemotePath, relativeTo baseDir: RemotePath) throws -> RemotePath {
    let resolved = URL(fileURLWithPath: baseDir.rawValue)
        .appendingPathComponent(remotePath.rawValue)
        .standardized
        .path

    guard resolved.hasPrefix(baseDir.rawValue) else {
        throw SecurityError.pathTraversal(attempted: remotePath.rawValue)
    }
    return RemotePath(rawValue: resolved)
}
```

---

### SEC-004 🔴 CRITICAL — CWE-59: Symlink attack saat recursive download

**Lokasi:** TASK-078 batch transfers

**Masalah:** Saat recursive download dari server jahat, server bisa mengirimkan symlink yang menunjuk ke file sistem lokal sensitif (e.g., `~/.ssh/id_rsa`). Jika client mengikuti symlink tanpa validasi, file sensitif lokal bisa tertimpa.

**Fix:**

```swift
// ✅ Symlink validation sebelum download ke local
func safeDownloadDestination(remoteFile: RemoteFile, baseLocalDir: URL) throws -> URL {
    let destination = baseLocalDir.appendingPathComponent(remoteFile.name)
    let canonicalized = destination.standardizedFileURL

    // Pastikan destinasi ada di dalam baseLocalDir
    guard canonicalized.path.hasPrefix(baseLocalDir.path) else {
        throw SecurityError.symlinkTraversal(destination: canonicalized.path)
    }

    // Jika remote file adalah symlink, resolve target dan validasi
    if remoteFile.isSymlink, let target = remoteFile.symlinkTarget {
        guard !target.contains("..") else {
            throw SecurityError.maliciousSymlink(target: target)
        }
    }
    return canonicalized
}
```

---

### SEC-005 🔴 CRITICAL — CWE-532: Credential leakage dalam OSLog

**Lokasi:** TASK-041 secure logging

**Masalah:** Plan menyebutkan "credential redaction via OSLog privacy" tetapi tidak mendefinisikan **cara implementasinya**. Jika developer hanya menggunakan `Logger.debug("\(password)")`, password akan muncul di Console.app.

**Fix yang Harus Explicit di TASK-041:**

```swift
// ✅ OSLog privacy labels — WAJIB untuk semua credential
import OSLog

extension Logger {
    static let security = Logger(subsystem: "com.alsyundawy.SparkleSFTP", category: "Security")
}

// Penggunaan WAJIB:
Logger.security.info("Connecting to \(host, privacy: .public) as \(username, privacy: .private)")
// JANGAN:
Logger.security.debug("Password: \(password)")  // ← NEVER

// Tambahkan swiftlint rule untuk prevent literal password logging:
// swiftlint.yml: forbidden_patterns: ["Logger.*password", "print.*password"]
```

---

### SEC-006 🟡 MEDIUM — Sparkle update tanpa DSA/EdDSA signature verification

**Lokasi:** TASK-123 Sparkle framework integration

**Masalah:** Sparkle dapat dikonfigurasi tanpa signature verification. Jika update feed HTTP (bukan HTTPS) atau signature disabled, ini adalah supply chain attack vector.

**Fix:**

- Wajibkan HTTPS untuk Sparkle update feed
- Aktifkan `SUPublicDSAKeyFile` atau lebih baik `SUPublicEDKeyFile` (Ed25519)
- Tambahkan ke acceptance criteria: update yang tidak ter-sign harus ditolak
- Test: simulasi tampered update package → harus ditolak

---

### SEC-007 🟡 MEDIUM — SCP filename injection via `execCommand`

**Lokasi:** TASK-051 SCP fallback

**Masalah:** SCP via SSH `execCommand` perlu meng-escape nama file. File dengan nama seperti `; rm -rf /` atau nama dengan newlines bisa menyebabkan command injection jika tidak di-escape.

**Fix:**

```swift
// ✅ WAJIB: Quote dan escape semua path arguments
func buildSCPCommand(source: RemotePath, destination: RemotePath) -> String {
    let escapedSource = source.rawValue
        .replacingOccurrences(of: "'", with: "'\\''")  // Shell single-quote escape
    let escapedDest = destination.rawValue
        .replacingOccurrences(of: "'", with: "'\\''")
    return "scp '\(escapedSource)' '\(escapedDest)'"
}
// Atau lebih baik: gunakan array argument (tidak melalui shell) jika API mendukung
```

---

## 11. 🔧 MAINTAINABILITY REVIEW

### MAINT-001 🟡 MEDIUM — Tidak ada error taxonomy yang terdefinisi

**Lokasi:** TASK-010, `Errors/` package

**Masalah:** Plan menyebutkan "AppError enum dengan pesan user-friendly" tapi tidak mendefinisikan **kategori** error. Tanpa taxonomy, developer akan membuat error types yang inkonsisten.

**Fix — Tambahkan ke TASK-010:**

```swift
enum AppError: Error, Sendable, LocalizedError {
    // Network
    case connectionTimeout(host: String, duration: Duration)
    case hostUnreachable(host: String)
    case hostKeyMismatch(expected: String, got: String)

    // Authentication  
    case authenticationFailed(method: AuthMethod)
    case credentialNotFound(service: String)

    // Transfer
    case transferFailed(reason: TransferFailureReason)
    case diskFull(requiredBytes: Int64, availableBytes: Int64)
    case permissionDenied(path: String)

    // Data Integrity
    case checksumMismatch(expected: String, actual: String)
    case partialTransferDetected(bytesExpected: Int64, bytesTransferred: Int64)

    var errorDescription: String? { /* localized descriptions */ }
    var recoverySuggestion: String? { /* user-friendly recovery hints */ }
}
```

---

### MAINT-002 🟡 MEDIUM — Tidak ada ADR untuk keputusan SwiftData vs JSON

**Lokasi:** TASK-023, Persistence layer

**Masalah:** Plan memilih SwiftData tanpa ADR. Jika di kemudian hari perlu migrasi (e.g., ke GRDB atau JSON), tidak ada dokumentasi mengapa SwiftData dipilih.

**Fix:** Buat ADR-003: "Database Metadata Storage Decision" dengan trade-off analysis.

---

### MAINT-003 🟡 MEDIUM — Tidak ada feature flag system

**Lokasi:** Plan secara keseluruhan

**Masalah:** Plan tidak mendefinisikan feature flag system. Tanpa ini, fitur yang setengah jadi bisa masuk ke release build.

**Fix:**

```swift
// Tambahkan FeatureFlags module di TASK baru
struct FeatureFlags {
    static let isSyncEnabled: Bool = ProcessInfo.processInfo.environment["SPARKLESFTP_SYNC_ENABLED"] == "1"
    static let isS3Enabled: Bool = ProcessInfo.processInfo.environment["SPARKLESFTP_S3_ENABLED"] == "1"
    // Untuk production: gunakan remote config atau hardcoded dengan #if DEBUG
}
```

---

### MAINT-004 🟡 MEDIUM — `SFTPService+SCP.swift` extension file — maintainability concern

**Lokasi:** TASK-051

**Masalah:** Menggunakan Swift extension files (`+SCP.swift`) untuk logika yang signifikan makes it harder to understand boundaries. SCP adapter harusnya class/struct terpisah, bukan extension.

**Fix:**

```swift
// ❌ Avoid:
// SFTPService+SCP.swift (extension SFTPService)

// ✅ Better:
// SCPCompatibilityAdapter.swift (separate struct implementing RemoteFileSystem)
struct SCPCompatibilityAdapter: RemoteFileSystem {
    private let sshService: SSHService
    // ...
}
```

---

## 12. 📈 SCALABILITY REVIEW

### SCALE-001 🟡 MEDIUM — Per-host connection limit tidak terdefinisi

**Lokasi:** TASK-079 concurrent transfers

**Masalah:** Plan menyebutkan "max 3 simultaneous transfers" secara global tapi tidak mendefinisikan per-host limit. Beberapa server (terutama shared hosting) membatasi 2 koneksi per user. Tanpa per-host limit, 3 concurrent transfers ke server sama = kemungkinan di-kick.

**Fix:**

```swift
actor TransferScheduler {
    private var perHostConcurrency: [String: Int] = [:]
    private let maxGlobalConcurrent: Int = 3
    private let maxPerHostConcurrent: Int = 2  // Configurable

    func canStart(transfer: TransferTask) -> Bool {
        let host = transfer.destination.host
        let currentHostCount = perHostConcurrency[host, default: 0]
        let totalActive = perHostConcurrency.values.reduce(0, +)
        return currentHostCount < maxPerHostConcurrent && totalActive < maxGlobalConcurrent
    }
}
```

---

### SCALE-002 🟡 MEDIUM — `TransferJournal` tidak ada size limit

**Lokasi:** TASK-085 `TransferJournal`

**Masalah:** Jika user menggunakan aplikasi selama months/years, transfer journal akan terus tumbuh. Plan tidak mendefinisikan retention policy atau max size.

**Fix:** Tambahkan ke TASK-085:

- Retention policy: keep completed transfers untuk 30 hari
- Max journal size: 10.000 entries (oldest deleted first)
- Explicit migration plan untuk schema changes

---

### SCALE-003 🟡 MEDIUM — Directory comparison tidak skala untuk jutaan file

**Lokasi:** TASK-103 file comparison engine

**Masalah:** Untuk sync large repos (jutaan file), SHA-256 comparison dari semua file akan sangat lambat. Plan tidak mendefinisikan comparison strategy untuk scale.

**Fix:** Tambahkan tiered comparison:

1. First: compare by size (fastest, O(n) memory)
2. Second: compare by mtime (fast, most accurate for typical use)
3. Third: compare by SHA-256 (slow, hanya untuk explicit "verify" mode)
4. Never: compare all files by SHA-256 by default

---

## 13. 👁️ READABILITY REVIEW

### READ-001 🟢 LOW — Campuran Bahasa Indonesia dan Inggris dalam interface names

**Lokasi:** Plan secara keseluruhan

**Masalah:** Plan menggunakan Bahasa Indonesia untuk deskripsi (baik) tapi code snippets dalam Inggris. Namun beberapa variable names dalam contoh kode tidak konsisten.

**Fix:** Establish coding standard: **semua code, variable names, comments dalam Bahasa Inggris**. Dokumentasi plan boleh Bahasa Indonesia. Tambahkan ke TASK-004 (SwiftLint).

---

### READ-002 🟢 LOW — `RemotePath` tidak didefinisikan tapi digunakan di mana-mana

**Lokasi:** Domain Interface

**Masalah:** Plan menggunakan `RemotePath` tapi tidak mendefinisikan strukturnya. Apakah `String`? `URL`? Custom type?

**Fix yang Harus Masuk TASK-010:**

```swift
// ✅ Strongly-typed, documented
struct RemotePath: Sendable, Hashable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        // Normalize: ensure leading slash
        self.rawValue = rawValue.hasPrefix("/") ? rawValue : "/" + rawValue
    }

    init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    var isAbsolute: Bool { rawValue.hasPrefix("/") }
    var parent: RemotePath? { /* ... */ }
    var filename: String { URL(fileURLWithPath: rawValue).lastPathComponent }
}
```

---

### READ-003 🟢 LOW — Workground numbering tidak konsisten dengan Phase numbering

**Lokasi:** Workground table vs Phase Roadmap

**Masalah:** WG-7 (Security) seharusnya diimplementasikan sebelum WG-2 (SFTP Engine) tapi dalam timeline tabel, Phase 03 (Security) datang setelah Phase 02 (Foundation). Numbering membingungkan.

**Fix:** Tambahkan kolom "Implemented in Phase" pada Workground table untuk mapping yang jelas.

---

## 14. 🔎 LINTER REVIEW

### LINT-001 🟡 MEDIUM — SwiftLint rules tidak terdefinisikan dalam plan

**Lokasi:** TASK-004

**Masalah:** Plan hanya menyebutkan "Configure SwiftLint" tanpa mendefinisikan rules set. Tanpa explicit rules, developer akan mendapat default rules yang mungkin tidak sesuai dengan proyek ini.

**Fix — Tambahkan `.swiftlint.yml` starter ke TASK-004:**

```yaml
# .swiftlint.yml — SparkleSFTP
opt_in_rules:
  - force_unwrapping       # No ! in production code
  - implicitly_unwrapped_optional
  - prefer_self_type_over_type_of_self
  - sorted_imports
  - literal_expression_end_indentation

disabled_rules:
  - todo  # Allow TODO in development phase

excluded:
  - Packages/*/Tests/

custom_rules:
  no_password_in_logs:
    name: "No Password in Logs"
    regex: 'Logger\.[a-z]+\(.*password.*\)'
    message: "Never log passwords or secrets"
    severity: error

  no_accept_any_host_key:
    name: "No Accept Any Host Key"
    regex: 'acceptAnything|acceptAnyHostKey'
    message: "Never disable host key verification"
    severity: error
```

---

### LINT-002 🟡 MEDIUM — `@unchecked Sendable` tidak ada guardrail

**Lokasi:** Plan concurrency design

**Masalah:** Plan menyebutkan `@unchecked Sendable` memerlukan "review khusus" tapi tidak ada mekanisme enforcement. Developer bisa diam-diam menambahkan tanpa review.

**Fix:**

```yaml
# .swiftlint.yml
custom_rules:
  no_unchecked_sendable_without_comment:
    name: "Unchecked Sendable Must Have Justification Comment"
    regex: '@unchecked Sendable(?!\s*//)'
    message: "Add // JUSTIFICATION: comment before @unchecked Sendable"
    severity: warning
```

---

### LINT-003 🟡 MEDIUM — Tidak ada SwiftFormat configuration

**Lokasi:** TASK-004

**Masalah:** Plan menyebutkan SwiftFormat tapi tidak mendefinisikan rules. Inconsistent formatting antara developer (atau AI-generated code).

**Fix — Tambahkan `.swiftformat` ke TASK-004:**

```text
# .swiftformat
--swiftversion 6.0
--indent 4
--maxwidth 120
--wraparguments before-first
--wrapparameters before-first
--disable redundantBackticks,redundantReturn
--enable blankLineAfterImports,sortedImports
```

---

### LINT-004 🟡 MEDIUM — GitHub Actions CI tidak ada linter step

**Lokasi:** TASK-006 CI/CD

**Masalah:** Plan hanya menyebutkan "build + unit test" di CI. Tanpa linter step di CI, linter errors bisa lolos ke main branch.

**Fix — Tambahkan ke TASK-006:**

```yaml
# .github/workflows/ci.yml
jobs:
  lint:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: SwiftLint
        run: swiftlint --strict
      - name: SwiftFormat Check
        run: swiftformat --lint .
      - name: ShellCheck (Tools/ scripts)
        run: shellcheck Tools/**/*.sh
```

---

## 🚨 Priority Remediation Order

### Harus diperbaiki SEBELUM eksekusi Phase 01

1. **SEC-001 to SEC-007** — Security vulnerabilities (CRITICAL)
2. **RUN-001** — CVE-2026-43798 version pinning (CRITICAL)
3. **RUN-002** — CVE-2025-15224 libcurl backend (CRITICAL)
4. **BUG-001** — AsyncStream protocol design (CRITICAL)
5. **BUG-002** — AppError Sendable conformance (CRITICAL)
6. **LOG-001** — TOFU state machine completeness (CRITICAL)
7. **LOG-002** — Resume revalidation logic (CRITICAL)

### Harus diperbaiki sebelum Phase 03 (Security)

1. **MEM-001** — Task.detached retain cycle in TransferQueue
2. **MEM-002** — SwiftTerm PTY file descriptor leak
3. **CIRC-001** — TransferEngine ↔ RemoteFileSystem circular reference
4. **LOG-003** — SyncPlan staleness validation

### Harus diperbaiki sebelum Phase 06 (Transfer Engine)

1. **RUN-003** — Actor reentrancy in TransferQueue
2. **RUN-004** — SwiftNIO channel stall handling
3. **PERF-001** — Directory listing main thread blocking
4. **PERF-002** — SHA-256 blocking verification
5. **MEM-003** — AsyncStream backpressure
6. **SCALE-001** — Per-host connection limits

---

## ✅ Updated Acceptance Criteria Additions

**Status MVP Gate (berdasarkan verifikasi implementasi & automated tests — 64 tests in 17 suites, 129 Swift files):**

- [x] `swift-nio-ssh` version ≥ 0.14.1 (`0.15.1`, patch CVE-2026-43798 — lihat [ADR-004](ADR/0004-direct-swift-nio-ssh-and-sftp-codec.md))
- [x] `Clibcurl` locked to `ftp,ftps` (`CURLOPT_PROTOCOLS_STR`, memblokir permukaan `libssh` — mitigasi CVE-2025-15224)
- [x] `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` pada semua Keychain entries (`SecurityTests` + `no_icloud_keychain_sync` — lihat [ADR-005](ADR/0005-macos13-sqlite3-journal-and-observable-object.md))
- [x] Path traversal test: download dengan `../` path → rejected (`SecurityTests`)
- [x] Symlink attack test: recursive download/scan & pre-existing local symlink destination → rejected (`SecurityTests`, `SynchronizationTests`)
- [x] Actor reentrancy & checkpoint pause/resume test: cancel mid-transfer, upload conflict policy, remote mutation revalidation → deterministik (`TransferEngineTests`, `TransferEngineResumeTests`)
- [x] Proxy tunnel strict HTTP `200` status token enforcement & bounded stall timeouts (`NetworkingTests`, `LoopbackAdvancedIntegrationTests`)
- [x] PTY leak test: open/close 100 terminal tabs → memory tidak leak (`IntegrationTests`)
- [x] SHA-256 verification: tidak blocking main thread untuk file > 100MB (`TransferEngineTests`)
- [x] Sparkle: unsigned/non-HTTPS update check dan placeholder `SUPublicEDKey` ditolak (`UpdateConfigurationValidator`, `SecurityTests`, `SparkleUpdaterService`); Ed25519 appcast signing dilakukan pada host rilis
- [x] OSLog: tidak ada secret dalam log (`DiagnosticsLogger` + SwiftLint `no_password_in_logs`)
- [x] CI/CD & Linters: `.github/workflows/ci.yml` + `release.yml`, `swiftlint --strict` (0/129 files), `swiftformat --lint .` (0/129 files), `markdownlint-cli2`, `yamllint`, `actionlint`, `shellcheck`, `clang-format --dry-run --Werror`, `cppcheck`

---

*Review completed: 2026-11-11 | SparkleSFTP Plan Code Review v1.1 (originally drafted for MacSFTP, standardized to SparkleSFTP)*
*55 findings across 14 pillars | 7 CRITICAL CVE/CWE security issues identified*
*Web research sources: CVE database (NIST), swift.org security advisories, SwiftNIO GitHub issues, Apple Developer Documentation, OWASP CWE database*
