# ADR-005: Native `Security.framework`, `SQLite3` Transfer Journal, and `ObservableObject` for macOS 13+ Compatibility

## Status

Accepted (Supersedes `GlasSecretStore` in [ADR-002](0002-security-keychain-and-host-trust.md) and `SwiftData` in [ADR-003](0003-metadata-persistence-swiftdata-vs-json.md))

## Date

2026-11-11

## Context

SparkleSFTP targets **macOS 13 Ventura and newer** (`Package.swift` `.macOS(.v13)`). Earlier planning drafts referenced three components whose upstream availability floors conflict with `macOS 13+`:

1. **`GlasSecretStore` (`msitarzewski/GlasSecretStore`)**: Upstream `Package.swift` declares `.macOS(.v26)` and `swift-tools-version: 6.2`, making it impossible to compile on macOS 13–15 targets.
2. **`SwiftData`**: Apple's `SwiftData` framework requires **macOS 14.0+**, failing compilation on a macOS 13.0 deployment target.
3. **`@Observable` (`Observation` framework)**: The Swift `Observation` macro also requires **macOS 14.0+**.

Additionally, Apple's system macOS SDK ships `/usr/include/sqlite3.h` (`libsqlite3.tbd`) and `/usr/include/curl/curl.h` (`libcurl.tbd`), both universally available across macOS 13+ with zero external SwiftPM packages.

## Decision

1. **Native Keychain & Biometrics (`src/Packages/Security`)**: Use Apple `Security.framework` (`SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete`, `SecAccessControlCreateWithFlags`) + `LocalAuthentication` (`LAContext`) exclusively, enforcing `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` across all items. Remove `GlasSecretStore` completely.
2. **ACID Durable Journal (`src/Packages/Persistence`)**: Implement `TransferJournal` directly over macOS built-in **`SQLite3`** (`WAL` journal mode, indexed `created_at` / `status`, startup crash reconciliation, and deterministic pruning to `10,000` records / `30` days), paired with atomic `Codable` JSON (`ConnectionStore`) for profiles, groups, and snippets.
3. **Presentation State (`src/Features/`)**: Standardize `@MainActor` ViewModels on `ObservableObject` + `@Published` (Combine / SwiftUI macOS 13+ native) rather than `@Observable` (macOS 14+), maintaining single-path code across macOS 13, 14, 15, and newer.

## Alternatives Considered

### `#if` / `@available(macOS 14, *)` Dual Implementations

- **Pros**: Uses SwiftData / `@Observable` on macOS 14+.
- **Cons**: Doubles persistence and ViewModel code paths, increases test matrix surface area, and violates simplicity (`DRY`).
- **Rejected**: Single macOS 13+ code path (`SQLite3` + `ObservableObject`) is faster, smaller, and testable identically everywhere.

### Third-Party SQLite Wrapper (`GRDB.swift` / `SQLite.swift`)

- **Pros**: Query builder sugar.
- **Cons**: Additional supply-chain dependency for one focused table (`transfer_journal`).
- **Rejected**: Direct `import SQLite3` actor wrapper keeps zero third-party database dependencies while remaining strictly encapsulated behind `TransferJournalProtocol`.

## Consequences

- Zero platform-availability hacks needed across macOS 13+.
- Zero external persistence or Keychain supply-chain surface.
- Full ACID WAL durability and bounded retention (`SCALE-002`) verified in unit tests without Core Data container startup overhead.
