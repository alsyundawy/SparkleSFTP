import Clibcurl
import Foundation
import SparkleCore
import SparkleSecurity

/// FTP / Explicit FTPS / Implicit FTPS engine built over `Clibcurl` + `SecTrust` TLS validation (ADR-001, SEC-001).
/// Strictly locks `CURLOPT_PROTOCOLS_STR` to `"ftp,ftps"` to prevent any `libssh` surface (CVE-2025-15224).
public actor FTPService: RemoteConnection, RemoteFileSystem {
    public typealias CredentialPromptHandler = @Sendable (CredentialPromptRequest) async -> String?

    public nonisolated let profile: ConnectionProfile
    private let credentialStore: any CredentialStoreProtocol
    private let tlsValidator: TLSCertificateValidator
    private let credentialPrompt: CredentialPromptHandler?

    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var lastVerifiedCertificate: TLSCertificateInfo?
    private var cachedPassword: String?

    public init(
        profile: ConnectionProfile,
        credentialStore: any CredentialStoreProtocol,
        tlsValidator: TLSCertificateValidator = TLSCertificateValidator(),
        credentialPrompt: CredentialPromptHandler? = nil
    ) {
        self.profile = profile
        self.credentialStore = credentialStore
        self.tlsValidator = tlsValidator
        self.credentialPrompt = credentialPrompt
    }

    public var capabilities: Set<RemoteCapability> {
        [.resumeTransfers, .atomicRename]
    }

    public func connect() async throws {
        sparklesftp_curl_global_init_once()
        connectionState = .connecting

        if let passwordRef = profile.passwordRef {
            do {
                let data = try await credentialStore.loadSecret(
                    for: passwordRef,
                    prompt: profile.requireTouchID ? "Unlock FTP password for \(profile.name)" : nil
                )
                cachedPassword = String(data: data, encoding: .utf8)
            } catch let appError as AppError {
                if case .credentialNotFound = appError {
                    cachedPassword = nil
                } else {
                    connectionState = .failed(appError)
                    throw appError
                }
            }
        } else if profile.authMethod == .password, let credentialPrompt {
            let req = CredentialPromptRequest(
                host: profile.host,
                port: profile.port,
                username: profile.username,
                authMethod: profile.authMethod,
                promptTitle: "Enter \(profile.protocolType.displayName) password for "
                    + "\(profile.username)@\(profile.host)"
            )
            cachedPassword = await credentialPrompt(req)
        } else {
            cachedPassword = nil
        }

        do {
            if profile.protocolType == .ftpsImplicit {
                lastVerifiedCertificate = try await tlsValidator.preflightVerifyTLS(
                    host: profile.host,
                    port: profile.port
                )
            }
            _ = try await performListing(path: profile.defaultRemotePath, useMLSD: false)
            connectionState = .connected(connectedAt: Date())
        } catch {
            let mapped = (error as? AppError) ?? .transferFailed(reason: error.localizedDescription)
            connectionState = .failed(mapped)
            throw error
        }
    }

    public func disconnect(policy _: DisconnectPolicy) async throws {
        cachedPassword = nil
        connectionState = .disconnected
    }

    public func listDirectory(at path: RemotePath) async throws -> [RemoteFile] {
        do {
            let mlsdOutput = try await performListing(path: path, useMLSD: true)
            return FTPListingParser.parse(listing: mlsdOutput, directory: path)
        } catch let appError as AppError {
            switch appError {
            case .tlsValidationFailed, .authenticationFailed, .connectionTimeout:
                throw appError
            default:
                break
            }
        }

        let listOutput = try await performListing(path: path, useMLSD: false)
        return FTPListingParser.parse(listing: listOutput, directory: path)
    }

    public func metadata(at path: RemotePath) async throws -> RemoteFileMetadata {
        let entries = try await listDirectory(at: path.parent)
        guard let matched = entries.first(where: { $0.name == path.filename }) else {
            throw AppError.fileNotFound(path: path.rawValue)
        }
        return RemoteFileMetadata(
            path: matched.path,
            size: matched.size,
            isDirectory: matched.isDirectory,
            isSymlink: matched.isSymlink,
            permissions: matched.permissions,
            modificationTime: matched.modificationTime
        )
    }

    public func resolveSymlink(at path: RemotePath) async throws -> RemotePath {
        path
    }

    public func download(
        from remotePath: RemotePath,
        to localURL: URL,
        offset: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        let token = CurlCancellationToken()
        let ctx = try makeRequestContext(path: remotePath, trailingSlash: false)
        try await withTaskCancellationHandler {
            try await CurlClientHelper.runOffCooperativePool {
                if offset == 0 || !FileManager.default.fileExists(atPath: localURL.path) {
                    FileManager.default.createFile(atPath: localURL.path, contents: nil)
                }
                let fileHandle = try FileHandle(forUpdating: localURL)
                defer { try? fileHandle.close() }
                try fileHandle.seek(toOffset: UInt64(max(0, offset)))

                let box = CurlTransferBox(
                    cancellationToken: token,
                    writeFileHandle: fileHandle,
                    onProgress: onProgress,
                    resumeOffset: offset
                )
                try withExtendedLifetime(box) {
                    try CurlClientHelper.executeCurl(context: ctx) { handle in
                        if offset > 0 {
                            sparklesftp_curl_setopt_off_t(handle, CURLOPT_RESUME_FROM_LARGE, curl_off_t(offset))
                        }
                        let ptr = Unmanaged.passUnretained(box).toOpaque()
                        sparklesftp_curl_setopt_write_cb(handle, curlWriteToFileCallback, ptr)
                        sparklesftp_curl_setopt_xfer_cb(handle, curlProgressCallback, ptr)
                    }
                    let finalOffset = (try? fileHandle.seekToEnd()).map { Int64($0) } ?? offset
                    if let doneProgress = box.speedMeter.record(
                        absoluteBytes: finalOffset,
                        totalOverride: max(finalOffset, offset),
                        force: true
                    ) {
                        onProgress(doneProgress)
                    }
                }
            }
        } onCancel: {
            token.cancel()
        }
    }

    public func upload(
        from localURL: URL,
        to remotePath: RemotePath,
        offset: Int64,
        onProgress: @escaping @Sendable (TransferProgress) -> Void
    ) async throws {
        let token = CurlCancellationToken()
        let ctx = try makeRequestContext(path: remotePath, trailingSlash: false)
        try await withTaskCancellationHandler {
            try await CurlClientHelper.runOffCooperativePool {
                let attrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
                let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                let fileHandle = try FileHandle(forReadingFrom: localURL)
                defer { try? fileHandle.close() }
                try fileHandle.seek(toOffset: UInt64(max(0, offset)))

                let box = CurlTransferBox(
                    cancellationToken: token,
                    readFileHandle: fileHandle,
                    onProgress: onProgress,
                    resumeOffset: offset,
                    expectedTotalBytes: fileSize
                )
                try withExtendedLifetime(box) {
                    try CurlClientHelper.executeCurl(context: ctx) { handle in
                        sparklesftp_curl_setopt_long(handle, CURLOPT_UPLOAD, 1)
                        let remaining = curl_off_t(max(0, fileSize - offset))
                        sparklesftp_curl_setopt_off_t(handle, CURLOPT_INFILESIZE_LARGE, remaining)
                        if offset > 0 {
                            sparklesftp_curl_setopt_long(handle, CURLOPT_APPEND, 1)
                        }
                        let ptr = Unmanaged.passUnretained(box).toOpaque()
                        sparklesftp_curl_setopt_read_cb(handle, curlReadFromFileCallback, ptr)
                        sparklesftp_curl_setopt_xfer_cb(handle, curlProgressCallback, ptr)
                    }
                }
            }
        } onCancel: {
            token.cancel()
        }
    }

    public func delete(at path: RemotePath, isDirectory: Bool) async throws {
        let safePath = try Self.sanitizeControlPath(path.rawValue)
        let cmd = isDirectory ? "RMD \(safePath)" : "DELE \(safePath)"
        try await executeQuoteCommands([cmd])
    }

    public func rename(from source: RemotePath, to destination: RemotePath) async throws {
        let src = try Self.sanitizeControlPath(source.rawValue)
        let dst = try Self.sanitizeControlPath(destination.rawValue)
        try await executeQuoteCommands(["RNFR \(src)", "RNTO \(dst)"])
    }

    public func createDirectory(at path: RemotePath) async throws {
        let safePath = try Self.sanitizeControlPath(path.rawValue)
        try await executeQuoteCommands(["MKD \(safePath)"])
    }

    public func setPermissions(_ permissions: UInt32, at path: RemotePath) async throws {
        let safePath = try Self.sanitizeControlPath(path.rawValue)
        let octal = String(permissions & 0o7777, radix: 8)
        try await executeQuoteCommands(["SITE CHMOD \(octal) \(safePath)"])
    }

    public static func sanitizeControlPath(_ raw: String) throws -> String {
        let hasControlByte = raw.utf8.contains { $0 == 0 || $0 == 0x0A || $0 == 0x0D }
        guard !hasControlByte else {
            throw AppError.pathTraversal(attempted: raw)
        }
        return raw
    }
}

