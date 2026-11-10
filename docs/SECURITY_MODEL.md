# SparkleSFTP Security Model

> [!IMPORTANT]
> This document defines the threat model, trust boundaries, cryptographic invariants, CVE/CWE controls, and operational security verification gates for **SparkleSFTP**.

## 1. Security Objectives & Assets

SparkleSFTP handles high-privilege remote infrastructure access. Primary protected assets:

1. **Authentication Credentials**: SSH passwords, FTP/FTPS passwords, private key passphrases, and private key material.
2. **Host Identity State**: Known SSH host public keys and SHA-256 fingerprints (`HostTrustStore`).
3. **Transport Channels**: SSH encrypted streams (`apple/swift-nio-ssh`) and FTPS TLS sessions (`SecTrust` + `libcurl`).
4. **Local & Remote Filesystems**: User home directories, `.ssh` keys, and server paths guarded against traversal and symlink escapes.
5. **Update Pipeline**: Signed binary releases delivered over HTTPS + Sparkle Ed25519 verification.

---

## 2. Trust Boundaries & STRIDE Analysis

| Boundary | Untrusted Input | STRIDE Threat | Enforced Control | Code Owner |
| :--- | :--- | :--- | :--- | :--- |
| **TB-1: SSH Handshake** | Remote server host key & KEX packets | **S**poofing (MITM), **T**ampering, Memory Corruption (CVE-2026-43798) | Pin `apple/swift-nio-ssh >= 0.14.1` (`0.15.1`); 6-state TOFU `HostTrustStore`; hard block on `.mismatch` | `Packages/Security/HostTrustStore.swift`, `Packages/Networking/SSHClientService.swift` |
| **TB-2: FTPS TLS** | Server X.509 certificate chain & FTP `AUTH TLS` reply | **S**poofing, **I**nformation Disclosure, Downgrade | `SecTrustEvaluateWithError` (`SecPolicyCreateSSL` + `kSecRevocationOCSPMethod`); TLS 1.2+ min; zero downgrade to plain FTP | `Packages/Security/TLSCertificateValidator.swift`, `Packages/Networking/FTPService.swift` |
| **TB-3: Credential Storage** | Secrets entered in UI or imported | **I**nformation Disclosure (iCloud sync, plaintext DB, logs) | `KeychainService` with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + optional Touch ID (`LAContext`); zero secrets in JSON/SQLite/`OSLog` | `Packages/Security/KeychainService.swift`, `Packages/Security/DiagnosticsLogger.swift` |
| **TB-4: Remote File Listings & Symlinks** | Server filenames, `../`, symlink targets | **T**ampering / Arbitrary local overwrite (CWE-22, CWE-59) | `PathValidator` canonicalization + base-dir containment + symlink escape check + `visitedInodes` loop detection | `Packages/Security/PathValidator.swift`, `Packages/Synchronization/DirectoryScanner.swift` |
| **TB-5: SCP Shell Fallback** | Filenames containing `;`, `$()`, quotes, newlines | **E**levation / Remote Command Injection (CWE-78) | Reject NUL bytes/control characters where unsafe; strict POSIX single-quote escaping (`'\\''`) | `Packages/Networking/SCPCompatibilityAdapter.swift` |
| **TB-6: Application Updates** | Remote Appcast XML & DMG/ZIP payload | **T**ampering (Supply Chain) | HTTPS Appcast URL (`SUFeedURL`) + mandatory Sparkle Ed25519 signature (`SUPublicEDKey`) | `App/SparkleUpdaterService.swift`, `App/Resources/Info.plist` |

---

## 3. Cryptographic & Keychain Invariants

### 3.1 Keychain Isolation (`CWE-312`, `CWE-522`)

