import Foundation
import SparkleCore

/// Atomic versioned JSON store for ConnectionProfile and ServerGroup metadata (ADR-003, ADR-005).
/// Secrets are never stored here; profiles carry only opaque Keychain SecretReference IDs.
public actor ConnectionStore: ConnectionStoreProtocol {
    public struct Snapshot: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public var profiles: [ConnectionProfile]
        public var groups: [ServerGroup]

        public init(schemaVersion: Int = 1, profiles: [ConnectionProfile] = [], groups: [ServerGroup] = []) {
            self.schemaVersion = schemaVersion
            self.profiles = profiles
            self.groups = groups
        }
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cachedSnapshot: Snapshot?

    public init(fileURL: URL = ConnectionStore.defaultStoreURL()) {
        self.fileURL = fileURL
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        decoder = dec
    }

    public static func defaultStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("SparkleSFTP", isDirectory: true)
            .appendingPathComponent("connections.v1.json", isDirectory: false)
    }

    public func loadProfiles() async throws -> [ConnectionProfile] {
        try loadSnapshot().profiles.sorted {
            if $0.isFavorite != $1.isFavorite {
                return $0.isFavorite && !$1.isFavorite
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public func saveProfile(_ profile: ConnectionProfile) async throws {
        var snapshot = try loadSnapshot()
        var updated = profile
        updated.updatedAt = Date()
        if let index = snapshot.profiles.firstIndex(where: { $0.id == profile.id }) {
            snapshot.profiles[index] = updated
        } else {
            snapshot.profiles.append(updated)
        }
        try persist(snapshot)
    }

    public func deleteProfile(id: UUID) async throws {
        var snapshot = try loadSnapshot()
        snapshot.profiles.removeAll { $0.id == id }
        try persist(snapshot)
    }

    public func deleteProfiles(ids: Set<UUID>) async throws {
        guard !ids.isEmpty else { return }
        var snapshot = try loadSnapshot()
        snapshot.profiles.removeAll { ids.contains($0.id) }
        try persist(snapshot)
    }

    public func loadGroups() async throws -> [ServerGroup] {
        try loadSnapshot().groups.sorted { $0.sortOrder < $1.sortOrder }
    }

    public func saveGroup(_ group: ServerGroup) async throws {
        var snapshot = try loadSnapshot()
        if let index = snapshot.groups.firstIndex(where: { $0.id == group.id }) {
            snapshot.groups[index] = group
        } else {
            snapshot.groups.append(group)
        }
        try persist(snapshot)
    }

    public func deleteGroup(id: UUID) async throws {
        var snapshot = try loadSnapshot()
        snapshot.groups.removeAll { $0.id == id }
        for index in snapshot.profiles.indices where snapshot.profiles[index].groupID == id {
            snapshot.profiles[index].groupID = nil
        }
        try persist(snapshot)
    }

    public func searchProfiles(query: String) async throws -> [ConnectionProfile] {
        let profiles = try await loadProfiles()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return profiles }
        return profiles.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.host.localizedCaseInsensitiveContains(trimmed)
                || $0.username.localizedCaseInsensitiveContains(trimmed)
        }
    }

    public func recentProfiles(limit: Int = 10) async throws -> [ConnectionProfile] {
        let profiles = try await loadProfiles()
        return profiles
            .filter { $0.lastConnectedAt != nil }
            .sorted { ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast) }
            .prefix(limit)
            .map(\.self)
    }

    private func loadSnapshot() throws -> Snapshot {
        if let cachedSnapshot {
            return cachedSnapshot
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let empty = Snapshot()
            cachedSnapshot = empty
            return empty
        }
        let data = try Data(contentsOf: fileURL)
        let decoded = try decoder.decode(Snapshot.self, from: data)
        cachedSnapshot = decoded
        return decoded
    }

    private func persist(_ snapshot: Snapshot) throws {
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parentDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        cachedSnapshot = snapshot
    }
}
