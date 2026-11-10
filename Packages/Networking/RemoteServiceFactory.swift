import Foundation
import SparkleCore

/// Factory producing the appropriate protocol adapter (`SFTPService`, `SCPCompatibilityAdapter`, or `FTPService`).
public enum RemoteServiceFactory {
    public static func makeService(
        for profile: ConnectionProfile,
        credentialStore: any CredentialStoreProtocol,
        hostTrustStore: any HostTrustStoreProtocol,
        hostTrustPrompt: @escaping SSHClientService.HostTrustPromptHandler
    ) -> (service: RemoteService, sshClient: SSHClientService?) {
        switch profile.protocolType {
        case .sftp:
            let ssh = SSHClientService(
                profile: profile,
                credentialStore: credentialStore,
                hostTrustStore: hostTrustStore,
                hostTrustPrompt: hostTrustPrompt
            )
            let sftp = SFTPService(profile: profile, sshClient: ssh)
            return (RemoteService(connection: sftp, fileSystem: sftp), ssh)

        case .scp:
            let ssh = SSHClientService(
                profile: profile,
                credentialStore: credentialStore,
                hostTrustStore: hostTrustStore,
                hostTrustPrompt: hostTrustPrompt
            )
            let scp = SCPCompatibilityAdapter(profile: profile, sshService: ssh)
            return (RemoteService(connection: scp, fileSystem: scp), ssh)

        case .ftp, .ftpsExplicit, .ftpsImplicit:
            let ftp = FTPService(profile: profile, credentialStore: credentialStore)
            return (RemoteService(connection: ftp, fileSystem: ftp), nil)
        }
    }
}
