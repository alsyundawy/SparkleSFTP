import SparkleCore
import SparkleDesignSystem
import SparkleTransferEngine
import SwiftUI

private enum ConflictChoiceKind: String, CaseIterable, Identifiable {
    case overwrite
    case overwriteIfNewer
    case overwriteIfDifferentSize
    case overwriteIfDifferentSizeOrNewer
    case resume
    case rename
    case skip

    var id: String {
        rawValue
    }

    var matchingPolicy: TransferConflictPolicy {
        switch self {
        case .overwrite: return .overwrite
        case .overwriteIfNewer: return .overwriteIfNewer
        case .overwriteIfDifferentSize: return .overwriteIfDifferentSize
        case .overwriteIfDifferentSizeOrNewer: return .overwriteIfDifferentSizeOrNewer
        case .resume: return .resume
        case .rename: return .rename
        case .skip: return .skip
        }
    }

    func title(strings: AppStrings) -> String {
        switch self {
        case .overwrite: return strings.t("prefs.conflictOverwrite")
        case .overwriteIfNewer: return strings.t("prefs.conflictOverwriteIfNewer")
        case .overwriteIfDifferentSize: return strings.t("prefs.conflictOverwriteIfDiffSize")
        case .overwriteIfDifferentSizeOrNewer: return strings.t("prefs.conflictOverwriteIfDiffOrNewer")
        case .resume: return strings.t("transfers.resume")
        case .rename: return strings.t("common.rename")
        case .skip: return strings.t("common.skip")
        }
    }
}

/// FileZilla-inspired target-file-exists dialog with comparison cards and queue/direction sticky rules.
public struct ConflictResolutionSheet: View {
    @ObservedObject var appState: AppState
    let conflict: ConflictContext
    @State private var selectedChoice: ConflictChoiceKind = .overwrite
    @State private var customName = ""
    @State private var alwaysApply = false
    @State private var currentDirectionOnly = true

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    public init(appState: AppState, conflict: ConflictContext) {
        self.appState = appState
        self.conflict = conflict
    }

    private var palette: SparkleThemePalette {
        appState.activePalette
    }

    private var strings: AppStrings {
        appState.strings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            headerRow
            comparisonSection
            Divider().overlay(palette.borderColor)
            actionsSection
            Divider().overlay(palette.borderColor)
            scopeCheckboxes
            footerButtons
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 560)
        .sparkleWorkspaceSurface(palette)
        .onAppear {
            let existingName = URL(fileURLWithPath: conflict.destinationDisplayPath).lastPathComponent
            if customName.isEmpty {
                customName = ConflictResolver.uniqueName(from: existingName)
            }
        }
    }

    private var headerRow: some View {
        HStack {
            Label(strings.t("transfers.fileAlreadyExists"), systemImage: "exclamationmark.triangle.fill")
                .font(SparkleTheme.Typography.title)
                .foregroundStyle(palette.primaryTextColor)
            Spacer()
            StatusPill(
                title: conflict.direction == .upload ? "UPLOAD" : "DOWNLOAD",
                systemImage: conflict.direction == .upload ? SparkleTheme.Symbols.upload : SparkleTheme.Symbols
                    .download,
                tint: palette.accentColor
            )
        }
    }

    private var comparisonSection: some View {
        HStack(alignment: .top, spacing: SparkleTheme.Spacing.medium) {
            metadataCard(
                title: strings.t("transfers.sourceFile"),
                path: conflict.sourceDisplayPath.isEmpty
                    ? URL(fileURLWithPath: conflict.destinationDisplayPath).lastPathComponent
                    : conflict.sourceDisplayPath,
                size: conflict.incomingSize,
                modifiedAt: conflict.incomingModifiedAt,
                highlightColor: palette.accentColor
            )
            metadataCard(
                title: strings.t("transfers.targetFile"),
                path: conflict.destinationDisplayPath,
                size: conflict.existingSize,
                modifiedAt: conflict.existingModifiedAt,
                highlightColor: palette.secondaryTextColor
            )
        }
    }

    private func metadataCard(
        title: String,
        path: String,
        size: Int64,
        modifiedAt: Date?,
        highlightColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SparkleTheme.Typography.headline)
                .foregroundStyle(highlightColor)
            Text(path)
                .font(SparkleTheme.Typography.monoSmall)
                .lineLimit(2)
                .truncationMode(.middle)
            Text("\(Self.byteFormatter.string(fromByteCount: size)) (\(size) B)")
                .font(SparkleTheme.Typography.caption)
            if let modifiedAt {
                let formattedDate = modifiedAt.formatted(date: .abbreviated, time: .shortened)
                Text("\(strings.t("transfers.modifiedAt")): \(formattedDate)")
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.secondaryTextColor)
            }
        }
        .padding(SparkleTheme.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.canvasColor)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.borderColor, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(strings.t("transfers.action"))
                .font(SparkleTheme.Typography.headline)

            ForEach(ConflictChoiceKind.allCases) { choice in
                let disabled = choice == .resume && !conflict.supportsResume
                Button {
                    selectedChoice = choice
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selectedChoice == choice ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selectedChoice == choice ? palette.accentColor : palette
                                .secondaryTextColor)
                        Text(choice.title(strings: strings))
                            .font(SparkleTheme.Typography.body)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .opacity(disabled ? 0.45 : 1.0)
            }

            if selectedChoice == .rename {
                TextField(strings.t("transfers.optionalRename"), text: $customName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.leading, 22)
            }
        }
    }

    private var scopeCheckboxes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(strings.t("transfers.alwaysApply"), isOn: $alwaysApply)
            if alwaysApply {
                Toggle(strings.t("transfers.applyCurrentDirectionOnly"), isOn: $currentDirectionOnly)
                    .padding(.leading, 18)
                    .foregroundStyle(palette.secondaryTextColor)
            }
        }
        .font(SparkleTheme.Typography.caption)
    }

    private var footerButtons: some View {
        HStack {
            Button(strings.t("common.cancel"), role: .cancel) {
                appState.resolveConflict(.skip)
            }
            Spacer()
            Button(strings.t("common.ok")) {
                submitSelectedChoice()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func submitSelectedChoice() {
        let existingName = URL(fileURLWithPath: conflict.destinationDisplayPath).lastPathComponent
        let resolution: TransferConflictResolution = switch selectedChoice {
        case .rename:
            .rename(newFilename: customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ConflictResolver.uniqueName(from: existingName)
                : customName.trimmingCharacters(in: .whitespacesAndNewlines))
        case .resume:
            .resume
        case .skip:
            .skip
        default:
            ConflictResolver.evaluateNonInteractivePolicy(
                selectedChoice.matchingPolicy,
                context: conflict,
                originalFilename: existingName
            )
        }

        let scope: TransferConflictScope = currentDirectionOnly
            ? (conflict.direction == .upload ? .uploadsOnly : .downloadsOnly)
            : .all
        appState.resolveConflict(
            resolution,
            applyToQueue: alwaysApply,
            queuePolicy: selectedChoice.matchingPolicy,
            scope: scope
        )
    }
}
