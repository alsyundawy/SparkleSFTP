import Foundation

/// Runtime feature flags preventing unfinished capabilities from leaking into production defaults (MAINT-003).
public struct FeatureFlags: Sendable, Equatable {
    public let isSyncEnabled: Bool
    public let isSCPFallbackEnabled: Bool
    public let isPortForwardingEnabled: Bool
    public let isTouchIDGateEnabled: Bool

    public init(
        isSyncEnabled: Bool = true,
        isSCPFallbackEnabled: Bool = true,
        isPortForwardingEnabled: Bool = true,
        isTouchIDGateEnabled: Bool = true
    ) {
        self.isSyncEnabled = isSyncEnabled
        self.isSCPFallbackEnabled = isSCPFallbackEnabled
        self.isPortForwardingEnabled = isPortForwardingEnabled
        self.isTouchIDGateEnabled = isTouchIDGateEnabled
    }

    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        func flag(_ key: String, defaultValue: Bool) -> Bool {
            guard let raw = environment[key] else { return defaultValue }
            return raw == "1" || raw.lowercased() == "true"
        }

        return FeatureFlags(
            isSyncEnabled: flag("SPARKLESFTP_SYNC_ENABLED", defaultValue: true),
            isSCPFallbackEnabled: flag("SPARKLESFTP_SCP_ENABLED", defaultValue: true),
            isPortForwardingEnabled: flag("SPARKLESFTP_FORWARDING_ENABLED", defaultValue: true),
            isTouchIDGateEnabled: flag("SPARKLESFTP_TOUCHID_ENABLED", defaultValue: true)
        )
    }
}
