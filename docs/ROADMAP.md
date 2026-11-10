# SparkleSFTP Roadmap & Release Gates

This document tracks the 8-phase delivery plan, Workground mapping, and mandatory release criteria for **SparkleSFTP**.

## Workground & Phase Mapping

| Workground | Scope | Target Phase | Dependencies | Status |
| :--- | :--- | :--- | :--- | :--- |
| **WG-1** | Repository, Xcode/SPM setup, Domain contracts, CI | Phase 01–02 | — | 🟡 Repo Bootstrapped |
| **WG-7** | KeychainService (`WhenUnlockedThisDeviceOnly`), HostTrustStore (TOFU), Touch ID, SSH config | Phase 03 | WG-1 | ⏳ Planned |
| **WG-2** | Core SSH & SFTP Engine (`Citadel`, `swift-nio-ssh >= 0.14.1`, SCP adapter) | Phase 04 | WG-1, WG-7 | ⏳ Planned |
| **WG-3** | FTP & Explicit/Implicit FTPS Engine (`libcurl` + `libssh2` + `SecTrust`) | Phase 04 | WG-1, WG-7 | ⏳ Planned |
| **WG-4** | UI Shell & Dual-Pane Commander (`NavigationSplitView`, `HSplitView`, `NSTableView`) | Phase 05 | WG-1 | ⏳ Planned |
| **WG-6** | Actor Transfer Engine (`TransferQueue`, `TransferJournal`, resume, atomic upload) | Phase 06 | WG-2, WG-3, WG-4 | ⏳ Planned |
| **WG-5** | Integrated SSH Terminal (`SwiftTerm` PTY, multi-tab, split panes) | Phase 07 | WG-2, WG-4 | ⏳ Planned |
| **WG-8** | Directory Sync (`SyncPlanner` + expiry), Remote Editor, Port Forwarding, Importers | Phase 07 | WG-2, WG-5, WG-6 | ⏳ Planned |
| **WG-9** | Full Docker Interop QA, Security Audit, Universal 2 Signing, Notarization, Sparkle | Phase 08 | All | ⏳ Planned |

## Phased Delivery Timeline

| Phase | Milestone | Estimated Duration | Key Deliverables |
| :--- | :--- | :--- | :--- |
| **Phase 01** | Research & Architecture | Weeks 1–2 | License audit, Citadel & libcurl PoCs, threat model, ADRs |
| **Phase 02** | Foundation & UI Framework | Weeks 3–4 | Swift 6 Xcode project, pinned SPM deps, DesignSystem, CI |
| **Phase 03** | Connection & Security | Weeks 5–7 | Connection profiles, Keychain ACLs, TOFU UI, `SecTrust` TLS validation |
| **Phase 04** | Protocol Engine | Weeks 8–11 | `SFTPService`, `SSHService`, `FTPService`, capability detection, Docker tests |
| **Phase 05** | Commander File Manager | Weeks 12–14 | Dual-pane `NSTableView`, F5–F8 Commander shortcuts, Quick Look, drag-and-drop |
| **Phase 06** | Transfer Engine | Weeks 15–17 | Actor queue, per-host throttling, crash journal recovery, atomic uploads |
| **Phase 07** | Advanced Features | Weeks 18–21 | SwiftTerm tabs/splits, port forwarding, dry-run sync, remote editor, EN/ID i18n |
| **Phase 08** | QA & Release | Weeks 22–24 | 10GB transfer stress tests, PTY leak checks, Developer ID notarization, Sparkle DMG |

## Non-Negotiable MVP Release Gate

Before cutting `v1.0.0`, every condition below must pass with empirical test evidence:

- [ ] `swift-nio-ssh >= 0.14.1` pinned and verified (**CVE-2026-43798** mitigated).
- [ ] `libcurl` configured with `libssh2` backend rather than `libssh` (**CVE-2025-15224** mitigated).
- [ ] All Keychain entries enforce `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (**CWE-312 / CWE-522**).
- [ ] Host key mismatch blocks connection with explicit alert; `acceptAnyHostKey` does not exist in production code.
- [ ] FTPS enforces `SecTrustEvaluateWithError` (chain, hostname, expiry, OCSP) with zero auto-downgrade to plain FTP.
- [ ] Path traversal (`../`) and malicious symlink targets are rejected before local/remote write (**CWE-22 / CWE-59**).
- [ ] Zero credentials or private keys in `OSLog` / Console.app output (**CWE-532**).
- [ ] Actor reentrancy cancellation tests and 100-tab PTY leak tests pass without leaks or crashes.
- [ ] Multi-GB (10GB+) transfer verification runs off `MainActor` without UI stalls.
- [ ] Universal Binary (`arm64` + `x86_64`), Developer ID signed, notarized (`xcrun notarytool`), and Sparkle Ed25519 verified.
