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
| `SwiftTerm` `1.x` vs `1.99.x` | `v1.99.3` requires `swift-tools-version: 6.2` and `swift-png`. `v1.19.0–1.20.0` use `swift-tools-version: 6.0` and `.macOS(.v11)`. | Pin `SwiftTerm` `"1.19.0" ..< "1.99.0"` (resolved `1.20.0`) for Swift 6.0–6.2 and macOS 13+ compatibility. |
| `Sparkle` binary framework in `swift run` | `.xcframework` requires `@rpath/Sparkle.framework` bundled in `.app/Contents/Frameworks` at runtime. | Wire `Sparkle` `2.10.1` cleanly via `Package.swift` + `#if canImport(Sparkle)` adapter, plus `Tools/Release/create-dmg.sh` framework embedding. |

## 3. Build, Lint, and Test Commands

All commands run via `/usr/local/bin/bash -l`:

```bash
# Build all SwiftPM modules and macOS executable
swift build

# Run Swift Testing suite under Command Line Tools macOS SDK
swift test --disable-xctest --enable-swift-testing \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks

# Run SwiftLint strict checks
swiftlint lint --strict

# Run Markdown, YAML, and ShellCheck hygiene checks
npx --yes markdownlint-cli2 "**/*.md" "#.build" "#DerivedData" "#node_modules" "#.trunk"
shellcheck -s bash Tools/**/*.sh
actionlint
```

## 4. Known Scope Boundaries & Honest Capabilities

1. **SSH Private Key Formats**: `apple/swift-nio-ssh 0.15.1` natively signs with `ssh-ed25519`, `ecdsa-sha2-nistp256`, `ecdsa-sha2-nistp384`, `ecdsa-sha2-nistp521`, and Secure Enclave P-256 (`NIOSSHPrivateKey`). `PrivateKeyParser` parses unencrypted OpenSSH v1 Ed25519/ECDSA and PKCS#8 PEM keys cleanly and surfaces an explicit error for unsupported legacy RSA or encrypted keys pending RFC 8332 signer support.
2. **Loopback vs Docker Integration Tests**: An in-process encrypted loopback SSH/SFTP v3 + `DirectTCPIP` server suite (`LoopbackSSHServer` + `LoopbackSFTPIntegrationTests`) runs via `swift test` verifying real SFTP v3 framing, password/Ed25519 auth, TOFU + MITM key rotation blocking, and port forwarding without external containers. Multi-server Docker interop fixtures are defined in `Tools/TestServers/docker-compose.test.yml` and `Tools/TestServers/run-integration-tests.sh` for environments with Docker Engine running.
3. **macOS `.app` Bundling & Notarization**: Running `swift run SparkleSFTP` launches the native SwiftUI + AppKit window directly for development; `Tools/Release/build-universal.sh` and `Tools/Release/create-dmg.sh` produce and verify the Universal 2 (`x86_64 arm64`) `.app` + DMG embedding `Sparkle.framework`, `Info.plist`, and App Sandbox entitlements (`Tools/Release/notarize.sh` requires production Developer ID & notarization credentials).
