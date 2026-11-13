import Clibcurl
import Foundation
import SparkleCore

public enum CompressionFormat: Sendable {
    case zlib
    case gzip
}

public struct Libssh2ProbeResult: Sendable, Equatable {
    public let isAvailable: Bool
    public let version: String
    public let path: String

    public init(isAvailable: Bool, version: String, path: String) {
        self.isAvailable = isAvailable
        self.version = version
        self.path = path
    }
}

private struct ToolchainProbeContext {
    let curlInfo: String
    let zlibVer: String
    let libssh2: Libssh2ProbeResult
    let sshURL: URL?
    let sshVer: String?
    let sslURL: URL?
    let sslVer: String?
    let shells: [String]
    let itermURL: URL?
    let terminalURL: URL?
}

private func decodeCString(_ buffer: [CChar]) -> String {
    let length = buffer.firstIndex(of: 0) ?? buffer.count
    let bytes = buffer.prefix(length).map { UInt8(bitPattern: $0) }
    return String(bytes: bytes, encoding: .utf8) ?? ""
}

/// Bounded streaming wrapper over macOS SDK `zlib` (`-lz`) protecting against zip-bomb allocations (`CWE-409`).
public enum ZlibCompressionCodec {
    public static let defaultMaxDecompressedBytes: Int = 64 * 1024 * 1024

    public static var libraryVersion: String {
        var buffer = [CChar](repeating: 0, count: 64)
        sparklesftp_zlib_version(&buffer, buffer.count)
        return decodeCString(buffer)
    }

    public static func compress(
        _ data: Data,
        level: Int32 = 6,
        format: CompressionFormat = .zlib
    ) throws -> Data {
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let useGzip: Int32 = format == .gzip ? 1 : 0
        let status: Int32 = data.withUnsafeBytes { rawBuffer in
            let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            return sparklesftp_zlib_deflate(base, data.count, level, useGzip, &outPtr, &outLen)
        }
        guard status == 0, let ptr = outPtr else {
            throw AppError.transferFailed(reason: "zlib compression failed (\(status))")
        }
        defer { sparklesftp_zlib_free(ptr) }
        return Data(bytes: ptr, count: outLen)
    }

    public static func decompress(
        _ data: Data,
        maxOutputBytes: Int = defaultMaxDecompressedBytes
    ) throws -> Data {
        guard !data.isEmpty, maxOutputBytes > 0 else {
            throw AppError.transferFailed(reason: "Invalid compressed payload")
        }
        var outPtr: UnsafeMutablePointer<UInt8>?
        var outLen = 0
        let status: Int32 = data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return sparklesftp_zlib_inflate(base, data.count, maxOutputBytes, &outPtr, &outLen)
        }
        guard status == 0, let ptr = outPtr else {
            let reason = status == -5
                ? "Compressed payload exceeds safety cap (\(maxOutputBytes) bytes)"
                : "zlib decompression failed (\(status))"
            throw AppError.transferFailed(reason: reason)
        }
        defer { sparklesftp_zlib_free(ptr) }
        return Data(bytes: ptr, count: outLen)
    }
}

