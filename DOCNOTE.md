# DOCNOTE — SparkleSFTP Engineering & Architecture Notes

## 1. Project Lineage & Rebranding

**SparkleSFTP** evolved from the initial `MacSFTP` architecture specification. All documentation, SwiftPM targets, bundle identifiers (`com.alsyundawy.SparkleSFTP`), Keychain service namespaces, and `OSLog` subsystems are standardized as **SparkleSFTP**, incorporating all 55 findings from [`docs/CODE_REVIEW_14_PILLARS.md`](docs/CODE_REVIEW_14_PILLARS.md).

## 2. Critical Verified Findings (Why Implementation Diverges from Early Drafts)

Every dependency in [`Package.swift`](Package.swift) was verified against upstream manifests and the live Swift 6.2.4 / macOS SDK toolchain before writing code (see [ADR-004](docs/ADR/0004-direct-swift-nio-ssh-and-sftp-codec.md) and [ADR-005](docs/ADR/0005-macos13-sqlite3-journal-and-observable-object.md)):

| Initial Plan Assumption | Empirical Verification Result | Implemented Resolution |
| :--- | :--- | :--- |
| `orlandos-nl/Citadel` + `swift-nio-ssh >= 0.14.1` on macOS 13+ | `Citadel 0.12.1` requires `.macOS(.v14)` and depends on fork `Wellz26/swift-nio-ssh` (`0.3.4`), while `0.11.1` depends on `Joannis/swift-nio-ssh` (`0.3.2`). Neither resolves `apple/swift-nio-ssh >= 0.14.1` (CVE-2026-43798 fix). | Use **`apple/swift-nio-ssh` (`0.15.1`)** directly (`.macOS(.v10_15)`, Swift 6) + dedicated RFC SFTP v3 binary codec (`SFTPPacketCodec` + `SFTPService`). |
| `msitarzewski/GlasSecretStore` | `Package.swift` sets `.macOS(.v26)` and `swift-tools-version: 6.2`. Incompatible with macOS 13–15. | Native `KeychainService` over Apple **`Security.framework`** + **`LAContext`** enforcing `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. |
| `SwiftData` for `TransferJournal` | `SwiftData` requires **macOS 14.0+**. | Built-in macOS **`SQLite3`** (`WAL` mode) for ACID `TransferJournal` + atomic `Codable` JSON `ConnectionStore`. |
| `@Observable` ViewModels | `Observation` macro requires **macOS 14.0+**. | `@MainActor` `ObservableObject` + `@Published` ViewModels across `Features/` for uniform macOS 13+ compatibility. |
| Direct Swift calls to `curl_easy_setopt` | C variadic functions are unavailable in Swift (`curl_easy_setopt`). | Non-variadic typed C helper wrapper in `Packages/Clibcurl` (`sparklesftp_curl_setopt_*`) linking system `-lcurl`. |
| `SwiftTerm` `1.x` vs `1.99.x` & `@MainActor` Delegate | `v1.99.3` requires `swift-tools-version: 6.2` and `swift-png`, while SE-0470 `@MainActor TerminalViewDelegate` fails to compile on `macos-15` Xcode Swift 6.0/6.1 runners. | Pin `SwiftTerm` `"1.19.0" ..< "1.99.0"` (resolved `1.20.0`), keep `@MainActor` on `Coordinator`, and dispatch `nonisolated TerminalViewDelegate` callbacks safely onto `MainActor` (`TerminalViewRepresentable.swift`). |
| `Sparkle` binary framework in `swift run` | `.xcframework` requires `@rpath/Sparkle.framework` bundled in `.app/Contents/Frameworks` at runtime; unsigned/HTTP feeds or placeholder `SUPublicEDKey` must not run updates. | Wire `Sparkle` `2.10.1` via `Package.swift` + `#if canImport(Sparkle)` adapter, enforce HTTPS + 32-byte Ed25519 key in `UpdateConfigurationValidator`, and bundle framework in `Tools/Release/create-dmg.sh`. |

## 3. Build, Lint, and Test Commands

All commands run via `/usr/local/bin/bash -l` (bounded parallelism `-j 2`):

```bash
# Build all SwiftPM modules and macOS executable
swift build -j 2

# Run Swift Testing suite under Command Line Tools macOS SDK
swift test -j 2 --disable-xctest --enable-swift-testing \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks

# Run SwiftLint & SwiftFormat checks
swiftlint lint --strict
swiftformat --lint .

# Run Markdown, YAML, GitHub Actions, and ShellCheck hygiene checks
npx --yes markdownlint-cli2 "**/*.md" "#.build" "#DerivedData" "#node_modules" "#.trunk"
yamllint -c .yamllint.yml .
shellcheck -s bash Tools/**/*.sh
shfmt -d -i 2 -ci Tools/**/*.sh
actionlint
```

## 4. Known Scope Boundaries & Honest Capabilities

1. **SSH Private Key Formats**: `apple/swift-nio-ssh 0.15.1` natively signs with `ssh-ed25519`, `ecdsa-sha2-nistp256`, `ecdsa-sha2-nistp384`, `ecdsa-sha2-nistp521`, and Secure Enclave P-256 (`NIOSSHPrivateKey`). `PrivateKeyParser` parses unencrypted OpenSSH v1 Ed25519/ECDSA and PKCS#8 PEM keys cleanly and surfaces an explicit error for unsupported legacy RSA or encrypted keys pending RFC 8332 signer support.
2. **Loopback vs Docker Integration Tests**: An in-process encrypted loopback SSH/SFTP v3 + `DirectTCPIP` server suite (`LoopbackSSHServer` + `LoopbackSFTPIntegrationTests` + `LoopbackAdvancedIntegrationTests`, 45 tests across 11 suites) runs via `swift test` verifying real SFTP v3 framing, password/Ed25519 auth, TOFU + MITM key rotation blocking, SOCKS5/HTTP proxy tunnels, `ProxyJump` bastion chains, and `-L`/`-R` port forwarding without external containers. Multi-server Docker interop fixtures are defined in `Tools/TestServers/docker-compose.test.yml` and `Tools/TestServers/run-integration-tests.sh` for environments with Docker Engine running.
3. **macOS `.app` Bundling, CI Release & Notarization**: Running `swift run SparkleSFTP` launches the native SwiftUI + AppKit window directly for development; `Tools/Release/build-universal.sh` and `Tools/Release/create-dmg.sh` (plus `.github/workflows/release.yml` on `v*` tags) produce and verify the Universal 2 (`x86_64 arm64`) `.app` + `.dmg` + `.sha256` embedding `Sparkle.framework`, `Info.plist`, and App Sandbox entitlements (`Tools/Release/notarize.sh` requires production Developer ID & notarization credentials).
