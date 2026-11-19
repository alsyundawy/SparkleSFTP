import Foundation
import SparkleCore
import SQLite3

public extension TransferJournal {
    /// Validates whether an open SQLite database handle passes `PRAGMA quick_check`.
    static func isDatabaseCorrupt(handle: OpaquePointer) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA quick_check;", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return true
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
            let result = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return result != "ok"
        }
        return true
    }

    /// Moves a damaged database and related journal files to a timestamped quarantine path.
    static func quarantineCorruptDatabase(at url: URL) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let corruptURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt.\(timestamp)")
        try? FileManager.default.moveItem(at: url, to: corruptURL)
        let walURL = URL(fileURLWithPath: url.path + "-wal")
        let shmURL = URL(fileURLWithPath: url.path + "-shm")
        try? FileManager.default.removeItem(at: walURL)
        try? FileManager.default.removeItem(at: shmURL)
    }

    /// Safely opens a database, performing integrity verification and auto-quarantine upon corruption.
    static func openAndValidateDatabase(at databaseURL: URL) throws -> OpaquePointer {
        try ensureParentDirectory(for: databaseURL)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        var openResult = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        if openResult == SQLITE_OK, let opened = handle {
            if isDatabaseCorrupt(handle: opened) {
                sqlite3_close(opened)
                handle = nil
                quarantineCorruptDatabase(at: databaseURL)
                openResult = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
            }
        }

        guard openResult == SQLITE_OK, let opened = handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 failed"
            if let handle {
                sqlite3_close(handle)
            }
            throw AppError.persistenceFailure(reason: message)
        }
        return opened
    }

    /// Purges orphaned `.sparklesftp.*.filepart` checkpoint files older than `maxAgeDays`.
    static func cleanupOrphanFileparts(
        inDirectory directoryURL: URL,
        maxAgeDays: Int = 7,
        fileManager: FileManager = .default
    ) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86400)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        ) else { return 0 }
        var removed = 0
        for file in files {
            let name = file.lastPathComponent
            if name.hasPrefix(".sparklesftp.") && name.hasSuffix(".filepart") {
                if let attrs = try? fileManager.attributesOfItem(atPath: file.path),
                   let mtime = attrs[.modificationDate] as? Date,
                   mtime < cutoff {
                    if (try? fileManager.removeItem(at: file)) != nil {
                        removed += 1
                    }
                }
            }
        }
        return removed
    }
}