/// Inspects linked and dynamically discovered third-party libraries, CLI tools, shells, and terminal apps.
public enum ToolchainInspector {
    public static func curlVersionSummary() -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        sparklesftp_curl_version_summary(&buffer, buffer.count)
        return decodeCString(buffer)
    }

    public static func probeLibssh2() -> Libssh2ProbeResult {
        var versionBuf = [CChar](repeating: 0, count: 64)
        var pathBuf = [CChar](repeating: 0, count: 256)
        let found = sparklesftp_probe_libssh2(&versionBuf, versionBuf.count, &pathBuf, pathBuf.count)
        let ver = decodeCString(versionBuf)
        let path = decodeCString(pathBuf)
        return Libssh2ProbeResult(
            isAvailable: found == 1,
            version: ver.isEmpty ? "Not loaded" : ver,
            path: path
        )
    }

    public static func detectAvailableShells() -> [String] {
        var candidates = [
            "/usr/local/bin/bash",
            "/opt/homebrew/bin/bash",
            "/bin/zsh",
            "/opt/homebrew/bin/fish",
            "/usr/local/bin/fish",
            "/bin/bash"
        ]
        if let envShell = ProcessInfo.processInfo.environment["SHELL"], !envShell.isEmpty {
            candidates.insert(envShell, at: 0)
        }
        var seen: Set<String> = []
        return candidates.filter { path in
            guard FileManager.default.isExecutableFile(atPath: path) else { return false }
            return seen.insert(path).inserted
        }
    }

    public static func firstExecutable(in paths: [String]) -> URL? {
        for path in paths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    public static func firstAppBundle(in paths: [String]) -> URL? {
        for path in paths where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    public static func inspectHostToolchain(runSubprocesses: Bool = true) async -> HostToolchainReport {
        if !runSubprocesses {
            return buildStaticReport(openSSHVer: nil, openSSLVer: nil)
        }
        return await Task.detached(priority: .utility) {
            let sshURL = firstExecutable(in: [
                "/opt/homebrew/bin/ssh", "/usr/local/bin/ssh", "/usr/bin/ssh"
            ])
            let sslURL = firstExecutable(in: [
                "/opt/homebrew/opt/openssl@3/bin/openssl",
                "/usr/local/opt/openssl@3/bin/openssl",
                "/usr/bin/openssl"
            ])
            let sshVer = sshURL.flatMap { runVersionProbe(executable: $0, args: ["-V"]) }
            let sslVer = sslURL.flatMap { runVersionProbe(executable: $0, args: ["version"]) }
            return buildStaticReport(openSSHVer: sshVer, openSSLVer: sslVer, sshURL: sshURL, sslURL: sslURL)
        }.value
    }

    private static func buildStaticReport(
        openSSHVer: String?,
        openSSLVer: String?,
        sshURL: URL? = nil,
        sslURL: URL? = nil
    ) -> HostToolchainReport {
        let shells = detectAvailableShells()
        let iterm = firstAppBundle(in: ["/Applications/iTerm.app", "/Applications/Utilities/iTerm.app"])
        let term = firstAppBundle(in: [
            "/System/Applications/Utilities/Terminal.app",
            "/Applications/Utilities/Terminal.app"
        ])
        let resolvedSSH = sshURL ?? firstExecutable(in: [
            "/opt/homebrew/bin/ssh", "/usr/local/bin/ssh", "/usr/bin/ssh"
        ])
        let resolvedSSL = sslURL ?? firstExecutable(in: [
            "/opt/homebrew/opt/openssl@3/bin/openssl",
            "/usr/local/opt/openssl@3/bin/openssl",
            "/usr/bin/openssl"
        ])
        let ctx = ToolchainProbeContext(
            curlInfo: curlVersionSummary(),
            zlibVer: ZlibCompressionCodec.libraryVersion,
            libssh2: probeLibssh2(),
            sshURL: resolvedSSH,
            sshVer: openSSHVer,
            sslURL: resolvedSSL,
            sslVer: openSSLVer,
            shells: shells,
            itermURL: iterm,
            terminalURL: term
        )
        return HostToolchainReport(
            libraries: assembleLibraryStatuses(ctx),
            availableShells: shells,
            iTermAppURL: iterm,
            appleTerminalURL: term,
            openSSHBinaryURL: resolvedSSH,
            openSSLBinaryURL: resolvedSSL
        )
    }

    private static func assembleLibraryStatuses(_ ctx: ToolchainProbeContext) -> [ToolchainLibraryStatus] {
        coreLibraryStatuses(ctx) + systemLibraryStatuses(ctx)
    }

    private static func coreLibraryStatuses(_ ctx: ToolchainProbeContext) -> [ToolchainLibraryStatus] {
        [
            ToolchainLibraryStatus(
                id: "niossh", name: "swift-nio-ssh", category: "SSH / SFTP", version: "0.15.1",
                isAvailable: true, role: "Primary SSH/SFTP engine",
                detail: "Async EventLoop SSH, SFTP v3 pipelining & DirectTCPIP (CVE-2026-43798 patched)"
            ),
            ToolchainLibraryStatus(
                id: "swiftterm", name: "SwiftTerm", category: "Terminal / PTY", version: "1.20.0",
                isAvailable: true, role: "xterm/VT100 PTY & OSC 7 sync",
                detail: "Embedded & standalone iTerm2-style terminal emulator with palette integration"
            ),
            ToolchainLibraryStatus(
                id: "sparkle", name: "Sparkle", category: "Updates", version: "2.10.1",
                isAvailable: true, role: "Automated software updates",
                detail: "Ed25519-signed update delivery & secure appcast validation"
            ),
            ToolchainLibraryStatus(
                id: "sqlite", name: "SQLite3", category: "Persistence", version: "macOS WAL",
                isAvailable: true, role: "ACID crash-safe transfer journal",
                detail: "System SQLite3 WAL engine with automatic pruning and transaction isolation"
            ),
            ToolchainLibraryStatus(
                id: "security", name: "Apple Security & CryptoKit", category: "Security", version: "macOS Native",
                isAvailable: true, role: "Keychain & biometric gating",
                detail: "Hardware Secure Enclave, Touch ID authentication & streaming SHA-256 validation"
            ),
            ToolchainLibraryStatus(
                id: "libcurl", name: "libcurl", category: "FTP / FTPS / TLS",
                version: ctx.curlInfo.isEmpty ? "Linked" : ctx.curlInfo, isAvailable: !ctx.curlInfo.isEmpty,
                role: "Concurrent FTP/FTPS transfer worker engine",
                detail: "256KB TCP keepalive buffers, locked to ftp,ftps (CVE-2025-15224 mitigated)"
            )
        ]
    }

    private static func systemLibraryStatuses(_ ctx: ToolchainProbeContext) -> [ToolchainLibraryStatus] {
        [
            ToolchainLibraryStatus(
                id: "zlib", name: "zlib", category: "Compression", version: ctx.zlibVer,
                isAvailable: !ctx.zlibVer.isEmpty, role: "Streaming deflate/gzip codec (-lz)",
                detail: "Bounded RFC 1950/1952 codec & libcurl compression integration"
            ),
            ToolchainLibraryStatus(
                id: "libssh2", name: "libssh2", category: "SSH Interop", version: ctx.libssh2.version,
                isAvailable: ctx.libssh2.isAvailable, role: "Optional runtime dlopen probe",
                detail: ctx.libssh2.isAvailable
                    ? "Loaded via \(ctx.libssh2.path)"
                    : "Not required (optional Homebrew)"
            ),
            ToolchainLibraryStatus(
                id: "openssl", name: "OpenSSL / LibreSSL", category: "Crypto & CLI",
                version: ctx.sslVer ?? (ctx.sslURL?.path ?? "macOS SecTrust"),
                isAvailable: ctx.sslURL != nil, role: "TLS inspection & key diagnostics",
                detail: ctx.sslURL?.path ?? "SecTrust + CryptoKit native"
            ),
            ToolchainLibraryStatus(
                id: "openssh", name: "OpenSSH", category: "External SSH",
                version: ctx.sshVer ?? (ctx.sshURL?.path ?? "Not found"),
                isAvailable: ctx.sshURL != nil, role: "External iTerm2 / Terminal launcher",
                detail: ctx.sshURL?.path ?? "No ssh CLI executable detected"
            ),
            ToolchainLibraryStatus(
                id: "shell", name: "POSIX Shells", category: "Local Terminal",
                version: ctx.shells.first ?? "None", isAvailable: !ctx.shells.isEmpty,
                role: "LocalProcessTerminalView & external scripts",
                detail: ctx.shells.joined(separator: ", ")
            ),
            ToolchainLibraryStatus(
                id: "iterm", name: "iTerm2 / Terminal", category: "Terminal Apps",
                version: ctx.itermURL != nil ? "iTerm2 + Terminal.app" : "Terminal.app",
                isAvailable: ctx.itermURL != nil || ctx.terminalURL != nil,
                role: "Open remote SSH session in external terminal",
                detail: ctx.itermURL?.path ?? (ctx.terminalURL?.path ?? "Unavailable")
            )
        ]
    }

    private static func runVersionProbe(executable: URL, args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
