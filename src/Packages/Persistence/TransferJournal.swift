import Foundation
import SparkleCore
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class SQLiteDatabaseBox: @unchecked Sendable { // JUSTIFICATION: Actor-isolated handle.
    let handle: OpaquePointer

    init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }
}

/// Durable SQLite3 WAL-mode transfer journal with crash reconciliation and bounded retention (ADR-005, SCALE-002).
public actor TransferJournal: TransferJournalProtocol {
    private let dbBox: SQLiteDatabaseBox
    private var database: OpaquePointer {
        dbBox.handle
    }

    private let databaseURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(databaseURL: URL = TransferJournal.defaultDatabaseURL()) throws {
        self.databaseURL = databaseURL
        try Self.ensureParentDirectory(for: databaseURL)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard openResult == SQLITE_OK, let opened = handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 failed"
            if let handle {
                sqlite3_close(handle)
            }
            throw AppError.persistenceFailure(reason: message)
        }
        dbBox = SQLiteDatabaseBox(handle: opened)
        try Self.executeSQL("PRAGMA journal_mode = WAL;", on: opened)
        try Self.executeSQL("PRAGMA synchronous = NORMAL;", on: opened)
        try Self.createSchemaIfNeeded(on: opened)
    }

    public static func defaultDatabaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("SparkleSFTP", isDirectory: true)
            .appendingPathComponent("transfer_journal.sqlite3", isDirectory: false)
    }

    public func upsert(_ record: TransferJournalRecord) async throws {
        let metadataData = try encoder.encode(record.metadata)
        let checkpointData = try record.checkpoint.map { try encoder.encode($0) }

        let sql = """
        INSERT INTO transfer_journal (id, metadata_json, status_code, error_description, checkpoint_json, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            metadata_json = excluded.metadata_json,
            status_code = excluded.status_code,
            error_description = excluded.error_description,
            checkpoint_json = excluded.checkpoint_json,
            updated_at = excluded.updated_at;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw AppError.persistenceFailure(reason: lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, record.id.uuidString, -1, sqliteTransient)
        _ = metadataData.withUnsafeBytes { rawBuf in
            sqlite3_bind_blob(stmt, 2, rawBuf.baseAddress, Int32(metadataData.count), sqliteTransient)
        }
        sqlite3_bind_text(stmt, 3, record.statusCode, -1, sqliteTransient)
        if let errorDescription = record.errorDescription {
            sqlite3_bind_text(stmt, 4, errorDescription, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        if let checkpointData {
            _ = checkpointData.withUnsafeBytes { rawBuf in
                sqlite3_bind_blob(stmt, 5, rawBuf.baseAddress, Int32(checkpointData.count), sqliteTransient)
            }
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        sqlite3_bind_double(stmt, 6, record.updatedAt.timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw AppError.persistenceFailure(reason: lastErrorMessage())
        }
    }

    public func fetchAll() async throws -> [TransferJournalRecord] {
        let sql = """
        SELECT id, metadata_json, status_code, error_description, checkpoint_json, updated_at
        FROM transfer_journal
        ORDER BY updated_at DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw AppError.persistenceFailure(reason: lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        var results: [TransferJournalRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let record = try decodeRow(stmt) {
                results.append(record)
            }
        }
        return results
    }

    public func reconcileInterruptedOnLaunch() async throws -> [TransferJournalRecord] {
        let activeCodes = ["preparing", "connecting", "transferring", "verifying", "finalizing", "queued"]
        let placeholders = activeCodes.map { "'\($0)'" }.joined(separator: ",")
        try executeSQL("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try executeSQL(
                "UPDATE transfer_journal SET status_code = 'interrupted' WHERE status_code IN (\(placeholders));"
            )
            try executeSQL("COMMIT;")
        } catch {
            try? executeSQL("ROLLBACK;")
            throw error
        }
        return try await fetchAll().filter { $0.statusCode == "interrupted" }
    }

    public func pruneOldEntries(maxEntries: Int = 10000, maxAgeDays: Int = 30) async throws {
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86400).timeIntervalSince1970
        let deleteAgeSQL = """
        DELETE FROM transfer_journal
        WHERE updated_at < ? AND status_code IN ('completed', 'cancelled', 'failed');
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, deleteAgeSQL, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw AppError.persistenceFailure(reason: lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, cutoff)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw AppError.persistenceFailure(reason: lastErrorMessage())
        }

        let capSQL = """
        DELETE FROM transfer_journal
        WHERE id IN (
            SELECT id FROM transfer_journal
            WHERE status_code IN ('completed', 'cancelled', 'failed')
            ORDER BY updated_at DESC
            LIMIT -1 OFFSET ?
        );
        """
        var capStmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, capSQL, -1, &capStmt, nil) == SQLITE_OK, let capStmt else {
            throw AppError.persistenceFailure(reason: lastErrorMessage())
        }
        defer { sqlite3_finalize(capStmt) }
        sqlite3_bind_int(capStmt, 1, Int32(max(0, maxEntries)))
        guard sqlite3_step(capStmt) == SQLITE_DONE else {
            throw AppError.persistenceFailure(reason: lastErrorMessage())
        }
    }

    public func delete(id: UUID) async throws {
        let sql = "DELETE FROM transfer_journal WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw AppError.persistenceFailure(reason: lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, sqliteTransient)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw AppError.persistenceFailure(reason: lastErrorMessage())
        }
    }

    private static func createSchemaIfNeeded(on database: OpaquePointer) throws {
        let schemaSQL = """
        CREATE TABLE IF NOT EXISTS transfer_journal (
            id TEXT PRIMARY KEY,
            metadata_json BLOB NOT NULL,
            status_code TEXT NOT NULL,
            error_description TEXT,
            checkpoint_json BLOB,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_transfer_journal_updated ON transfer_journal (updated_at DESC);
        CREATE INDEX IF NOT EXISTS idx_transfer_journal_status ON transfer_journal (status_code);
        PRAGMA user_version = 1;
        """
        try executeSQL(schemaSQL, on: database)
    }

    private func decodeRow(_ stmt: OpaquePointer) throws -> TransferJournalRecord? {
        guard
            let idCStr = sqlite3_column_text(stmt, 0),
            let id = UUID(uuidString: String(cString: idCStr)),
            let metaPtr = sqlite3_column_blob(stmt, 1),
            let statusCStr = sqlite3_column_text(stmt, 2)
        else {
            return nil
        }

        let metaSize = Int(sqlite3_column_bytes(stmt, 1))
        let metaData = Data(bytes: metaPtr, count: metaSize)
        let metadata = try decoder.decode(TransferTaskMetadata.self, from: metaData)
        let statusCode = String(cString: statusCStr)
        let errorDesc = sqlite3_column_text(stmt, 3).map { String(cString: $0) }

        var checkpoint: TransferCheckpoint?
        if let cpPtr = sqlite3_column_blob(stmt, 4) {
            let cpSize = Int(sqlite3_column_bytes(stmt, 4))
            if cpSize > 0 {
                let cpData = Data(bytes: cpPtr, count: cpSize)
                checkpoint = try decoder.decode(TransferCheckpoint.self, from: cpData)
            }
        }
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
        return TransferJournalRecord(
            id: id,
            metadata: metadata,
            statusCode: statusCode,
            errorDescription: errorDesc,
            checkpoint: checkpoint,
            updatedAt: updatedAt
        )
    }

    private func executeSQL(_ sql: String) throws {
        try Self.executeSQL(sql, on: database)
    }

    private static func executeSQL(_ sql: String, on database: OpaquePointer) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, sql, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            if let errMsg {
                sqlite3_free(errMsg)
            }
            throw AppError.persistenceFailure(reason: msg)
        }
    }

    private func lastErrorMessage() -> String {
        String(cString: sqlite3_errmsg(database))
    }

    private static func ensureParentDirectory(for url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
