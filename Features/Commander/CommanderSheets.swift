import AppKit
import Quartz
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager
import SparkleTransferEngine
import SwiftUI

public struct PermissionsEditorSheet: View {
    let file: RemoteFile
    let onApply: (UInt32) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var octalText: String

    public init(file: RemoteFile, onApply: @escaping (UInt32) -> Void) {
        self.file = file
        self.onApply = onApply
        _octalText = State(initialValue: POSIXPermissions(mode: file.permissions).octalString)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Text("POSIX Permissions — \(file.name)").font(SparkleTheme.Typography.title)
            TextField("Octal (e.g. 755)", text: $octalText)
                .font(SparkleTheme.Typography.mono)
            if let parsed = POSIXPermissions.from(octalString: octalText) {
                Text("Symbolic: \(parsed.symbolicString)")
                    .font(SparkleTheme.Typography.monoSmall)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Apply") {
                    if let parsed = POSIXPermissions.from(octalString: octalText) {
                        onApply(parsed.mode)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

public struct RenameItemSheet: View {
    let item: RemoteFile
    let onRename: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newName: String

    public init(item: RemoteFile, onRename: @escaping (String) -> Void) {
        self.item = item
        self.onRename = onRename
        _newName = State(initialValue: item.name)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Text("Rename Item").font(SparkleTheme.Typography.title)
            TextField("New name", text: $newName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Rename") {
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
        .frame(width: 360)
    }
}

public struct FileInspectorSheet: View {
    let item: RemoteFile
    let isLocal: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var computedSHA256: String?

    public init(item: RemoteFile, isLocal: Bool) {
        self.item = item
        self.isLocal = isLocal
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            HStack {
                Label(item.name, systemImage: item.isDirectory ? "folder.fill" : "doc.text")
                    .font(SparkleTheme.Typography.title)
                Spacer()
                Button("Close") { dismiss() }
            }

            Form {
                LabeledContent("Path", value: item.path.rawValue)
                LabeledContent("Kind", value: item.isDirectory ? "Directory" : (item.isSymlink ? "Symlink" : "File"))
                LabeledContent("Size", value: "\(item.size) bytes")
                LabeledContent(
                    "Permissions",
                    value: "\(POSIXPermissions(mode: item.permissions).symbolicString)"
                        + " (\(POSIXPermissions(mode: item.permissions).octalString))"
                )
                if let mtime = item.modificationTime {
                    LabeledContent("Modified", value: mtime.formatted(date: .abbreviated, time: .standard))
                }
                if let target = item.symlinkTarget {
                    LabeledContent("Symlink Target", value: target)
                }
                if isLocal, !item.isDirectory {
                    if let digest = computedSHA256 {
                        LabeledContent("SHA-256", value: digest)
                            .font(SparkleTheme.Typography.monoSmall)
                    } else {
                        Button("Compute SHA-256") {
                            let url = URL(fileURLWithPath: item.path.rawValue)
                            Task {
                                computedSHA256 = try? await SHA256Verifier.computeHexDigest(of: url)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding()
        .frame(width: 480, height: 340)
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