private extension FTPService {
    func performListing(path: RemotePath, useMLSD: Bool) async throws -> String {
        let ctx = try makeRequestContext(path: path, trailingSlash: true)
        return try await CurlClientHelper.runOffCooperativePool {
            let box = CurlMemoryBox()
            try withExtendedLifetime(box) {
                try CurlClientHelper.executeCurl(context: ctx) { handle in
                    if useMLSD {
                        sparklesftp_curl_setopt_string(handle, CURLOPT_CUSTOMREQUEST, "MLSD")
                    }
                    let ptr = Unmanaged.passUnretained(box).toOpaque()
                    sparklesftp_curl_setopt_write_cb(handle, curlWriteToMemoryCallback, ptr)
                }
            }
            return String(data: box.data, encoding: .utf8) ?? ""
        }
    }

    func executeQuoteCommands(_ commands: [String]) async throws {
        let ctx = try makeRequestContext(path: "/", trailingSlash: true)
        try await CurlClientHelper.runOffCooperativePool {
            try CurlClientHelper.executeCurl(context: ctx, performAutomatically: false) { handle in
                var slist: UnsafeMutablePointer<curl_slist>?
                defer { curl_slist_free_all(slist) }
                for cmd in commands {
                    guard let appended = curl_slist_append(slist, cmd) else {
                        throw AppError.transferFailed(reason: "Failed allocating libcurl FTP command list")
                    }
                    slist = appended
                }
                sparklesftp_curl_setopt_slist(handle, CURLOPT_QUOTE, slist)
                sparklesftp_curl_setopt_long(handle, CURLOPT_NOBODY, 1)
                let perf = curl_easy_perform(handle)
                if perf != CURLE_OK {
                    throw CurlClientHelper.mapCurlError(perf, protocolType: ctx.protocolType)
                }
            }
        }
    }

