import Foundation
import SparkleCore

public struct RemoteTransportOptions: Sendable, Equatable {
    public let pipelineDepth: Int
    public let useCompression: Bool

    public init(pipelineDepth: Int = 8, useCompression: Bool = true) {
        self.pipelineDepth = min(16, max(1, pipelineDepth))
        self.useCompression = useCompression
    }
}

/// Factory producing the appropriate protocol adapter (`SFTPService`, `SCPCompatibilityAdapter`, or `FTPService`).
public enum RemoteServiceFactory {
    public static func makeService(
        for profile: ConnectionProfile,
        credentialStore: any CredentialStoreProtocol,
        hostTrustStore: any HostTrustStoreProtocol,
        credentialPrompt: SSHClientService.CredentialPromptHandler? = nil,
        jumpProfileResolver: SSHClientService.JumpProfileResolver? = nil,
        options: RemoteTransportOptions = RemoteTransportOptions(),
        hostTrustPrompt: @escaping SSHClientService.HostTrustPromptHandler
    ) -> (service: RemoteService, sshClient: SSHClientService?) {
        switch profile.protocolType {
        case .sftp:
            let ssh = SSHClientService(
                profile: profile,
                credentialStore: credentialStore,
                hostTrustStore: hostTrustStore,
                hostTrustPrompt: hostTrustPrompt,
                credentialPrompt: credentialPrompt,
                jumpProfileResolver: jumpProfileResolver
            )
            let sftp = SFTPService(
                profile: profile,
                sshClient: ssh,
                pipelineDepth: options.pipelineDepth
            )
            return (RemoteService(connection: sftp, fileSystem: sftp), ssh)

        case .scp:
            let ssh = SSHClientService(
                profile: profile,
                credentialStore: credentialStore,
                hostTrustStore: hostTrustStore,
                hostTrustPrompt: hostTrustPrompt,
                credentialPrompt: credentialPrompt,
                jumpProfileResolver: jumpProfileResolver
            )
            let scp = SCPCompatibilityAdapter(
                profile: profile,
                sshService: ssh,
                useCompression: options.useCompression
            )
            return (RemoteService(connection: scp, fileSystem: scp), ssh)

        case .ftp, .ftpsExplicit, .ftpsImplicit:
            let ftp = FTPService(
                profile: profile,
                credentialStore: credentialStore,
                credentialPrompt: credentialPrompt
            )
            return (RemoteService(connection: ftp, fileSystem: ftp), nil)
        }
    }
}
