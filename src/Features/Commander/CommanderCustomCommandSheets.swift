import AppKit
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager
import SwiftUI

public struct CopyMoveItemSheet: View {
    let request: CopyMoveRequest
    let hasActiveSession: Bool
    let oppositeDefaultPath: String
    let sameSideDefaultPath: String
    let strings: AppStrings
    let onConfirm: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.sparklePalette) private var palette
    @State private var transferToOppositePane: Bool
    @State private var destinationPath: String

    public init(
        request: CopyMoveRequest,
        hasActiveSession: Bool,
        oppositeDefaultPath: String,
        sameSideDefaultPath: String,
        strings: AppStrings = AppStrings(),
        onConfirm: @escaping (String, Bool) -> Void
    ) {
        self.request = request
        self.hasActiveSession = hasActiveSession
        self.oppositeDefaultPath = oppositeDefaultPath
        self.sameSideDefaultPath = sameSideDefaultPath
        self.strings = strings
        self.onConfirm = onConfirm
        let crossPane = hasActiveSession && !request.isMove
        _transferToOppositePane = State(initialValue: crossPane)
        _destinationPath = State(initialValue: crossPane ? oppositeDefaultPath : sameSideDefaultPath)
    }

    public var body: some View {
        let titleKey = request.isMove ? "pane.moveTitle" : "pane.copyTitle"
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Text(strings.t(titleKey)).font(SparkleTheme.Typography.title)
            Text(summaryLabel)
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)

            if hasActiveSession {
                Toggle(strings.t("pane.targetOppositePane"), isOn: $transferToOppositePane)
                    .onChange(of: transferToOppositePane) { useOpposite in
                        destinationPath = useOpposite ? oppositeDefaultPath : sameSideDefaultPath
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(strings.t("pane.destinationFolder"))
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.secondaryTextColor)
                TextField(strings.t("pane.destinationFolder"), text: $destinationPath)
                    .textFieldStyle(.roundedBorder)
                    .font(SparkleTheme.Typography.monoSmall)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(strings.t("common.cancel"), role: .cancel) { dismiss() }
                Button(strings.t("common.apply")) {
                    onConfirm(destinationPath, transferToOppositePane)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 480, height: 230)
        .sparkleWorkspaceSurface(palette)
    }

    private var summaryLabel: String {
        if request.files.count == 1, let first = request.files.first {
            return first.name
        }
        return "\(request.files.count) \(strings.t("transfers.items"))"
    }
}

public struct ChecksumResultSheet: View {
    let report: FileChecksumReport
    let strings: AppStrings

    @Environment(\.dismiss) private var dismiss
    @Environment(\.sparklePalette) private var palette

    public init(report: FileChecksumReport, strings: AppStrings = AppStrings()) {
        self.report = report
        self.strings = strings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            HStack {
                Label(strings.t("pane.verifyChecksum"), systemImage: "checkmark.seal.fill")
                    .font(SparkleTheme.Typography.title)
                Spacer()
                Button(strings.t("common.close")) { dismiss() }
            }

            Form {
                LabeledContent(strings.t("pane.name"), value: report.filename)
                LabeledContent(strings.t("pane.path"), value: report.path)
                LabeledContent(strings.t("pane.size"), value: "\(report.byteCount) bytes")
                LabeledContent(strings.t("pane.checksumSource"), value: report.sourceNote)
                LabeledContent(strings.t("pane.sha256"), value: report.sha256)
                    .font(SparkleTheme.Typography.monoSmall)
                    .textSelection(.enabled)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(palette.windowColor)

            HStack {
                Spacer()
                Button(strings.t("pane.copyHash")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.sha256, forType: .string)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 520, height: 320)
        .sparkleWorkspaceSurface(palette)
    }
}

public struct FileComparisonSheet: View {
    let report: FileComparisonReport
    let strings: AppStrings

    @Environment(\.dismiss) private var dismiss
    @Environment(\.sparklePalette) private var palette

    public init(report: FileComparisonReport, strings: AppStrings = AppStrings()) {
        self.report = report
        self.strings = strings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            HStack {
                Label("\(strings.t("pane.compareFiles")) — \(report.filename)", systemImage: "square.split.2x1")
                    .font(SparkleTheme.Typography.title)
                Spacer()
                Text(strings.t(report.verdictKey))
                    .font(SparkleTheme.Typography.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(verdictTint.opacity(0.18))
                    .foregroundStyle(verdictTint)
                    .clipShape(Capsule())
                Button(strings.t("common.close")) { dismiss() }
            }

            HStack(alignment: .top, spacing: SparkleTheme.Spacing.medium) {
                comparisonColumn(
                    title: strings.t("sync.sideLocal"),
                    file: report.localItem,
                    sha256: report.localSHA256
                )
                comparisonColumn(
                    title: strings.t("sync.sideRemote"),
                    file: report.remoteItem,
                    sha256: report.remoteSHA256
                )
            }
        }
        .padding()
        .frame(width: 640, height: 320)
        .sparkleWorkspaceSurface(palette)
    }

