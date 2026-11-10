# ADR-004: Direct `apple/swift-nio-ssh` (`>= 0.14.1`) and Native SFTP v3 Engine Instead of `Citadel`

## Status

Accepted (Supersedes the `Citadel` backend choice in [ADR-001](0001-tech-stack-and-protocols.md))

## Date

2026-11-11

## Context

[ADR-001](0001-tech-stack-and-protocols.md) initially proposed `orlandos-nl/Citadel` for SSH/SFTP, combined with a security mandate to pin `apple/swift-nio-ssh >= 0.14.1` (mitigating **CVE-2026-43798**) while targeting **macOS 13 Ventura and newer**.

Empirical manifest inspection against upstream `Package.swift` releases on 2026-11-11 uncovered two hard incompatibilities in `Citadel`:

1. **`Citadel 0.12.1` (and `main`) raises its minimum platform floor to `.macOS(.v14)`**, which fails compilation for a `.macOS(.v13)` target.
2. **`Citadel` depends on non-official forks of `swift-nio-ssh`** (`Wellz26/swift-nio-ssh` `"0.3.4" ..< "0.4.0"` in `0.12.1`; `Joannis/swift-nio-ssh` `"0.3.2" ..< "0.4.0"` in `0.7.5`–`0.11.1`) rather than `apple/swift-nio-ssh >= 0.14.1` (`0.15.1`). Resolving both packages simultaneously creates dependency identity conflicts and leaves CVE-2026-43798 mitigation unverified.

Meanwhile, upstream **`apple/swift-nio-ssh` `0.15.1`** (`swift-tools-version:6.1`, `platforms: [.macOS(.v10_15)]`) natively supports Swift 6 strict concurrency, macOS 13+, Ed25519 / ECDSA P-256/384/521 / Secure Enclave keys, password auth, TOFU host key validation delegates, session channels (`SubsystemRequest("sftp")`, `ExecRequest`, `ShellRequest`, `PseudoTerminalRequest`, `WindowChangeRequest`), and `DirectTCPIP` port forwarding.

## Decision

1. **Depend directly on official `apple/swift-nio-ssh` (`"0.15.1" ..< "0.16.0"`)**, alongside `apple/swift-nio` (`from: "2.81.0"`) and `apple/swift-crypto` (`from: "3.12.3"`).
2. **Implement an explicit, testable, RFC/draft-ietf-secsh-filexfer-02 SFTP v3 binary wire codec and actor client** (`SFTPPacketCodec` + `SFTPService`) in `Packages/Networking` directly over `NIOSSHHandler` child session channels (`SubsystemRequest(subsystem: "sftp")`).
3. **Eliminate `Citadel` from `Package.swift`** so there is zero dependency on unverified forks and zero `.macOS(.v14)` platform ceiling breach.

## Alternatives Considered

### Pin `Citadel 0.11.1` (macOS 12+)

- **Pros**: Exposes high-level SFTP helpers.
- **Cons**: Pulls `Joannis/swift-nio-ssh` `0.3.x` instead of `apple/swift-nio-ssh >= 0.14.1` (violates CVE-2026-43798 security invariant).
- **Rejected**: Unacceptable CVE exposure.

### Vendor or Fork `Citadel`

- **Pros**: Keeps Citadel wrappers.
- **Cons**: Requires rewriting `Citadel` internals to match `NIOSSH 0.15.x` breaking changes and maintaining a permanent third-party fork.
- **Rejected**: Direct `NIOSSH` + clean `SFTPPacketCodec` requires less maintenance and gives full control over pipelining, `WINDOW_ADJUST` timeout watchdogs (`RUN-004`), and resume offsets.

## Consequences

- `Package.swift` resolves cleanly with `.macOS(.v13)` and `apple/swift-nio-ssh >= 0.14.1` (`0.15.1`).
- SFTP wire framing (`SSH_FXP_INIT`..`SSH_FXP_EXTENDED`) can be deterministically unit-tested without network sockets.
- Note on private keys: `apple/swift-nio-ssh 0.15.1` natively supports `Ed25519`, `ECDSA P-256`, `ECDSA P-384`, `ECDSA P-521`, and `SecureEnclave.P256` keys (`NIOSSHPrivateKey`). Legacy RSA SSH keys are explicitly flagged in diagnostics until an RSA signer extension is verified against RFC 8332.
