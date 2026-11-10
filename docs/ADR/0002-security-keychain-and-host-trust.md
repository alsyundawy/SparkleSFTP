# ADR-002: Keychain Isolation, Host Trust State Machine, and TLS Validation

## Status

Accepted

## Date

2026-11-11

## Context

An SFTP/FTPS/SSH client handles high-value secrets (passwords, passphrases, private keys) and connects to untrusted remote hosts over hostile networks. Our 14-pillar code review identified multiple critical risks if defaults are left implicit:

- `GlasSecretStore` maintenance uncertainty (`BUG-004`, `DUP-002`)
- Keychain accessibility defaults syncing secrets to iCloud (`SEC-002` / CWE-522 / CWE-312)
- Incomplete TOFU host key state transitions (`LOG-001`)
- Unspecified `SecTrust` TLS validation (`SEC-001` / CWE-295)

## Decision

1. **Primary Keychain Implementation**: Build a native `KeychainService` directly over Apple **`Security.framework`** rather than depending on unverified single-maintainer wrappers (`DUP-002`).
2. **Device-Locked Keychain Accessibility**: Every Keychain item must enforce `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and `SecAccessControlCreateWithFlags` (with optional `.userPresence` / Touch ID gating), under service namespace `com.alsyundawy.SparkleSFTP`.
3. **Complete Host Trust State Machine (`HostTrustStore`)**: Model all six explicit states (`unknown`, `pendingUserDecision`, `trusted`, `rejected`, `mismatch`, `corrupted`) stored in Keychain rather than `UserDefaults`. Any `mismatch` blocks connection immediately.
4. **Explicit TLS Certificate Policy**: Validate FTPS certificates using `SecPolicyCreateSSL(true, host as CFString)` + `SecPolicyCreateRevocation(kSecRevocationOCSPMethod)` + `SecTrustEvaluateWithError`, with TLS 1.2 minimum (TLS 1.3 preferred) and no silent downgrade to plain FTP.

## Alternatives Considered

### Third-Party `GlasSecretStore` Only

- **Pros**: Slightly less boilerplate wrapper code.
- **Cons**: Single-maintainer dependency risk for Swift 6 compatibility and security audits (`BUG-004`).
- **Rejected**: Direct `Security.framework` usage eliminates external risk on the most critical security boundary.

### `UserDefaults` for Known Hosts

- **Pros**: Simple key-value storage.
- **Cons**: Unprotected plain plist easily tampered with locally; lacks Keychain ACL guarantees.
- **Rejected**: Fingerprints belong in Keychain / protected trust store.

## Consequences

- SwiftLint rules (`no_icloud_keychain_sync`, `no_accept_any_host_key`, `no_password_in_logs`) enforce these invariants statically at build time.
- Connection metadata stored on disk references secrets solely by opaque UUID (`SecretReference`).
