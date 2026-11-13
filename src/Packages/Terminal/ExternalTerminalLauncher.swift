import AppKit
import Foundation
import SparkleCore

/// Opens sanitized OpenSSH sessions inside external terminals (iTerm2 or Apple Terminal.app).
public enum ExternalTerminalLauncher {
    public static func validateNoControlCharacters(_ raw: String) throws -> String {
        let invalid = raw.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
        guard !invalid, !raw.isEmpty else {
            throw AppError.invalidConfiguration("Unsupported control character in SSH target")
        }
        return raw
    }

    public static func escapePOSIXSingleQuoted(_ raw: String) throws -> String {
        _ = try validateNoControlCharacters(raw)
        let escaped = raw.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    public static func buildSSHURL(for profile: ConnectionProfile) throws -> URL {
        let safeUser = try validateNoControlCharacters(profile.username)
        let safeHost = try validateNoControlCharacters(profile.host)
        var components = URLComponents()
        components.scheme = "ssh"
        components.user = safeUser
        components.host = safeHost
        components.port = profile.port
        guard let url = components.url else {
            throw AppError.invalidConfiguration("Invalid SSH destination URI")
        }
        return url
    }

    public static func validateNoLeadingHyphen(_ raw: String, field: String) throws -> String {
        let safe = try validateNoControlCharacters(raw)
        guard !safe.hasPrefix("-") else {
            throw AppError.invalidConfiguration("Unsupported leading hyphen in SSH \(field)")
        }
        return safe
    }

    public static func buildOpenSSHCommandParts(
        for profile: ConnectionProfile,
        jumpProfile: ConnectionProfile? = nil,
        sshBinaryPath: String? = nil
    ) throws -> [String] {
        let sshExe = sshBinaryPath ?? "/usr/bin/ssh"
        let safeUser = try validateNoLeadingHyphen(profile.username, field: "username")
        let safeHost = try validateNoLeadingHyphen(profile.host, field: "host")
        var args = [sshExe, "-p", "\(profile.port)", "-o", "ServerAliveInterval=30"]
        if let jumpProfile {
            let jumpUser = try validateNoLeadingHyphen(jumpProfile.username, field: "jump username")
            let jumpHost = try validateNoLeadingHyphen(jumpProfile.host, field: "jump host")
            args += ["-J", "\(jumpUser)@\(jumpHost):\(jumpProfile.port)"]
        }
        args += ["--", "\(safeUser)@\(safeHost)"]
        return args
    }

    @MainActor
    public static func launchSession(
        for profile: ConnectionProfile,
        preferredApp: ExternalTerminalApp,
        report: HostToolchainReport,
        jumpProfile: ConnectionProfile? = nil
    ) async throws -> String {
        let targetAppURL = resolveTargetAppURL(preferredApp: preferredApp, report: report)
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

        guard !isSandboxed, let appURL = targetAppURL else {
            let sshURL = try buildSSHURL(for: profile)
            if let targetAppURL {
                try await NSWorkspace.shared.open(
                    [sshURL],
                    withApplicationAt: targetAppURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
                return targetAppURL.deletingPathExtension().lastPathComponent
            }
            guard NSWorkspace.shared.open(sshURL) else {
                throw AppError.transferFailed(reason: "Unable to open external SSH URL")
            }
            return "External SSH"
        }

        let commandParts = try buildOpenSSHCommandParts(
            for: profile,
            jumpProfile: jumpProfile,
            sshBinaryPath: report.openSSHBinaryURL?.path
        )
        let quotedCmd = try commandParts.map { try escapePOSIXSingleQuoted($0) }.joined(separator: " ")
        let launcherURL = try createLauncherScript(commandLine: quotedCmd)
        try await NSWorkspace.shared.open(
            [launcherURL],
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
        return appURL.deletingPathExtension().lastPathComponent
    }

    private static func resolveTargetAppURL(
        preferredApp: ExternalTerminalApp,
        report: HostToolchainReport
    ) -> URL? {
        switch preferredApp {
        case .auto, .internalTerminal:
            return report.iTermAppURL ?? report.appleTerminalURL
        case .iTerm2:
            return report.iTermAppURL ?? report.appleTerminalURL
        case .appleTerminal:
            return report.appleTerminalURL ?? report.iTermAppURL
        }
    }

    private static func createLauncherScript(commandLine: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleSSH-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let scriptURL = tempDir.appendingPathComponent("connect-openssh.command")
        let script = try """
        #!/usr/bin/env bash
        clear
        rm -rf -- \(escapePOSIXSingleQuoted(tempDir.path))
        exec \(commandLine)
        """
        try Data(script.utf8).write(to: scriptURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return scriptURL
    }
}
