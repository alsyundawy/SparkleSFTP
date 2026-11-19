import Foundation
import SparkleCore
import SparkleSecurity
import Testing

@Suite("TLS Certificate Expiration & Health Tests")
struct TLSCertificateExpirationTests {
    @Test("TLSCertificateInfo calculates expiration and warning thresholds correctly")
    func testTLSCertificateInfoExpirationMetrics() {
        let now = Date()
        let daySeconds: TimeInterval = 86400

        let normal = TLSCertificateInfo(
            host: "api.example.com",
            subject: "api.example.com",
            issuer: "Let's Encrypt",
            sha256Fingerprint: "SHA256:abc",
            validFrom: now.addingTimeInterval(-30 * daySeconds),
            validUntil: now.addingTimeInterval(60 * daySeconds),
            isTrusted: true
        )
        #expect(!normal.isExpired)
        #expect(!normal.isExpiringSoon)
        #expect(!normal.isCriticallyExpiring)

        let expiringSoon = TLSCertificateInfo(
            host: "api.example.com",
            subject: "api.example.com",
            issuer: "Let's Encrypt",
            sha256Fingerprint: "SHA256:abc",
            validFrom: now.addingTimeInterval(-60 * daySeconds),
            validUntil: now.addingTimeInterval(20 * daySeconds),
            isTrusted: true
        )
        #expect(!expiringSoon.isExpired)
        #expect(expiringSoon.isExpiringSoon)
        #expect(!expiringSoon.isCriticallyExpiring)

        let critical = TLSCertificateInfo(
            host: "api.example.com",
            subject: "api.example.com",
            issuer: "Let's Encrypt",
            sha256Fingerprint: "SHA256:abc",
            validFrom: now.addingTimeInterval(-80 * daySeconds),
            validUntil: now.addingTimeInterval(5 * daySeconds),
            isTrusted: true
        )
        #expect(!critical.isExpired)
        #expect(critical.isExpiringSoon)
        #expect(critical.isCriticallyExpiring)

        let expired = TLSCertificateInfo(
            host: "api.example.com",
            subject: "api.example.com",
            issuer: "Let's Encrypt",
            sha256Fingerprint: "SHA256:abc",
            validFrom: now.addingTimeInterval(-90 * daySeconds),
            validUntil: now.addingTimeInterval(-2 * daySeconds),
            isTrusted: true
        )
        #expect(expired.isExpired)
    }
}
