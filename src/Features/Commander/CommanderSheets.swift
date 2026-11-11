import AppKit
import Quartz
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager
import SparkleTransferEngine
import SwiftUI

public struct PermissionsEditorSheet: View {
    let file: RemoteFile
    let strings: AppStrings
    let onApply: (UInt32) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sparklePalette) private var palette
    @State private var octalText: String

    public init(file: RemoteFile, strings: AppStrings = AppStrings(), onApply: @escaping (UInt32) -> Void) {
        self.file = file
        self.strings = strings
        self.onApply = onApply
        _octalText = State(initialValue: POSIXPermissions(mode: file.permissions).octalString)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Text("\(strings.t("pane.posixPermissions")) — \(file.name)").font(SparkleTheme.Typography.title)
            TextField(strings.t("pane.octalExample"), text: $octalText)
                .font(SparkleTheme.Typography.mono)
            if let parsed = POSIXPermissions.from(octalString: octalText) {
                Text("\(strings.t("pane.symbolic")): \(parsed.symbolicString)")
                    .font(SparkleTheme.Typography.monoSmall)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(strings.t("common.cancel"), role: .cancel) { dismiss() }
                Button(strings.t("common.apply")) {
                    if let parsed = POSIXPermissions.from(octalString: octalText) {
                        onApply(parsed.mode)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 360, height: 190)
        .sparkleWorkspaceSurface(palette)
    }
}

public struct RenameItemSheet: View {
    let item: RemoteFile
    let strings: AppStrings
    let onRename: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sparklePalette) private var palette
    @State private var newName: String

    public init(item: RemoteFile, strings: AppStrings = AppStrings(), onRename: @escaping (String) -> Void) {
        self.item = item
        self.strings = strings
        self.onRename = onRename
        _newName = State(initialValue: item.name)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Text(strings.t("pane.renameItem")).font(SparkleTheme.Typography.title)
            TextField(strings.t("pane.newName"), text: $newName)
                .textFieldStyle(.roundedBorder)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(strings.t("common.cancel"), role: .cancel) { dismiss() }
                Button(strings.t("common.rename")) {
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onRename(trimmed)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 380, height: 165)
        .sparkleWorkspaceSurface(palette)
    }
}

public struct FileInspectorSheet: View {
    let item: RemoteFile
    let isLocal: Bool
    let strings: AppStrings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sparklePalette) private var palette
    @State private var computedSHA256: String?

    public init(item: RemoteFile, isLocal: Bool, strings: AppStrings = AppStrings()) {
        self.item = item
        self.isLocal = isLocal
        self.strings = strings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            HStack {
                Label(item.name, systemImage: item.isDirectory ? "folder.fill" : "doc.text")
                    .font(SparkleTheme.Typography.title)
                Spacer()
                Button(strings.t("common.close")) { dismiss() }
            }

            Form {
                LabeledContent(strings.t("pane.path"), value: item.path.rawValue)
                LabeledContent(
                    strings.t("pane.kind"),
                    value: item.isDirectory
                        ? strings.t("pane.directory")
                        : (item.isSymlink ? strings.t("pane.symlink") : strings.t("pane.file"))
                )
                LabeledContent(strings.t("pane.size"), value: "\(item.size) bytes")
                LabeledContent(
                    strings.t("pane.permissions"),
                    value: "\(POSIXPermissions(mode: item.permissions).symbolicString)"
                        + " (\(POSIXPermissions(mode: item.permissions).octalString))"
                )
                if let mtime = item.modificationTime {
                    LabeledContent(
                        strings.t("pane.modified"),
                        value: mtime.formatted(date: .abbreviated, time: .standard)
                    )
                }
                if let target = item.symlinkTarget {
                    LabeledContent(strings.t("pane.symlinkTarget"), value: target)
                }
                if isLocal, !item.isDirectory {
                    if let digest = computedSHA256 {
                        LabeledContent(strings.t("pane.sha256"), value: digest)
                            .font(SparkleTheme.Typography.monoSmall)
                    } else {
                        Button(strings.t("pane.computeSHA256")) {
                            let url = URL(fileURLWithPath: item.path.rawValue)
                            Task {
                                computedSHA256 = try? await SHA256Verifier.computeHexDigest(of: url)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(palette.windowColor)
        }
        .padding()
        .frame(width: 480, height: 340)
        .sparkleWorkspaceSurface(palette)
    }
}

@MainActor
public final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource {
    private var previewURL: URL?

    public func preview(url: URL) {
        previewURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    public nonisolated func numberOfPreviewItems(in _: QLPreviewPanel) -> Int {
        MainActor.assumeIsolated { previewURL == nil ? 0 : 1 }
    }

    public nonisolated func previewPanel(_: QLPreviewPanel, previewItemAt _: Int) -> (any QLPreviewItem)? {
        MainActor.assumeIsolated { previewURL as NSURL? }
    }
}
