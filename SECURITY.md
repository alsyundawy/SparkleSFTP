# Security Policy

## Reporting a Vulnerability

SparkleSFTP treats credential protection, host identity verification, TLS validation, and file-system boundary safety as core non-negotiable invariants.

If you discover a security vulnerability, **please do not open a public GitHub issue**. Instead, report it privately via the SparkleSFTP GitHub **[Security Advisories](https://github.com/alsyundawy/SparkleSFTP/security/advisories/new)** page.

When reporting a vulnerability, please include:

- A clear description of the vulnerability and its potential impact.
- Affected protocol or component (e.g., SFTP, FTPS/FTP, SCP, Keychain, Terminal PTY, TransferEngine).
- Step-by-step reproduction instructions or a minimal proof of concept.
- Your macOS version, architecture (`arm64` or `x86_64`), and SparkleSFTP build version/commit.

## Supported Versions

| Version | Supported | Notes |
| :--- | :--- | :--- |
| `main` (Pre-release / Development) | ✅ | Active architecture & implementation branch |
| Future `1.x` releases | ✅ | Only the latest released version receives security patches |

## Mandatory Security Invariants

All contributions and future releases of SparkleSFTP must uphold these baseline security controls:

1. **SSH Host Key Verification (TOFU)**: Unknown host keys require explicit user confirmation; changed host keys must block connection (`acceptAnyHostKey` / `.acceptAnything()` is prohibited).
2. **Keychain Isolation (CWE-312 / CWE-522)**: All secrets (passwords, passphrases, private keys) must be stored in Apple Keychain using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — never synced to iCloud and never stored in plaintext databases.
3. **TLS / FTPS Enforcement (CWE-295)**: Explicit `SecTrust` chain, hostname, expiry, and revocation validation via `SecTrustEvaluateWithError`, with TLS 1.2 minimum (TLS 1.3 preferred) and zero silent downgrade from FTPS to plain FTP.
4. **Known Dependency CVE Baselines**:
   - `swift-nio-ssh >= 0.14.1` (mitigates **CVE-2026-43798** pre-auth OOB stack write).
   - `libcurl` built against `libssh2` (not `libssh`, mitigating **CVE-2025-15224** SSH agent auth bypass).
5. **Path & Symlink Containment (CWE-22 / CWE-59)**: Strict path canonicalization and symlink target/inode loop checks prior to local or remote file writes.
6. **Zero Secret Leakage in Logs (CWE-532)**: Mandatory `OSLog` privacy annotations; passwords, passphrases, and private keys must never appear in logs or crash dumps.
7. **Signed Updates**: Sparkle update feeds must use HTTPS with Ed25519 signature verification (`SUPublicEDKey`); unsigned updates must be rejected.