    func makeRequestContext(path: RemotePath, trailingSlash: Bool) throws -> CurlRequestContext {
        let scheme = profile.protocolType == .ftpsImplicit ? "ftps" : "ftp"
        let encodedPath = path.rawValue
            .split(separator: "/", omittingEmptySubsequences: true)
            .compactMap { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
            .joined(separator: "/")
        let suffix: String = if trailingSlash {
            encodedPath.isEmpty ? "/" : "/\(encodedPath)/"
        } else {
            encodedPath.isEmpty ? "/" : "/\(encodedPath)"
        }
        let formattedHost = try Self.formatURLHost(profile.host)
        return CurlRequestContext(
            urlString: "\(scheme)://\(formattedHost):\(profile.port)\(suffix)",
            protocolType: profile.protocolType,
            username: profile.username,
            password: cachedPassword,
            proxy: profile.proxy
        )
    }

    static func formatURLHost(_ rawHost: String) throws -> String {
        let trimmed = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("@"),
              !trimmed.contains("/"),
              !trimmed.contains("?"),
              !trimmed.contains("#"),
              !trimmed.contains(where: \.isWhitespace) else {
            throw AppError.invalidConfiguration("Invalid FTP hostname")
        }
        if trimmed.contains(":"), !trimmed.hasPrefix("[") {
            return "[\(trimmed)]"
        }
        return trimmed
    }
}
