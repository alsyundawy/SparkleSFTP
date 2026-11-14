import Foundation

/// Opaque UUID reference pointing to a secret stored inside Apple Keychain.
/// Never stores plaintext secret values (CWE-312 / CWE-522).
public struct SecretReference: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let kind: SecretKind

    public enum SecretKind: String, Sendable, Codable {
        case password
        case privateKey
        case keyPassphrase
    }

    public init(id: UUID = UUID(), kind: SecretKind) {
        self.id = id
        self.kind = kind
    }

    public var accountKey: String {
        "\(kind.rawValue):\(id.uuidString)"
    }
}

public enum ProxyKind: String, Sendable, Codable, CaseIterable {
    case none
    case socks5
    case http
}

public struct ProxyConfiguration: Sendable, Codable, Hashable {
    public var kind: ProxyKind
    public var host: String
    public var port: Int

    public init(kind: ProxyKind = .none, host: String = "", port: Int = 1080) {
        self.kind = kind
        self.host = host
        self.port = port
    }
}

public struct ConnectionProfile: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var groupID: UUID?
    public var protocolType: ProtocolType
    public var host: String
    public var port: Int
    public var username: String
    public var authMethod: AuthMethod
    public var passwordRef: SecretReference?
    public var privateKeyRef: SecretReference?
    public var passphraseRef: SecretReference?
    public var privateKeyBookmarkData: Data?
    public var jumpHostProfileID: UUID?
    public var proxy: ProxyConfiguration
    public var defaultRemotePath: RemotePath
    public var defaultLocalPath: String?
    public var isFavorite: Bool
    public var requireTouchID: Bool
    public var lastConnectedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        groupID: UUID? = nil,
        protocolType: ProtocolType = .sftp,
        host: String,
        port: Int? = nil,
        username: String,
        authMethod: AuthMethod = .password,
        passwordRef: SecretReference? = nil,
        privateKeyRef: SecretReference? = nil,
        passphraseRef: SecretReference? = nil,
        privateKeyBookmarkData: Data? = nil,
        jumpHostProfileID: UUID? = nil,
        proxy: ProxyConfiguration = ProxyConfiguration(),
        defaultRemotePath: RemotePath = "/",
        defaultLocalPath: String? = nil,
        isFavorite: Bool = false,
        requireTouchID: Bool = false,
        lastConnectedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.groupID = groupID
        self.protocolType = protocolType
        self.host = host
        self.port = port ?? protocolType.defaultPort
        self.username = username
        self.authMethod = authMethod
        self.passwordRef = passwordRef
        self.privateKeyRef = privateKeyRef
        self.passphraseRef = passphraseRef
        self.privateKeyBookmarkData = privateKeyBookmarkData
        self.jumpHostProfileID = jumpHostProfileID
        self.proxy = proxy
        self.defaultRemotePath = defaultRemotePath
        self.defaultLocalPath = defaultLocalPath
        self.isFavorite = isFavorite
        self.requireTouchID = requireTouchID
        self.lastConnectedAt = lastConnectedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var hasPassword: Bool {
        passwordRef != nil
    }

    public var hasPrivateKey: Bool {
        privateKeyRef != nil
    }

    public var hasPassphrase: Bool {
        passphraseRef != nil
    }

    public func copying(
        id: UUID? = nil,
        name: String? = nil,
        groupID: UUID?? = nil
    ) -> ConnectionProfile {
        let finalGroupID: UUID? = if let explicitGroup = groupID {
            explicitGroup
        } else {
            self.groupID
        }
        return ConnectionProfile(
            id: id ?? self.id,
            name: name ?? self.name,
            groupID: finalGroupID,
            protocolType: protocolType,
            host: host,
            port: port,
            username: username,
            authMethod: authMethod,
            passwordRef: passwordRef,
            privateKeyRef: privateKeyRef,
            passphraseRef: passphraseRef,
            privateKeyBookmarkData: privateKeyBookmarkData,
            jumpHostProfileID: jumpHostProfileID,
            proxy: proxy,
            defaultRemotePath: defaultRemotePath,
            defaultLocalPath: defaultLocalPath,
            isFavorite: isFavorite,
            requireTouchID: requireTouchID,
            lastConnectedAt: lastConnectedAt,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}

public struct ServerGroup: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var sortOrder: Int

    public init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }
}

public struct PortForwardingRule: Identifiable, Sendable, Codable, Hashable {
    public enum Direction: String, Sendable, Codable, CaseIterable {
        case local
        case remote
    }

    public let id: UUID
    public var name: String
    public var direction: Direction
    public var bindHost: String
    public var bindPort: Int
    public var targetHost: String
    public var targetPort: Int
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        direction: Direction = .local,
        bindHost: String = "127.0.0.1",
        bindPort: Int,
        targetHost: String = "127.0.0.1",
        targetPort: Int,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.direction = direction
        self.bindHost = bindHost
        self.bindPort = bindPort
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.isEnabled = isEnabled
    }
}

public struct CommandSnippet: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public var title: String
    public var command: String
    public var category: String

    public init(id: UUID = UUID(), title: String, command: String, category: String = "General") {
        self.id = id
        self.title = title
        self.command = command
        self.category = category
    }
}
