import Crypto
import Foundation
import Network
import Security
import SparkleCore

/// Explicit SecTrust SSL + OCSP revocation validator and Network.framework TLS preflight inspector (CWE-295).
public struct TLSCertificateValidator: Sendable {
    public init() {}

    /// Evaluates a SecTrust chain enforcing hostname verification and OCSP revocation.
    public func validateServerCertificate(_ trust: SecTrust, host: String) throws -> TLSCertificateInfo {
        var policies: [SecPolicy] = [SecPolicyCreateSSL(true, host as CFString)]
        if let revocation = SecPolicyCreateRevocation(kSecRevocationOCSPMethod) {
            policies.append(revocation)
        }
        let policyStatus = SecTrustSetPolicies(trust, policies as CFArray)
        guard policyStatus == errSecSuccess else {
            throw AppError.tlsValidationFailed(reason: "Failed applying SSL policies (\(policyStatus))")
        }

        var cfError: CFError?
        let isValid = SecTrustEvaluateWithError(trust, &cfError)
        let info = Self.extractCertificateInfo(from: trust, host: host, isTrusted: isValid)
        guard isValid else {
            let reason = cfError.map { CFErrorCopyDescription($0) as String } ?? "Certificate untrusted"
            DiagnosticsLogger.security.error(
                "TLS verification failed for \(host, privacy: .private): \(reason, privacy: .public)"
            )
            throw AppError.tlsValidationFailed(reason: reason)
        }

        return info
    }

    /// Performs an explicit TLS handshake to inspect and validate the peer certificate via SecTrust before FTPS I/O.
    public func preflightVerifyTLS(
        host: String,
        port: Int,
        timeoutSeconds: Int = 10
    ) async throws -> TLSCertificateInfo {
        let box = TLSHandshakeBox()
        let tlsOptions = makeTLSOptions(host: host, box: box)
        let parameters = NWParameters(tls: tlsOptions)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            throw AppError.invalidConfiguration("Invalid TLS port \(port)")
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        return try await awaitTLSConnection(connection, host: host, timeoutSeconds: timeoutSeconds, box: box)
    }

    private func makeTLSOptions(host: String, box: TLSHandshakeBox) -> NWProtocolTLS.Options {
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
        let validator = self

        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, secTrust, completion in
                let trust = sec_trust_copy_ref(secTrust).takeRetainedValue()
                do {
                    let info = try validator.validateServerCertificate(trust, host: host)
                    box.setInfo(info)
                    completion(true)
                } catch {
                    completion(false)
                }
            },
            DispatchQueue(label: "com.alsyundawy.SparkleSFTP.tls.verify")
        )
        return tlsOptions
    }

    private func awaitTLSConnection(
        _ connection: NWConnection,
        host: String,
        timeoutSeconds: Int,
        box: TLSHandshakeBox
    ) async throws -> TLSCertificateInfo {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "com.alsyundawy.SparkleSFTP.tls.preflight")
            queue.asyncAfter(deadline: .now() + .seconds(timeoutSeconds)) {
                if box.claimResume() {
                    connection.cancel()
                    continuation.resume(throwing: AppError.connectionTimeout(host: host, seconds: timeoutSeconds))
                }
            }

            connection.stateUpdateHandler = { state in
                Self.handleConnectionState(state, connection: connection, box: box, continuation: continuation)
            }
            connection.start(queue: queue)
        }
    }

    private static func handleConnectionState(
        _ state: NWConnection.State,
        connection: NWConnection,
        box: TLSHandshakeBox,
        continuation: CheckedContinuation<TLSCertificateInfo, Error>
    ) {
        switch state {
        case .ready:
            if box.claimResume() {
                connection.cancel()
                if let info = box.getInfo() {
                    continuation.resume(returning: info)
                } else {
                    let err = AppError.tlsValidationFailed(reason: "Missing certificate metadata")
                    continuation.resume(throwing: err)
                }
            }
        case .failed(let nwError):
            if box.claimResume() {
                connection.cancel()
                continuation.resume(throwing: AppError.tlsValidationFailed(reason: nwError.localizedDescription))
            }
        case .cancelled:
            if box.claimResume() {
                continuation.resume(throwing: AppError.tlsValidationFailed(reason: "TLS preflight cancelled"))
            }
        default:
            break
        }
    }

    public static func extractCertificateInfo(
        from trust: SecTrust,
        host: String,
        isTrusted: Bool
    ) -> TLSCertificateInfo {
        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        guard let leaf = chain.first else {
            return TLSCertificateInfo(
                host: host,
                subject: host,
                issuer: "Unknown",
                sha256Fingerprint: "",
                validFrom: nil,
                validUntil: nil,
                isTrusted: isTrusted
            )
        }

        let subject = (SecCertificateCopySubjectSummary(leaf) as String?) ?? host
        let issuer = chain.dropFirst().first.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? subject
        let derData = SecCertificateCopyData(leaf) as Data
        let digest = SHA256.hash(data: derData)
        let fingerprint = digest.map { String(format: "%02X", $0) }.joined(separator: ":")

        return TLSCertificateInfo(
            host: host,
            subject: subject,
            issuer: issuer,
            sha256Fingerprint: fingerprint,
            validFrom: nil,
            validUntil: nil,
            isTrusted: isTrusted
        )
    }
}

private final class TLSHandshakeBox: @unchecked Sendable { // JUSTIFICATION: NSLock guards single-shot resume.
    private let lock = NSLock()
    private var info: TLSCertificateInfo?
    private var resumed = false

    func setInfo(_ newValue: TLSCertificateInfo) {
        lock.lock()
        info = newValue
        lock.unlock()
    }

    func getInfo() -> TLSCertificateInfo? {
        lock.lock()
        defer { lock.unlock() }
        return info
    }

    func claimResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}
