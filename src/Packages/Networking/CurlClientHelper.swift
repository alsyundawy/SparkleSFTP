import Clibcurl
import Foundation
import SparkleCore

struct CurlRequestContext: Sendable {
    let urlString: String
    let protocolType: ProtocolType
    let username: String
    let password: String?
    let proxy: ProxyConfiguration
}

enum CurlClientHelper {
    private static let workerQueue = DispatchQueue(
        label: "com.alsyundawy.SparkleSFTP.curl.worker",
        qos: .userInitiated,
        attributes: .concurrent
    )

    static func runOffCooperativePool<T: Sendable>(
        _ operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            workerQueue.async {
                do {
                    try continuation.resume(returning: operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func executeCurl(
        context: CurlRequestContext,
        performAutomatically: Bool = true,
        configure: (UnsafeMutableRawPointer) throws -> Void
    ) throws {
        guard let handle = curl_easy_init() else {
            throw AppError.transferFailed(reason: "Failed initializing libcurl handle")
        }
        defer { curl_easy_cleanup(handle) }

        sparklesftp_curl_setopt_string(handle, CURLOPT_URL, context.urlString)
        sparklesftp_curl_setopt_string(handle, CURLOPT_PROTOCOLS_STR, "ftp,ftps")
        sparklesftp_curl_setopt_string(handle, CURLOPT_USERNAME, context.username)
        if let password = context.password {
            sparklesftp_curl_setopt_string(handle, CURLOPT_PASSWORD, password)
        }
        sparklesftp_curl_setopt_long(handle, CURLOPT_CONNECTTIMEOUT, 20)
        sparklesftp_curl_setopt_long(handle, CURLOPT_LOW_SPEED_LIMIT, 1)
        sparklesftp_curl_setopt_long(handle, CURLOPT_LOW_SPEED_TIME, 30)
        sparklesftp_curl_setopt_long(handle, CURLOPT_TCP_NODELAY, 1)
        sparklesftp_curl_setopt_long(handle, CURLOPT_TCP_KEEPALIVE, 1)
        sparklesftp_curl_setopt_long(handle, CURLOPT_TCP_KEEPIDLE, 30)
        sparklesftp_curl_setopt_long(handle, CURLOPT_TCP_KEEPINTVL, 15)
        sparklesftp_curl_setopt_long(handle, CURLOPT_BUFFERSIZE, 262_144)
        sparklesftp_curl_setopt_long(handle, CURLOPT_UPLOAD_BUFFERSIZE, 262_144)

        if context.proxy.kind != .none, !context.proxy.host.isEmpty {
            let scheme = context.proxy.kind == .socks5 ? "socks5h" : "http"
            let rawHost = context.proxy.host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawHost.contains("@"),
                  !rawHost.contains("/"),
                  !rawHost.contains(where: \.isWhitespace) else {
                throw AppError.invalidConfiguration("Invalid proxy host")
            }
            let formattedHost = (rawHost.contains(":") && !rawHost.hasPrefix("[")) ? "[\(rawHost)]" : rawHost
            let proxyURL = "\(scheme)://\(formattedHost):\(context.proxy.port)"
            sparklesftp_curl_setopt_string(handle, CURLOPT_PROXY, proxyURL)
        }

        if context.protocolType == .ftpsExplicit || context.protocolType == .ftpsImplicit {
            // Mandatory TLS 1.2+ & strict cert verification with ZERO downgrade to plaintext FTP (SEC-001)
            sparklesftp_curl_setopt_long(handle, CURLOPT_USE_SSL, Int(CURLUSESSL_ALL.rawValue))
            sparklesftp_curl_setopt_long(handle, CURLOPT_SSLVERSION, Int(CURL_SSLVERSION_TLSv1_2))
            sparklesftp_curl_setopt_long(handle, CURLOPT_SSL_VERIFYPEER, 1)
            sparklesftp_curl_setopt_long(handle, CURLOPT_SSL_VERIFYHOST, 2)
        }

        try configure(handle)

        if performAutomatically {
            let result = curl_easy_perform(handle)
            if result != CURLE_OK {
                throw mapCurlError(result, protocolType: context.protocolType)
            }
        }
    }

    static func mapCurlError(_ code: CURLcode, protocolType: ProtocolType) -> AppError {
        let message = String(cString: curl_easy_strerror(code))
        switch code {
        case CURLE_PEER_FAILED_VERIFICATION, CURLE_SSL_CONNECT_ERROR, CURLE_SSL_CERTPROBLEM, CURLE_USE_SSL_FAILED:
            return .tlsValidationFailed(reason: message)
        case CURLE_LOGIN_DENIED:
            return .authenticationFailed(method: .password)
        case CURLE_OPERATION_TIMEDOUT:
            return .connectionTimeout(host: protocolType.displayName, seconds: 20)
        default:
            return .transferFailed(reason: "FTP/FTPS error (\(code.rawValue)): \(message)")
        }
    }
}

final class CurlMemoryBox {
    var data = Data()
}

final class CurlCancellationToken:
    @unchecked Sendable { // JUSTIFICATION: NSLock protects single cancellation flag.
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

final class CurlTransferBox {
    let cancellationToken: CurlCancellationToken
    let writeFileHandle: FileHandle?
    let readFileHandle: FileHandle?
    let onProgress: @Sendable (TransferProgress) -> Void
    let resumeOffset: Int64
    let expectedTotalBytes: Int64
    let speedMeter: TransferSpeedMeter

    init(
        cancellationToken: CurlCancellationToken,
        writeFileHandle: FileHandle? = nil,
        readFileHandle: FileHandle? = nil,
        onProgress: @escaping @Sendable (TransferProgress) -> Void,
        resumeOffset: Int64,
        expectedTotalBytes: Int64 = 0
    ) {
        self.cancellationToken = cancellationToken
        self.writeFileHandle = writeFileHandle
        self.readFileHandle = readFileHandle
        self.onProgress = onProgress
        self.resumeOffset = max(0, resumeOffset)
        self.expectedTotalBytes = max(0, expectedTotalBytes)
        speedMeter = TransferSpeedMeter(totalBytes: expectedTotalBytes, initialOffset: resumeOffset)
    }
}

func curlWriteToMemoryCallback(
    ptr: UnsafeMutablePointer<CChar>?,
    size: Int,
    nmemb: Int,
    userdata: UnsafeMutableRawPointer?
) -> Int {
    guard let ptr, let userdata else { return 0 }
    let (byteCount, overflow) = size.multipliedReportingOverflow(by: nmemb)
    guard !overflow, byteCount >= 0 else { return 0 }
    let box = Unmanaged<CurlMemoryBox>.fromOpaque(userdata).takeUnretainedValue()
    let typedPtr = UnsafeRawPointer(ptr).assumingMemoryBound(to: UInt8.self)
    box.data.append(UnsafeBufferPointer(start: typedPtr, count: byteCount))
    return byteCount
}

func curlWriteToFileCallback(
    ptr: UnsafeMutablePointer<CChar>?,
    size: Int,
    nmemb: Int,
    userdata: UnsafeMutableRawPointer?
) -> Int {
    guard let ptr, let userdata else { return 0 }
    let (byteCount, overflow) = size.multipliedReportingOverflow(by: nmemb)
    guard !overflow, byteCount >= 0 else { return 0 }
    let box = Unmanaged<CurlTransferBox>.fromOpaque(userdata).takeUnretainedValue()
    guard let handle = box.writeFileHandle else { return 0 }
    let chunk = Data(bytes: ptr, count: byteCount)
    do {
        try handle.write(contentsOf: chunk)
        return byteCount
    } catch {
        return 0
    }
}

func curlReadFromFileCallback(
    buffer: UnsafeMutablePointer<CChar>?,
    size: Int,
    nitems: Int,
    userdata: UnsafeMutableRawPointer?
) -> Int {
    guard let buffer, let userdata else { return 0 }
    let (maxBytes, overflow) = size.multipliedReportingOverflow(by: nitems)
    guard !overflow, maxBytes > 0 else { return 0 }
    let box = Unmanaged<CurlTransferBox>.fromOpaque(userdata).takeUnretainedValue()
    guard let handle = box.readFileHandle else { return 0 }
    do {
        let data = try handle.read(upToCount: maxBytes) ?? Data()
        data.copyBytes(to: UnsafeMutableRawPointer(buffer).assumingMemoryBound(to: UInt8.self), count: data.count)
        return data.count
    } catch {
        return Int(CURL_READFUNC_ABORT)
    }
}

func curlProgressCallback(
    clientp: UnsafeMutableRawPointer?,
    dltotal: curl_off_t,
    dlnow: curl_off_t,
    ultotal: curl_off_t,
    ulnow: curl_off_t
) -> Int32 {
    guard let clientp else { return 0 }
    let box = Unmanaged<CurlTransferBox>.fromOpaque(clientp).takeUnretainedValue()
    if box.cancellationToken.isCancelled {
        return 1
    }
    let activeNow = max(Int64(dlnow), Int64(ulnow))
    let rawTotal = max(Int64(dltotal), Int64(ultotal))
    guard activeNow > 0 || rawTotal > 0 else {
        return 0
    }
    let current = activeNow + box.resumeOffset
    let resolvedTotal: Int64 = if rawTotal > 0 {
        rawTotal + box.resumeOffset
    } else {
        box.expectedTotalBytes
    }
    let forceComplete = resolvedTotal > 0 && current >= resolvedTotal
    if let progress = box.speedMeter.record(
        absoluteBytes: current,
        totalOverride: resolvedTotal > 0 ? resolvedTotal : nil,
        force: forceComplete
    ) {
        box.onProgress(progress)
    }
    return 0
}
