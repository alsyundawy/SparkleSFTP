# ADR-003: Metadata Persistence Strategy (JSON vs SwiftData)

## Status

Accepted _(`TransferJournal` storage backend superseded from SwiftData to system `SQLite3` in [ADR-005](0005-macos13-sqlite3-journal-and-observable-object.md))_

## Date

2026-11-11

## Context

SparkleSFTP persists two very different categories of non-secret data:

1. **Connection Profiles & Bookmarks** (`ConnectionProfile`, server groups, favorites — typically tens to a few hundred records, read mostly on launch/connect).
2. **Transfer Journal & Crash Recovery Records** (`TransferJournal` — high-frequency checkpoint writes, state transitions, bounded retention up to 10,000 entries / 30 days, interrupted-job reconciliation on restart).

Using SwiftData indiscriminately for tiny configuration profiles introduces unnecessary Core Data migration complexity (`PERF-005`, `MAINT-002`), whereas plain JSON without structured querying is risky for high-frequency durable transfer checkpoints (`SCALE-002`).

## Decision

Adopt a **split persistence strategy** behind `Core` repository interfaces:

1. **`ConnectionStore` (JSON + `Codable`)**: Store non-secret `ConnectionProfile` metadata, groups, and UI preferences as atomic versioned JSON files (`schemaVersion`), keeping backup/export/import simple and avoiding Core Data schema migration overhead for small datasets.
2. **`TransferJournal` (SwiftData / Durable Store)**: Persist active and historical transfer checkpoints, pause/resume offsets, and crash-recovery records in a structured store with bounded retention (30 days or max 10,000 entries, oldest pruned first).
3. **Strict Secret Separation**: Neither store may ever persist passwords, passphrases, or private key bytes; only opaque `SecretReference` UUIDs pointing to Apple Keychain are allowed.

## Alternatives Considered

### SwiftData for Everything

- **Pros**: Unified persistence stack.
- **Cons**: Unnecessary Core Data stack weight and migration boilerplate for `< 1,000` connection profiles.
- **Rejected**: Overkill for simple portable profile lists (`PERF-005`).

### Plain JSON for TransferJournal

- **Pros**: Minimal dependencies.
- **Cons**: Full-file serialization on high-frequency transfer progress checkpoints does not scale cleanly and complicates crash-safe partial updates.
- **Rejected**: Durable transfer recovery benefits from transactional structured storage.

## Consequences

- `ConnectionProfile` export/import (including FileZilla XML / Commander `.ini` / `.ssh/config` imports) stays clean and human-debuggable.
- `TransferJournal` enforces bounded retention (`SCALE-002`) and remote metadata revalidation before resuming interrupted transfers (`LOG-002`).
