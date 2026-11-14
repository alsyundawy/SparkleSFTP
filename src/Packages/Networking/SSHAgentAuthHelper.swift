import Foundation

/// Helper evaluating OpenSSH agent (`SSH_AUTH_SOCK`) availability on the local machine.
public enum SSHAgentAuthHelper {
    public static let envVarName = "SSH_AUTH_SOCK"

    /// Checks if a valid `SSH_AUTH_SOCK` Unix domain socket is active and accessible.
    public static var isAgentAvailable: Bool {
        guard let sockPath = ProcessInfo.processInfo.environment[envVarName], !sockPath.isEmpty else {
            return false
        }
        var statBuf = stat()
        guard stat(sockPath, &statBuf) == 0 else {
            return false
        }
        // S_IFSOCK: Verify it is a Unix domain socket
        return (statBuf.st_mode & S_IFMT) == S_IFSOCK
    }

    /// Returns the active socket path if available.
    public static var socketPath: String? {
        guard isAgentAvailable else { return nil }
        return ProcessInfo.processInfo.environment[envVarName]
    }
}
