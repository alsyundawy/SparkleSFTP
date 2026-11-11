import AppKit
import Foundation
import SparkleCore
import SwiftTerm
import SwiftUI

/// Launches local interactive login shells inside `SwiftTerm.LocalProcessTerminalView` with live theme sync.
public struct LocalShellTerminalRepresentable: NSViewRepresentable {
    public let session: TerminalTabSession
    public let themeColors: TerminalThemeColors?

    public init(session: TerminalTabSession, themeColors: TerminalThemeColors? = nil) {
        self.session = session
        self.themeColors = themeColors
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        TerminalThemeColors.apply(themeColors, to: view)
        context.coordinator.cachedThemeColors = themeColors
        view.optionAsMetaKey = true
        view.allowMouseReporting = true
        view.processDelegate = context.coordinator

        let shellPath = resolveShellExecutable(session.localShellPath)
        let shellName = "-\(URL(fileURLWithPath: shellPath).lastPathComponent)"
        let workingDir = session.localWorkingDirectory?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        view.startProcess(
            executable: shellPath,
            args: ["-l"],
            execName: shellName,
            currentDirectory: workingDir
        )
        session.attachLocalProcessView(view)
        return view
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        if nsView.processDelegate !== context.coordinator {
            nsView.processDelegate = context.coordinator
        }
        if context.coordinator.cachedThemeColors != themeColors {
            context.coordinator.cachedThemeColors = themeColors
            TerminalThemeColors.apply(themeColors, to: nsView)
        }
    }

    public static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        nsView.processDelegate = nil
        nsView.terminate()
        coordinator.teardown()
    }

    private func resolveShellExecutable(_ requested: String?) -> String {
        if let requested, FileManager.default.isExecutableFile(atPath: requested) {
            return requested
        }
        let defaults = ["/usr/local/bin/bash", "/opt/homebrew/bin/bash", "/bin/zsh", "/bin/bash"]
        return defaults.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/bin/zsh"
    }

    @MainActor
    public final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private weak var session: TerminalTabSession?
        var cachedThemeColors: TerminalThemeColors?

        init(session: TerminalTabSession) {
            self.session = session
        }

        func teardown() {
            session = nil
        }

        private nonisolated func runOnMain(_ work: @MainActor @escaping (Coordinator) -> Void) {
            if Thread.isMainThread {
                MainActor.assumeIsolated { work(self) }
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    MainActor.assumeIsolated { work(self) }
                }
            }
        }

        public nonisolated func sizeChanged(source _: LocalProcessTerminalView, newCols _: Int, newRows _: Int) {}

        public nonisolated func setTerminalTitle(source _: LocalProcessTerminalView, title: String) {
            runOnMain { coordinator in
                coordinator.session?.updateTitle(title)
            }
        }

        public nonisolated func hostCurrentDirectoryUpdate(source _: TerminalView, directory: String?) {
            runOnMain { coordinator in
                coordinator.session?.updateRemoteWorkingDirectory(directory)
            }
        }

        public nonisolated func processTerminated(source _: TerminalView, exitCode _: Int32?) {
            runOnMain { coordinator in
                coordinator.session?.isActive = false
            }
        }
    }
}

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

    public static func buildOpenSSHCommandParts(
        for profile: ConnectionProfile,
        jumpProfile: ConnectionProfile? = nil,
        sshBinaryPath: String? = nil
    ) throws -> [String] {
        let sshExe = sshBinaryPath ?? "/usr/bin/ssh"
        let safeUser = try validateNoControlCharacters(profile.username)
        let safeHost = try validateNoControlCharacters(profile.host)
        var args = [sshExe, "-p", "\(profile.port)", "-o", "ServerAliveInterval=30"]
        if let jumpProfile {
            let jumpUser = try validateNoControlCharacters(jumpProfile.username)
            let jumpHost = try validateNoControlCharacters(jumpProfile.host)
            args += ["-J", "\(jumpUser)@\(jumpHost):\(jumpProfile.port)"]
        }
        args.append("\(safeUser)@\(safeHost)")
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
        case .auto:
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