    private func comparisonColumn(title: String, file: RemoteFile?, sha256: String?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(SparkleTheme.Typography.headline)
                if let file {
                    Text("\(strings.t("pane.path")): \(file.path.rawValue)")
                        .font(SparkleTheme.Typography.monoSmall)
                        .textSelection(.enabled)
                    Text("\(strings.t("pane.size")): \(file.size) bytes")
                        .font(SparkleTheme.Typography.caption)
                    if let mtime = file.modificationTime {
                        Text("\(strings.t("pane.modified")): \(mtime.formatted(date: .abbreviated, time: .standard))")
                            .font(SparkleTheme.Typography.caption)
                    }
                    Text("\(strings.t("pane.sha256")): \(sha256 ?? "--")")
                        .font(SparkleTheme.Typography.monoSmall)
                        .textSelection(.enabled)
                } else {
                    Text(strings.t("compare.notPresent"))
                        .font(SparkleTheme.Typography.caption)
                        .foregroundStyle(palette.secondaryTextColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvasColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.borderColor, lineWidth: 1))
    }

    private var verdictTint: Color {
        switch report.verdictKey {
        case "compare.identical": return SparkleTheme.Colors.encryptedBadge
        case "compare.different": return .orange
        default: return SparkleTheme.Colors.danger
        }
    }
}

public struct CustomSSHCommandSheet: View {
    @ObservedObject var appState: AppState
    let request: CustomCommandRequest

    @Environment(\.dismiss) private var dismiss
    @State private var commandText = "ls -lh {path}"
    @State private var result: CustomCommandResult?
    @State private var errorMessage: String?
    @State private var isRunning = false

    private let presets = [
        "ls -lh {path}",
        "stat {path}",
        "head -n 40 {path}",
        "du -sh {path}",
        "tar -czf {file}.tar.gz {file}"
    ]

    public init(appState: AppState, request: CustomCommandRequest) {
        self.appState = appState
        self.request = request
    }

    public var body: some View {
        let strings = appState.strings
        let palette = appState.activePalette
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            HStack {
                Label(strings.t("pane.executeCustomSSH"), systemImage: "terminal")
                    .font(SparkleTheme.Typography.title)
                Spacer()
                Button(strings.t("common.close")) { dismiss() }
            }

            Text("\(strings.t("pane.placeholdersHint")): {file}, {path}, {dir}")
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)

            presetChips
            commandInputRow(strings: strings)
            outputPanel(strings: strings, palette: palette)
        }
        .padding()
        .frame(width: 620, height: 420)
        .sparkleWorkspaceSurface(palette)
    }

    private var presetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { preset in
                    Button(preset) { commandText = preset }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    private func commandInputRow(strings: AppStrings) -> some View {
        HStack(spacing: 8) {
            TextField(strings.t("pane.customCommandPlaceholder"), text: $commandText)
                .textFieldStyle(.roundedBorder)
                .font(SparkleTheme.Typography.monoSmall)
                .onSubmit { runCommand() }
            Button(strings.t("common.run")) { runCommand() }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func outputPanel(strings: AppStrings, palette: SparkleThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let result {
                Text("\(strings.t("pane.exitCode")): \(result.exitCode)")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(result.exitCode == 0 ? SparkleTheme.Colors.encryptedBadge : .orange)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(SparkleTheme.Colors.danger)
            }
            ScrollView {
                Text(renderedOutput)
                    .font(SparkleTheme.Typography.monoSmall)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(palette.canvasColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.borderColor, lineWidth: 1))
        }
    }

    private var renderedOutput: String {
        guard let result else { return "" }
        if result.stderr.isEmpty {
            return result.stdout
        }
        if result.stdout.isEmpty {
            return result.stderr
        }
        return "\(result.stdout)\n[stderr]\n\(result.stderr)"
    }

    private func runCommand() {
        isRunning = true
        errorMessage = nil
        Task {
            defer { isRunning = false }
            do {
                let output = try await appState.executeCustomRemoteCommand(template: commandText, request: request)
                result = output
                await appState.refreshRemoteDirectory(recordHistory: false)
            } catch {
                errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
