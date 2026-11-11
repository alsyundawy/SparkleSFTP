import Foundation
import LocalAuthentication
import Security
import SparkleCore

/// Native Apple Security.framework Keychain store enforcing device-only isolation (CWE-312 / CWE-522).
public final class KeychainService: CredentialStoreProtocol, Sendable {
    public let serviceIdentifier: String

    public init(serviceIdentifier: String = "com.alsyundawy.SparkleSFTP") {
        self.serviceIdentifier = serviceIdentifier
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
        try deleteSync(accountKey: reference.accountKey)
        let attributes = try buildAddAttributes(
            data: data,
            accountKey: reference.accountKey,
            requireTouchID: requireTouchID
        )
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            DiagnosticsLogger.security.error("Keychain add failed with status \(status, privacy: .public)")
            throw AppError.keychainFailure(status: status, message: Self.errorMessage(for: status))
        }
        DiagnosticsLogger.security.info(
            "Stored item \(reference.id.uuidString, privacy: .private) touchID=\(requireTouchID, privacy: .public)"
        )
    }

    public func loadSecret(for reference: SecretReference, prompt: String?) async throws -> Data {
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
            throw AppError.credentialNotFound(service: reference.accountKey)
        }
        if status == errSecAuthFailed || status == errSecUserCanceled {
            throw AppError.biometricAuthenticationFailed(reason: Self.errorMessage(for: status))
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AppError.keychainFailure(status: status, message: Self.errorMessage(for: status))
        }
        return data
    }

    public func deleteSecret(for reference: SecretReference) async throws {
        try deleteSync(accountKey: reference.accountKey)
    }

    public func hasSecret(for reference: SecretReference) async -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: reference.accountKey,
            kSecReturnAttributes as String: kCFBooleanFalse as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
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
