import Foundation
import LocalAuthentication
import Security
import SparkleCore

/// Thread-safe in-memory cache avoiding repeated non-TouchID Keychain lookups.
private final class KeychainMemoryCache: @unchecked Sendable { // JUSTIFICATION: Protected via NSLock.
    private let lock = NSLock()
    private var entries: [String: Data] = [:]

    func get(_ key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    func set(_ data: Data, for key: String) {
        lock.lock()
        entries[key] = data
        lock.unlock()
    }

    func remove(_ key: String) {
        lock.lock()
        entries.removeValue(forKey: key)
        lock.unlock()
    }

    func purge() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}

/// Native Apple Security.framework Keychain store enforcing device-only isolation (CWE-312 / CWE-522).
public final class KeychainService: CredentialStoreProtocol, Sendable {
    public let serviceIdentifier: String
    private let memoryCache = KeychainMemoryCache()

    public init(serviceIdentifier: String = "com.alsyundawy.SparkleSFTP") {
        self.serviceIdentifier = serviceIdentifier
    }

    public func purgeTransientCache() async {
        memoryCache.purge()
    }

    /// Builds Keychain attributes enforcing local-device-only isolation (no iCloud Keychain sync).
    public func buildAddAttributes(
        data: Data,
        accountKey: String,
        requireTouchID: Bool
    ) throws -> [String: Any] {
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: accountKey,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]

        if requireTouchID {
            var error: Unmanaged<CFError>?
            guard let accessControl = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .userPresence,
                &error
            ) else {
                let message = error?.takeRetainedValue().localizedDescription ?? "Unable to create access control"
                throw AppError.keychainFailure(status: errSecParam, message: message)
            }
            attributes[kSecAttrAccessControl as String] = accessControl
        } else {
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        return attributes
    }

    public func saveSecret(_ data: Data, for reference: SecretReference, requireTouchID: Bool) async throws {
        let attributes = try buildAddAttributes(
            data: data,
            accountKey: reference.accountKey,
            requireTouchID: requireTouchID
        )
        var status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try deleteSync(accountKey: reference.accountKey)
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            DiagnosticsLogger.security.error("Keychain add failed with status \(status, privacy: .public)")
            throw AppError.keychainFailure(status: status, message: Self.errorMessage(for: status))
        }
        if requireTouchID {
            memoryCache.remove(reference.accountKey)
        } else {
            memoryCache.set(data, for: reference.accountKey)
        }
        DiagnosticsLogger.security.info(
            "Stored item \(reference.id.uuidString, privacy: .private) touchID=\(requireTouchID, privacy: .public)"
        )
    }

    public func loadSecret(for reference: SecretReference, prompt: String?) async throws -> Data {
        if prompt == nil, let cached = memoryCache.get(reference.accountKey) {
            return cached
        }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: reference.accountKey,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]

        if let prompt {
            let context = LAContext()
            context.localizedReason = prompt
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            memoryCache.remove(reference.accountKey)
            throw AppError.credentialNotFound(service: reference.accountKey)
        }
        if status == errSecAuthFailed || status == errSecUserCanceled {
            throw AppError.biometricAuthenticationFailed(reason: Self.errorMessage(for: status))
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AppError.keychainFailure(status: status, message: Self.errorMessage(for: status))
        }
        if prompt == nil {
            memoryCache.set(data, for: reference.accountKey)
        }
        return data
    }

    public func deleteSecret(for reference: SecretReference) async throws {
        memoryCache.remove(reference.accountKey)
        try deleteSync(accountKey: reference.accountKey)
    }

    public func hasSecret(for reference: SecretReference) async -> Bool {
        if memoryCache.get(reference.accountKey) != nil {
            return true
        }
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: reference.accountKey,
            kSecReturnAttributes as String: kCFBooleanFalse as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseAuthenticationContext as String: context
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Evaluates Touch ID / local owner authentication explicitly when vault lock is enabled.
    public func evaluateBiometricPolicy(reason: String) async throws {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            throw AppError.biometricAuthenticationFailed(
                reason: authError?.localizedDescription ?? "Device authentication unavailable"
            )
        }
        do {
            let granted = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if !granted {
                throw AppError.biometricAuthenticationFailed(reason: "Authentication denied")
            }
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.biometricAuthenticationFailed(reason: error.localizedDescription)
        }
    }

    private func deleteSync(accountKey: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: accountKey,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.keychainFailure(status: status, message: Self.errorMessage(for: status))
        }
    }

    private static func errorMessage(for status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus(\(status))"
    }
}
