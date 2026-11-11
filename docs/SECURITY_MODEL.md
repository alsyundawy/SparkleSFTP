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

| Boundary                                               | Untrusted Input                                                   | STRIDE Threat                                                                          | Enforced Control                                                                                                                                                                                                                                                                                                                                                          | Code Owner                                                                                                                                                   |
| :----------------------------------------------------- | :---------------------------------------------------------------- | :------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | :----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **TB-1: SSH Handshake**                                | Remote server host key & KEX packets                              | **S**poofing (MITM), **T**ampering, Memory Corruption (CVE-2026-43798)                 | Pin `apple/swift-nio-ssh >= 0.14.1` (`0.15.1`); 6-state TOFU `HostTrustStore`; hard block on `.mismatch`                                                                                                                                                                                                                                                                  | `src/Packages/Security/HostTrustStore.swift`, `src/Packages/Networking/SSHClientService.swift`                                                               |
| **TB-2: FTPS TLS**                                     | Server X.509 certificate chain & FTP `AUTH TLS` reply             | **S**poofing, **I**nformation Disclosure, Downgrade                                    | `SecTrustEvaluateWithError` (`SecPolicyCreateSSL` + `kSecRevocationOCSPMethod`); TLS 1.2+ min; zero downgrade to plain FTP                                                                                                                                                                                                                                                | `src/Packages/Security/TLSCertificateValidator.swift`, `src/Packages/Networking/FTPService.swift`                                                            |
| **TB-3: Credential Storage**                           | Secrets entered in UI or imported from FileZilla / WinSCP         | **I**nformation Disclosure (iCloud sync, plaintext DB, logs, encrypted external blobs) | `KeychainService` with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + optional Touch ID (`LAContext`); FileZilla `<Pass encoding="crypt">` and malformed/Master-Password WinSCP (`UseMasterPassword=1`) secrets flagged `.encryptedUnavailable` (standard/legacy `0xA3` WinSCP secrets decrypted transiently straight to Keychain); zero secrets in JSON/SQLite/`OSLog` | `src/Packages/Security/KeychainService.swift`, `src/Packages/Persistence/ExternalImporters.swift`                                                            |
| **TB-4: Remote File Listings & Symlinks**              | Server filenames, `../`, symlink targets                          | **T**ampering / Arbitrary local overwrite (CWE-22, CWE-59)                             | `PathValidator` canonicalization + base-dir containment + symlink escape check + `visitedInodes` loop detection                                                                                                                                                                                                                                                           | `src/Packages/Security/PathValidator.swift`, `src/Packages/Synchronization/DirectoryScanner.swift`                                                           |
| **TB-5: SCP, Custom SSH Commands & External Terminal** | Filenames/hosts/usernames containing `;`, `$()`, quotes, newlines | **E**levation / Remote Command Injection (CWE-78)                                      | Reject NUL bytes/control characters (`< 0x20`, `0x7F`); strict POSIX single-quote escaping (`'\\''` via `PathValidator.escapePOSIXSingleQuoted`) across SCP, Custom SSH Commands (`{file}`/`{path}`/`{dir}`), Command-Line insertion & `0o700` temp scripts                                                                                                               | `src/Packages/Security/PathValidator.swift`, `src/Packages/Networking/SCPCompatibilityAdapter.swift`, `src/Packages/Terminal/ExternalTerminalLauncher.swift` |
| **TB-6: Application Updates & Decompression**          | Remote Appcast XML, DMG payloads, or `zlib`/`gzip` streams        | **T**ampering / Resource Exhaustion (**CWE-409** Zip Bomb)                             | `UpdateConfigurationValidator` enforces HTTPS feeds + 32-byte Ed25519 `SUPublicEDKey`; `ClibcurlSystemLibs.c` & `ZlibCompressionCodec` cap inflate allocations via strict `max_output_bytes` & `UINT32_MAX` guards                                                                                                                                                        | `src/App/SparkleUpdaterService.swift`, `src/Packages/Clibcurl/ClibcurlSystemLibs.c`, `src/Packages/Networking/ZlibAndLibraryProbes.swift`                    |

---

## 3. Cryptographic & Keychain Invariants

### 3.1 Keychain Isolation (`CWE-312`, `CWE-522`)

