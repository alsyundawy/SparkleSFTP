import Foundation
import Security
import SparkleCore

public protocol HostTrustBackingStore: Sendable {
    func loadTrustBlob() async throws -> Data?
    func saveTrustBlob(_ data: Data) async throws
}

/// Keychain-backed host key trust storage (not UserDefaults) enforcing local device isolation.
public final class KeychainHostTrustBackingStore: HostTrustBackingStore, Sendable {
    private let service: String
    private let account: String

    public init(
        service: String = "com.alsyundawy.SparkleSFTP.hosttrust",
        account: String = "known_hosts_v1"
    ) {
        self.service = service
        self.account = account
    }

    public func loadTrustBlob() async throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AppError.keychainFailure(status: status, message: "Failed reading known hosts")
        }
        return result as? Data
    }

    public func saveTrustBlob(_ data: Data) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        SecItemDelete(query as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppError.keychainFailure(status: status, message: "Failed saving known hosts")
        }
    }
}

/// Complete 6-state TOFU host key trust store (LOG-001).
public actor HostTrustStore: HostTrustStoreProtocol {
    public struct Entry: Codable, Sendable, Equatable {
        public let fingerprint: String
        public let trustedSince: Date
    }

    private let backingStore: any HostTrustBackingStore
    private var entries: [String: Entry] = [:]
    private var pendingDecisions: [String: String] = [:]
    private var rejectedHosts: Set<String> = []
    private var isCorrupted = false
    private var hasLoaded = false

    public init(backingStore: any HostTrustBackingStore = KeychainHostTrustBackingStore()) {
        self.backingStore = backingStore
    }

    public static func hostKey(host: String, port: Int) -> String {
        "\(host.lowercased()):\(port)"
    }

    public func state(forHost host: String, port: Int) async -> HostTrustState {
        await ensureLoaded()
        if isCorrupted {
            return .corrupted
        }
        let key = Self.hostKey(host: host, port: port)
        if rejectedHosts.contains(key) {
            return .rejected
        }
        if let pending = pendingDecisions[key] {
            return .pendingUserDecision(fingerprint: pending)
        }
        if let entry = entries[key] {
            return .trusted(fingerprint: entry.fingerprint, since: entry.trustedSince)
        }
        return .unknown
    }

    public func evaluate(host: String, port: Int, fingerprint: String) async -> HostTrustState {
        await ensureLoaded()
        if isCorrupted {
            return .corrupted
        }
        let key = Self.hostKey(host: host, port: port)

        if let existing = entries[key] {
            if existing.fingerprint == fingerprint {
                rejectedHosts.remove(key)
                pendingDecisions.removeValue(forKey: key)
                return .trusted(fingerprint: existing.fingerprint, since: existing.trustedSince)
            } else {
                DiagnosticsLogger.security.fault(
                    "SSH host key mismatch for \(host, privacy: .private):\(port, privacy: .public)"
                )
                return .mismatch(expected: existing.fingerprint, got: fingerprint)
            }
        }

        if rejectedHosts.contains(key) {
            return .rejected
        }

        pendingDecisions[key] = fingerprint
        return .pendingUserDecision(fingerprint: fingerprint)
    }

    public func trust(host: String, port: Int, fingerprint: String) async throws {
        await ensureLoaded()
        let key = Self.hostKey(host: host, port: port)
        if isCorrupted {
            entries = [:]
            isCorrupted = false
        }
        rejectedHosts.remove(key)
        pendingDecisions.removeValue(forKey: key)
        entries[key] = Entry(fingerprint: fingerprint, trustedSince: Date())
        try await persist()
        DiagnosticsLogger.security.info("Trusted SSH host key for \(host, privacy: .private):\(port, privacy: .public)")
    }

    public func reject(host: String, port: Int) async throws {
        await ensureLoaded()
        let key = Self.hostKey(host: host, port: port)
        pendingDecisions.removeValue(forKey: key)
        rejectedHosts.insert(key)
    }

    public func clearTrust(host: String, port: Int) async throws {
        await ensureLoaded()
        let key = Self.hostKey(host: host, port: port)
        entries.removeValue(forKey: key)
        pendingDecisions.removeValue(forKey: key)
        rejectedHosts.remove(key)
        isCorrupted = false
        try await persist()
    }

    public func allTrustedHosts() async -> [String: Entry] {
        await ensureLoaded()
        return entries
    }

    private func ensureLoaded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        do {
            guard let data = try await backingStore.loadTrustBlob(), !data.isEmpty else {
                entries = [:]
                return
            }
            entries = try JSONDecoder().decode([String: Entry].self, from: data)
        } catch {
            DiagnosticsLogger.security.error(
                "Known-hosts store corrupted: \(error.localizedDescription, privacy: .public)"
            )
            isCorrupted = true
        }
    }

    private func persist() async throws {
        let data = try JSONEncoder().encode(entries)
        try await backingStore.saveTrustBlob(data)
    }
}
