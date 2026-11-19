import Foundation
import SparkleCore

extension HostTrustStore {
    /// Default standard path for user's OpenSSH known hosts file (`~/.ssh/known_hosts`).
    public static var defaultOpenSSHKnownHostsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)
            .appendingPathComponent("known_hosts")
    }

    /// Imports entries from an OpenSSH `known_hosts` file into this trust store.
    /// Returns the number of new host keys successfully imported.
    @discardableResult
    public func importFromOpenSSHKnownHosts(at fileURL: URL = defaultOpenSSHKnownHostsURL) async throws -> Int {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return 0
        }

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let parsed = KnownHostsCodec.parse(contents: contents)
        var importedCount = 0

        for item in parsed {
            // If pattern is a direct host or [host]:port
            let pattern = item.hostPattern
            guard !pattern.hasPrefix("|1|") else { continue } // Hashed cannot be reversed to plaintext host key

            let subPatterns = pattern.split(separator: ",")
            for sub in subPatterns {
                let hostStr = String(sub)
                let (host, port) = parseHostAndPort(hostStr)
                let existingState = await state(forHost: host, port: port)
                if case .unknown = existingState {
                    try await trust(host: host, port: port, fingerprint: item.fingerprintSHA256)
                    importedCount += 1
                }
            }
        }

        return importedCount
    }

    private func parseHostAndPort(_ spec: String) -> (String, Int) {
        if spec.hasPrefix("[") && spec.contains("]:") {
            let parts = spec.dropFirst().components(separatedBy: "]:")
            if parts.count == 2, let port = Int(parts[1]) {
                return (parts[0], port)
            }
        }
        return (spec, 22)
    }
}