- Service namespace: `com.alsyundawy.SparkleSFTP` (secrets) and `com.alsyundawy.SparkleSFTP.hosttrust` (SSH known hosts).
- Every Keychain write **MUST** specify `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- iCloud-syncable classes (`kSecAttrAccessibleAfterFirstUnlock`, `kSecAttrAccessibleWhenUnlocked`) are statically forbidden by `.swiftlint.yml` (`no_icloud_keychain_sync` at `severity: error`).
- When biometric lock is enabled on a profile or app vault, `SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil)` gates access via `LAContext`.
- On-disk JSON profiles (`ConnectionStore`) and SQLite records (`TransferJournal`) reference secrets solely via opaque `SecretReference` (`UUID`).

### 3.2 SSH Host Key TOFU State Machine (`LOG-001`)

`HostTrustStore` models all six explicit states:

1. `unknown`: Never seen `(host, port)`. Connection pauses while `HostKeyVerificationSheet` presents the SHA-256 fingerprint (`SHA256:<base64>`) and algorithm.
2. `pendingUserDecision(fingerprint)`: Concurrent connection attempts to the same unverified host attach to the same decision state rather than racing prompts.
3. `trusted(fingerprint, since)`: Persisted in Keychain under `host:port`. Verified on subsequent handshakes.
4. `rejected`: User explicitly declined; connection aborts with `AppError.hostKeyRejected`.
5. `mismatch(expected, got)`: Stored fingerprint differs from presented key. Connection **hard-blocks** immediately with `AppError.hostKeyMismatch` and a distinct critical MITM warning UI (requiring explicit manual fingerprint reset in Security Diagnostics to clear).
6. `corrupted`: Keychain trust payload failed decoding; blocks automatic trust and requires explicit user re-verification.

`acceptAnyHostKey` / `acceptAnything` is forbidden in production targets by SwiftLint rule `no_accept_any_host_key`.

### 3.3 FTPS & Plain FTP Policy (`CWE-295`, `CVE-2025-15224`)

- **Explicit FTPS (`ftpsExplicit`, port 21)**: Uses `CURLOPT_USE_SSL = CURLUSESSL_ALL`, `CURLOPT_SSLVERSION = CURL_SSLVERSION_TLSv1_2`, `CURLOPT_SSL_VERIFYPEER = 1`, `CURLOPT_SSL_VERIFYHOST = 2`, plus pre-handshake TLS certificate evaluation via `Network.framework` (`NWProtocolTLS`) + `SecTrustEvaluateWithError` (`SecPolicyCreateSSL` + OCSP revocation).
- **Implicit FTPS (`ftpsImplicit`, port 990)**: `ftps://` scheme with identical TLS 1.2+ and `SecTrust` checks.
- **No Silent Downgrade**: If TLS fails on FTPS, the connection fails closed (`AppError.tlsValidationFailed`). Never silently retries plain FTP.
- **Plain FTP (`ftp`)**: Allowed only when explicitly chosen by user; displays a persistent red unencrypted-transport warning banner in connection editor and commander status bar.
- **CVE-2025-15224 Mitigation**: `libcurl` is strictly scoped via `CURLOPT_PROTOCOLS_STR = "ftp,ftps"` — SSH/SFTP never routes through `libcurl`, eliminating `libssh` SSH-agent bypass paths completely.

### 3.4 Path, Symlink, and Log Hygiene (`CWE-22`, `CWE-59`, `CWE-532`)

- **Path Canonicalization**: `PathValidator.canonicalizeRemote(_:relativeTo:)` normalizes POSIX paths, collapses dot segments, rejects NUL bytes, and verifies containment within expected base paths before download/upload/sync writes.
- **Local Symlink Safety**: `PathValidator.safeLocalDestination(name:baseDirectory:symlinkTarget:)` rejects filenames containing `/` or `..`, rejects symlink targets escaping `baseDirectory`, and inspects local destination components (`realpath` / `resolvingSymlinksInPath()`) before writing.
- **Log Redaction**: All logging flows through `DiagnosticsLogger` (`OSLog`). Private credentials (`password`, `passphrase`, `privateKey`, `secretData`) are never passed to logs; SwiftLint rule `no_password_in_logs` enforces this statically at `severity: error`.

---

## 4. App Sandbox & Distribution Hardening

- Entitlements (`App/SparkleSFTP.entitlements`):
  - `com.apple.security.app-sandbox`: `true`
  - `com.apple.security.network.client`: `true`
  - `com.apple.security.files.user-selected.read-write`: `true`
  - `com.apple.security.files.bookmarks.app-scope`: `true` (for security-scoped folder bookmarks)
- Distribution: Universal 2 (`arm64` + `x86_64`), Hardened Runtime, Developer ID Application signing, `xcrun notarytool` notarization, and Sparkle HTTPS + Ed25519 update verification.

---

## 5. Automated Security Test Matrix

| Test Target | Verified Security Property |
| :--- | :--- |
| `SecurityTests` | 6-state TOFU transitions (`unknown` → `trusted`, `mismatch` block, `corrupted` handling, concurrent pending deduplication) |
| `SecurityTests` | `PathValidator` rejects `../../.ssh/id_rsa`, NUL bytes, symlink escape targets |
| `SecurityTests` | `PrivateKeyParser` decodes OpenSSH Ed25519/ECDSA keys and produces deterministic `SHA256:` fingerprints matching `ssh-keygen` |
| `SecurityTests` | `KeychainService` builds `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` attributes and round-trips secret bytes safely |
| `NetworkingTests` | `SCPCompatibilityAdapter.escapePOSIXSingleQuoted` safely neutralizes `; rm -rf /`, `$(...)`, backticks, and newlines |
| `TransferEngineTests` | Actor reentrancy cancellation leaves zero double-processing or orphaned files; SHA-256 mismatch cleans temporary file |
| `PersistenceTests` | `ConnectionStore` JSON contains zero secret strings after saving profile with Keychain `SecretReference` |
