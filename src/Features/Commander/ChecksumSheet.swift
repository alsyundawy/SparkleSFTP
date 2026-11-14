import AppKit
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager
import SwiftUI

public struct ChecksumSheet: View {
    @ObservedObject var appState: AppState
    let fileURL: URL
    let filename: String
    @Environment(\.dismiss) private var dismiss

    @State private var algorithm: ChecksumAlgorithm = .sha256
    @State private var computedDigest: String?
    @State private var isComputing = false
    @State private var expectedDigest: String = ""
    @State private var errorMessage: String?

    public init(appState: AppState, fileURL: URL, filename: String? = nil) {
        self.appState = appState
        self.fileURL = fileURL
        self.filename = filename ?? fileURL.lastPathComponent
    }

    private var strings: AppStrings {
        appState.strings
    }

    private var matchStatus: MatchStatus {
        guard let computed = computedDigest?.lowercased() else { return .none }
        let expected = expectedDigest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !expected.isEmpty else { return .none }
        return computed == expected ? .matches : .mismatch
    }

    private enum MatchStatus {
        case none
        case matches
        case mismatch
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            headerView
            algorithmPickerView
            computedDigestView
            expectedDigestView
            Spacer(minLength: 0)
            footerActionView
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 580, height: 420)
        .sparkleWorkspaceSurface(appState.activePalette)
        .onAppear {
            computeHash()
        }
        .onChange(of: algorithm) { _ in
            computeHash()
        }
    }

    private var headerView: some View {
        HStack {
            Label(strings.t("checksum.title"), systemImage: "number.square")
                .font(SparkleTheme.Typography.title)
            Spacer()
            Button(strings.t("common.close")) {
                dismiss()
            }
        }
    }

    private var algorithmPickerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(filename)
                .font(SparkleTheme.Typography.headline)
                .lineLimit(1)

            Picker(strings.t("checksum.algorithm"), selection: $algorithm) {
                ForEach(ChecksumAlgorithm.allCases) { algo in
                    Text(algo.displayName).tag(algo)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var computedDigestView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(strings.t("checksum.computed"))
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(appState.activePalette.secondaryTextColor)
                Spacer()
                if let computed = computedDigest {
                    Button(strings.t("common.copy")) {
                        copyToClipboard(computed)
                    }
                    .controlSize(.small)
                }
            }

            if isComputing {
                ProgressView()
                    .controlSize(.small)
            } else if let computed = computedDigest {
                Text(computed)
                    .font(SparkleTheme.Typography.mono)
                    .textSelection(.enabled)
                    .padding(SparkleTheme.Spacing.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(appState.activePalette.canvasColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if let errorMessage {
                Text(errorMessage)
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.danger)
            }
        }
    }

    private var expectedDigestView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(strings.t("checksum.expected"))
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(appState.activePalette.secondaryTextColor)
                Spacer()
                matchBadgeView
            }

            TextField(strings.t("checksum.pastePlaceholder"), text: $expectedDigest)
                .textFieldStyle(.roundedBorder)
                .font(SparkleTheme.Typography.mono)
        }
    }

    @ViewBuilder
    private var matchBadgeView: some View {
        switch matchStatus {
        case .none:
            EmptyView()
        case .matches:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text(strings.t("checksum.matches"))
            }
            .font(SparkleTheme.Typography.caption)
            .foregroundStyle(SparkleTheme.Colors.success)
        case .mismatch:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                Text(strings.t("checksum.mismatch"))
            }
            .font(SparkleTheme.Typography.caption)
            .foregroundStyle(SparkleTheme.Colors.danger)
        }
    }

    private var footerActionView: some View {
        HStack {
            Spacer()
            Button(strings.t("common.close"), role: .cancel) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func computeHash() {
        isComputing = true
        errorMessage = nil
        let targetAlgo = algorithm
        let targetURL = fileURL

        Task {
            do {
                let digest = try await ChecksumService.computeDigest(of: targetURL, algorithm: targetAlgo)
                await MainActor.run {
                    computedDigest = digest
                    isComputing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isComputing = false
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
