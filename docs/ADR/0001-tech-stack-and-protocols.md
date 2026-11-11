# ADR-001: Native Swift 6 Tech Stack and Protocol Engines

## Status

Accepted *(SSH/SFTP transport choice partially superseded by [ADR-004](0004-direct-swift-nio-ssh-and-sftp-codec.md))*

## Date

2026-11-11

## Context

SparkleSFTP aims to deliver a high-performance, native macOS dual-pane SFTP, FTP/FTPS, SCP, and SSH Commander without Electron or webview memory overhead. We must choose primary protocol libraries for SSH/SFTP, terminal emulation, and FTP/FTPS that satisfy:

- Swift 6 strict concurrency and `Sendable` ergonomics
- Active maintenance and timely CVE patching
- MIT-compatible licensing
- Support for macOS 13 Ventura and newer (Universal 2 `arm64` + `x86_64`)

## Decision

1. **Language & UI**: **Swift 6** with **SwiftUI** for chrome/layouts (`NavigationSplitView`, `HSplitView`) bridged to AppKit **`NSTableView`** via `NSViewRepresentable` for high-volume directory listings (10K–100K+ entries).
2. **SSH & SFTP**: **`orlandos-nl/Citadel`** on top of **`apple/swift-nio-ssh`** with an explicit minimum version pin of **`swift-nio-ssh >= 0.14.1`** (mitigates **CVE-2026-43798** pre-auth OOB stack write).
3. **Terminal Emulation**: **`migueldeicaza/SwiftTerm`** integrated via `NSViewRepresentable` with explicit PTY lifecycle teardown.
4. **FTP & FTPS (Explicit/Implicit)**: **`libcurl`** via C module map bridge compiled against **`libssh2`** (explicitly prohibiting `libssh` to avoid **CVE-2025-15224** SSH agent auth bypass).
5. **SCP Compatibility**: Isolated in a dedicated `SCPCompatibilityAdapter` only activated when an SSH server lacks the SFTP subsystem, with strict POSIX single-quote shell escaping (`SEC-007`).

## Alternatives Considered

### Electron / WebView UI

- **Pros**: Cross-platform UI speed.
- **Cons**: High baseline RAM footprint, non-native file-list scrolling performance, weak native Keychain/Touch ID ergonomics.
- **Rejected**: Conflicts with the core native macOS performance invariant.

### libssh2 as Primary SSH/SFTP Engine

- **Pros**: Long-lived C library.
- **Cons**: Manual async bridging, C callback boilerplate, less ergonomic Swift 6 actor integration compared to SwiftNIO SSH / Citadel.
- **Rejected as primary**: Citadel + SwiftNIO SSH aligns directly with Swift 6 structured concurrency and Apple DTS recommendations.

## Consequences

- All protocol dependencies remain MIT or MIT/curl compatible.
- Package resolution must enforce `swift-nio-ssh >= 0.14.1` and audit dependency graphs in CI.
- UI code remains decoupled from `Citadel`, `libcurl`, and `SwiftTerm` internals behind `Core` protocols.
