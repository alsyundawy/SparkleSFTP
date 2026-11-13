import Foundation

public extension Notification.Name {
    static let sparkleTerminalDirectoryDidChange = Notification.Name("sparkleSFTP.terminalDirectoryDidChange")
}

public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case awaitingHostTrust(HostKeyChallenge)
    case connected(connectedAt: Date)
    case failed(AppError)
}

/// Manages session connection lifecycle and negotiated capabilities (DUP-001).
public protocol RemoteConnection: Sendable {
    var profile: ConnectionProfile { get }
    var capabilities: Set<RemoteCapability> { get async }
    var connectionState: ConnectionState { get async }

    func connect() async throws
    func disconnect(policy: DisconnectPolicy) async throws
}

/// Stateless remote filesystem operations decoupled from TransferEngine (BUG-001, CIRC-001).
public protocol RemoteFileSystem: Sendable {
    func listDirectory(at path: RemotePath) async throws -> [RemoteFile]
    func metadata(at path: RemotePath) async throws -> RemoteFileMetadata
    func resolveSymlink(at path: RemotePath) async throws -> RemotePath
    func download(
        from remotePath: RemotePath,
        to localURL: URL,
        offset: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws
    func upload(
        from localURL: URL,
        to remotePath: RemotePath,
        offset: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws
    func delete(at path: RemotePath, isDirectory: Bool) async throws
    func rename(from source: RemotePath, to destination: RemotePath) async throws
    func createDirectory(at path: RemotePath) async throws
    func setPermissions(_ permissions: UInt32, at path: RemotePath) async throws
    func setModificationTime(_ time: Date, at path: RemotePath) async throws
}

public extension RemoteFileSystem {
    func setModificationTime(_: Date, at _: RemotePath) async throws {
        // Default no-op for remote filesystems that do not implement timestamp mutation
    }

    func download(
        from remotePath: RemotePath,
        to localURL: URL,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        try await download(from: remotePath, to: localURL, offset: 0, onProgress: onProgress)
    }

    func upload(
        from localURL: URL,
        to remotePath: RemotePath,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        try await upload(from: localURL, to: remotePath, offset: 0, onProgress: onProgress)
    }
}

/// Composed service object pairing connection lifecycle with file operations.
public struct RemoteService: Sendable {
    public let connection: any RemoteConnection
    public let fileSystem: any RemoteFileSystem

    public init(connection: any RemoteConnection, fileSystem: any RemoteFileSystem) {
        self.connection = connection
        self.fileSystem = fileSystem
    }
}

/// Abstract secret vault contract implemented by Security.KeychainService.
public protocol CredentialStoreProtocol: Sendable {
    func saveSecret(_ data: Data, for reference: SecretReference, requireTouchID: Bool) async throws
    func loadSecret(for reference: SecretReference, prompt: String?) async throws -> Data
    func deleteSecret(for reference: SecretReference) async throws
    func hasSecret(for reference: SecretReference) async -> Bool
    func evaluateBiometricPolicy(reason: String) async throws
}

public extension CredentialStoreProtocol {
    func evaluateBiometricPolicy(reason _: String) async throws {}
}

/// Host key Trust-On-First-Use (TOFU) verification contract.
public protocol HostTrustStoreProtocol: Sendable {
    func state(forHost host: String, port: Int) async -> HostTrustState
    func evaluate(host: String, port: Int, fingerprint: String) async -> HostTrustState
    func trust(host: String, port: Int, fingerprint: String) async throws
    func reject(host: String, port: Int) async throws
    func clearTrust(host: String, port: Int) async throws
}

public protocol ConnectionStoreProtocol: Sendable {
    func loadProfiles() async throws -> [ConnectionProfile]
    func saveProfile(_ profile: ConnectionProfile) async throws
    func deleteProfile(id: UUID) async throws
    func deleteProfiles(ids: Set<UUID>) async throws
    func loadGroups() async throws -> [ServerGroup]
    func saveGroup(_ group: ServerGroup) async throws
    func deleteGroup(id: UUID) async throws
}

public extension ConnectionStoreProtocol {
    func deleteProfiles(ids: Set<UUID>) async throws {
        for id in ids {
            try await deleteProfile(id: id)
        }
    }
}

public struct TransferJournalRecord: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let metadata: TransferTaskMetadata
    public let statusCode: String
    public let errorDescription: String?
    public let checkpoint: TransferCheckpoint?
    public let updatedAt: Date

    public init(
        id: UUID,
        metadata: TransferTaskMetadata,
        statusCode: String,
        errorDescription: String? = nil,
        checkpoint: TransferCheckpoint? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.metadata = metadata
        self.statusCode = statusCode
        self.errorDescription = errorDescription
        self.checkpoint = checkpoint
        self.updatedAt = updatedAt
    }
}

public protocol TransferJournalProtocol: Sendable {
    func upsert(_ record: TransferJournalRecord) async throws
    func upsertBatch(_ records: [TransferJournalRecord]) async throws
    func fetchAll() async throws -> [TransferJournalRecord]
    func reconcileInterruptedOnLaunch() async throws -> [TransferJournalRecord]
    func pruneOldEntries(maxEntries: Int, maxAgeDays: Int) async throws
    func delete(id: UUID) async throws
    func deleteBatch(ids: [UUID]) async throws
}

public extension TransferJournalProtocol {
    func upsertBatch(_ records: [TransferJournalRecord]) async throws {
        for record in records {
            try await upsert(record)
        }
    }

    func deleteBatch(ids: [UUID]) async throws {
        for id in ids {
            try await delete(id: id)
        }
    }
}