- Service namespace: `com.alsyundawy.SparkleSFTP` (secrets) and `com.alsyundawy.SparkleSFTP.hosttrust` (SSH known hosts).
- Every Keychain write **MUST** specify `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- iCloud-syncable classes (`kSecAttrAccessibleAfterFirstUnlock`, `kSecAttrAccessibleWhenUnlocked`) are statically forbidden by `.swiftlint.yml` (`no_icloud_keychain_sync` at `severity: error`).
- When biometric lock is enabled on a profile or app vault, `SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil)` gates access via `LAContext`.
- On-disk JSON profiles (`ConnectionStore`) and SQLite records (`TransferJournal`) reference secrets solely via opaque `SecretReference` (`UUID`). Cloning a connection profile (`AppState.cloneProfile`) duplicates stored secrets under fresh `SecretReference` IDs so deleting or rotating credentials on a clone never mutates or removes the original connection's Keychain items.

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

- **Explicit FTPS (`ftpsExplicit`, port 21)**: Uses `CURLOPT_USE_SSL = CURLUSESSL_ALL`, `CURLOPT_SSLVERSION = CURL_SSLVERSION_TLSv1_2`, `CURLOPT_SSL_VERIFYPEER = 1`, `CURLOPT_SSL_VERIFYHOST = 2` via `libcurl` over `AUTH TLS` STARTTLS (`SecTrust` preflight applies to direct TLS Implicit FTPS; `TD-10` tracks STARTTLS `SecTrust`/OCSP hook parity).
- **Implicit FTPS (`ftpsImplicit`, port 990)**: `ftps://` scheme with identical TLS 1.2+ enforcement plus pre-handshake `NWProtocolTLS` + `SecTrustEvaluateWithError` (`SecPolicyCreateSSL` + OCSP revocation).
- **No Silent Downgrade**: If TLS fails on FTPS, the connection fails closed (`AppError.tlsValidationFailed`). Never silently retries plain FTP.
- **Plain FTP (`ftp`)**: Allowed only when explicitly chosen by user; displays a persistent red unencrypted-transport warning banner in connection editor and commander status bar.
- **CVE-2025-15224 Mitigation**: `libcurl` is strictly scoped via `CURLOPT_PROTOCOLS_STR = "ftp,ftps"` — SSH/SFTP never routes through `libcurl`, eliminating `libssh` SSH-agent bypass paths completely.

### 3.4 Path, Symlink, and Log Hygiene (`CWE-22`, `CWE-59`, `CWE-532`)

- **Path Canonicalization**: `PathValidator.canonicalizeRemote(_:relativeTo:)` normalizes POSIX paths, collapses dot segments, rejects NUL bytes, and verifies containment within expected base paths before download/upload/sync writes.
- **Local Symlink Safety**: `PathValidator.safeLocalDestination(name:baseDirectory:symlinkTarget:)` rejects filenames containing `/` or `..`, rejects symlink targets escaping `baseDirectory`, and inspects local destination components (`realpath` / `resolvingSymlinksInPath()`) before writing.
- **Log Redaction**: All logging flows through `DiagnosticsLogger` (`OSLog`). Private credentials (`password`, `passphrase`, `privateKey`, `secretData`) are never passed to logs; SwiftLint rule `no_password_in_logs` enforces this statically at `severity: error`.

---

## 4. App Sandbox & Distribution Hardening

- Entitlements (`src/App/SparkleSFTP.entitlements`):
  - `com.apple.security.app-sandbox`: `true`
  - `com.apple.security.network.client`: `true`
  - `com.apple.security.files.user-selected.read-write`: `true`
  - `com.apple.security.files.bookmarks.app-scope`: `true` (for security-scoped folder bookmarks)
- Distribution: Universal 2 (`arm64` + `x86_64`), Hardened Runtime, Developer ID Application signing, `xcrun notarytool` notarization, and Sparkle HTTPS + Ed25519 update verification.

---

## 5. Automated Security Test Matrix

| Test Target                                | Verified Security Property                                                                                                                                                         |
| :----------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `SecurityTests`                            | 6-state TOFU transitions (`unknown` → `trusted`, `mismatch` block, `corrupted` handling, concurrent pending deduplication)                                                         |
| `SecurityTests`                            | `PathValidator` rejects `../../.ssh/id_rsa`, NUL bytes, symlink escape targets                                                                                                     |
| `SecurityTests`                            | `PrivateKeyParser` decodes OpenSSH Ed25519/ECDSA keys and produces deterministic `SHA256:` fingerprints matching `ssh-keygen`                                                      |
| `SecurityTests`                            | `KeychainService` builds `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` attributes and round-trips secret bytes safely                                                             |
| `NetworkingTests` / `IntegrationTests`     | `SCPCompatibilityAdapter` & `ExternalTerminalLauncher` neutralize `; rm -rf /`, `$(...)`, backticks, and control chars; `ZlibCompressionCodec` rejects `CWE-409` zip-bomb payloads |
| `TransferEngineTests` / `IntegrationTests` | Actor reentrancy cancellation leaves zero double-processing; SHA-256 mismatch cleans temporary file; FIFO `pendingConflictQueue` serializes concurrent prompts                     |
| `PersistenceTests`                         | `ConnectionStore` JSON contains zero secret strings after saving profile with Keychain `SecretReference`                                                                           |
