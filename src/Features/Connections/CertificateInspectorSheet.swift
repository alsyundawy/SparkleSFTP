import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// Interactive X.509 Visual Certificate Inspector Sheet (Task 9.1).
public struct CertificateInspectorSheet: View {
    let certificate: TLSCertificateInfo
    @Environment(\.dismiss) private var dismiss

    public init(certificate: TLSCertificateInfo) {
        self.certificate = certificate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            headerSection
            statusSection
            detailsSection
            Spacer(minLength: 0)
            footerSection
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 520, height: 380)
    }

    private var headerSection: some View {
        HStack {
            Label("X.509 Certificate Inspector", systemImage: "lock.shield")
                .font(SparkleTheme.Typography.title)
            Spacer()
            ModalCloseButton { dismiss() }
        }
    }

    private var statusSection: some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            statusBadge
            Spacer()
            Text(certificate.host)
                .font(SparkleTheme.Typography.monoSmall)
                .foregroundStyle(.secondary)
        }
        .padding(SparkleTheme.Spacing.small)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var statusBadge: some View {
        if certificate.isExpired {
            Label("Certificate Expired", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        } else if certificate.isCriticallyExpiring {
            let days = certificate.daysUntilExpiration ?? 0
            Label("Expires in \(days) days", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if certificate.isTrusted {
            Label("Certificate Trusted", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        } else {
            Label("Self-Signed / Untrusted", systemImage: "questionmark.diamond.fill")
                .foregroundStyle(.yellow)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            infoRow(label: "Subject:", value: certificate.subject)
            infoRow(label: "Issuer:", value: certificate.issuer)
            if let from = certificate.validFrom, let until = certificate.validUntil {
                infoRow(label: "Validity:", value: "\(formattedDate(from)) — \(formattedDate(until))")
            }
            fingerprintRow
        }
        .padding(SparkleTheme.Spacing.small)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var fingerprintRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("SHA-256 Fingerprint:")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(certificate.sha256Fingerprint, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(SparkleTheme.Typography.caption)
                }
                .buttonStyle(.borderless)
            }
            Text(certificate.sha256Fingerprint.isEmpty ? "None" : certificate.sha256Fingerprint)
                .font(SparkleTheme.Typography.monoSmall)
                .textSelection(.enabled)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(SparkleTheme.Typography.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private var footerSection: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
