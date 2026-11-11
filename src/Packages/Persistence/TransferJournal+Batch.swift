import Foundation
import SparkleCore
import SQLite3

public extension TransferJournal {
    func upsert(_ record: TransferJournalRecord) async throws {
        try await upsertBatch([record])
    }

    func upsertBatch(_ records: [TransferJournalRecord]) async throws {
        guard !records.isEmpty else { return }
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
        try executePreparedBatch(sql: sql, useTransaction: records.count > 1) { stmt in
            for record in records {
                try bindAndStepUpsert(stmt: stmt, record: record)
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
            }
        }
    }

    func delete(id: UUID) async throws {
        try await deleteBatch(ids: [id])
    }

    func deleteBatch(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let sql = "DELETE FROM transfer_journal WHERE id = ?;"
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        try executePreparedBatch(sql: sql, useTransaction: ids.count > 1) { stmt in
            for id in ids {
                sqlite3_bind_text(stmt, 1, id.uuidString, -1, transient)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw AppError.persistenceFailure(reason: lastErrorMessage())
                }
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
            }
        }
    }

    private func executePreparedBatch(
        sql: String,
        useTransaction: Bool,
        stepBody: (OpaquePointer) throws -> Void
    ) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw AppError.persistenceFailure(reason: lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        if useTransaction {
            try executeSQL("BEGIN IMMEDIATE TRANSACTION;")
        }
        do {
            try stepBody(stmt)
            if useTransaction {
                try executeSQL("COMMIT;")
            }
        } catch {
            if useTransaction {
                try? executeSQL("ROLLBACK;")
            }
            throw error
        }
    }

    private func bindAndStepUpsert(stmt: OpaquePointer, record: TransferJournalRecord) throws {
        let metadataData = try encoder.encode(record.metadata)
        let checkpointData = try record.checkpoint.map { try encoder.encode($0) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, record.id.uuidString, -1, transient)
        _ = metadataData.withUnsafeBytes { rawBuf in
            sqlite3_bind_blob(stmt, 2, rawBuf.baseAddress, Int32(metadataData.count), transient)
        }
        sqlite3_bind_text(stmt, 3, record.statusCode, -1, transient)
        if let errorDescription = record.errorDescription {
            sqlite3_bind_text(stmt, 4, errorDescription, -1, transient)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        if let checkpointData {
            _ = checkpointData.withUnsafeBytes { rawBuf in
                sqlite3_bind_blob(stmt, 5, rawBuf.baseAddress, Int32(checkpointData.count), transient)
            }
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        sqlite3_bind_double(stmt, 6, record.updatedAt.timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw AppError.persistenceFailure(reason: lastErrorMessage())
        }
    }
}
