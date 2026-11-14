# ADR-0009: Internal Configuration Bundle Format, Cryptographic Vault & Cross-Client Import Policy

## Status

Accepted

## Date

2026-11-14

## Context

Prior to SparkleSFTP v0.6.0, connection profile backups were limited to plaintext JSON exports and partial FileZilla XML exports. Users managing enterprise server fleets required:
1. **Authenticated Zero-Knowledge Encryption**: Exporting sensitive credentials (passwords, private key passphrases, endpoints) safely to disk or cloud storage without plaintext exposure.
2. **Selective Export Scopes**: Ability to export only specific subsystems (e.g. profiles only, bookmarks only, or full configuration state).
3. **Cross-Platform & Cross-Client Portability**: Seamless migration from legacy SparkleSFTP exports, FileZilla `sitemanager.xml`, WinSCP `WinSCP.ini`, and OpenSSH `~/.ssh/config`.
4. **Deterministic Conflict Resolution**: Safe handling of name collisions, duplicate UUIDs, and group tree merging.

## Decision

1. **Dual Bundle Format (`.sparkleconfig` & `.sparklevault`)**:
   - Plaintext bundle (`.sparkleconfig`): Structured JSON adhering to `SparkleConfigBundle` schema with SHA-256 payload integrity digest and ISO 8601 timestamps.
   - Encrypted vault (`.sparklevault`): Self-contained binary archive consisting of a 46-byte authenticated binary header (`SparkleVaultHeader`) prepended to AES-256-GCM ciphertext.

2. **Cryptographic Key Derivation & AEAD Cipher Suite (`ConfigBundleCrypto`)**:
   - **KDF**: PBKDF2-HMAC-SHA256 with 600,000 iterations (exceeding OWASP 2024–2026 recommendations) and a cryptographically secure 16-byte random salt.
   - **Cipher**: AES-256-GCM authenticated encryption with a 12-byte random nonce and 16-byte authentication tag.
   - **AAD Binding**: The entire 46-byte binary header is bound as Additional Authenticated Data (AAD) during encryption and decryption to prevent header tampering.
   - **Memory Zeroization**: Symmetric key material, derived keys, and plaintext buffers are explicitly zeroed out in memory upon completion.

3. **46-Byte Binary Header Layout (`SPKVAULT1`)**:
   - Bytes 0–8: Magic bytes ASCII `SPKVAULT1` (9 bytes)
   - Byte 9: Version (0x01)
   - Bytes 10–11: Feature flags (16-bit big endian)
   - Byte 12: KDF Identifier (0x01 = PBKDF2-HMAC-SHA256)
   - Bytes 13–16: KDF Iteration count (32-bit big endian, 600,000)
   - Bytes 17–32: KDF Salt (16 bytes)
   - Bytes 33–44: GCM Initialization Vector (12 bytes)
   - Byte 45: Reserved / Tag length indicator

4. **Multi-Source Importer & Conflict Engine (`ConfigImporter`)**:
   - **Auto-Detection**: Stream sniffing automatically identifies format: `.sparkleVault`, `.sparkleConfig`, `.legacyExport`, `.fileZillaXML`, `.winSCPINI`, or `.openSSHConfig`.
   - **Conflict Policies**:
     - `.skipExisting`: Retains existing profiles without alteration.
     - `.overwrite`: Updates matching items by UUID or normalized host/port/user signature.
     - `.keepBoth`: Generates distinct copy names (e.g., `Node (Imported)`).
     - `.mergeGroups`: Preserves folder trees and nests incoming profiles into existing groups.

## Consequences

- Fully verified by unit test suites (`ConfigBundleCryptoTests`, `ConfigImporterTests`) and end-to-end integration tests.
- Reversible and safe: Plaintext exports write with POSIX file permissions `0600` to prevent unauthorized read access by other local users.
- Forward compatible: The 46-byte binary header supports future KDF upgrades (e.g. Argon2id) via the KDF ID field without breaking legacy decryption paths.
