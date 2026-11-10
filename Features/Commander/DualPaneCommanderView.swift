import AppKit
import Quartz
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager
import SwiftUI
import UniformTypeIdentifiers

public struct DualPaneCommanderView: View {
    @ObservedObject var appState: AppState
    @State private var localPathText: String = ""
    @State private var remotePathText: String = ""
    @State private var isShowingNewFolderSheet = false
    @State private var newFolderName = ""
    @State private var editingPermissionsFile: RemoteFile?
    @State private var quickLookCoordinator = QuickLookCoordinator()

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        HSplitView {
            localPane
                .frame(minWidth: 280)
                .overlay(paneFocusBorder(isFocused: appState.activePane == .left))

            remotePane
                .frame(minWidth: 280)
                .overlay(paneFocusBorder(isFocused: appState.activePane == .right))
        }
        .onAppear {
            localPathText = appState.localCurrentURL.path
            remotePathText = appState.currentSession?.currentRemotePath.rawValue ?? "/"
        }
        .onChange(of: appState.localCurrentURL) { newURL in
            localPathText = newURL.path
        }
        .onChange(of: appState.activeSessionID) { _ in
            remotePathText = appState.currentSession?.currentRemotePath.rawValue ?? "/"
        }
        .sheet(isPresented: $isShowingNewFolderSheet) {
            VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
                Text(appState.strings.newFolder).font(SparkleTheme.Typography.title)
                TextField("Folder Name", text: $newFolderName)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { isShowingNewFolderSheet = false }
                    Button("Create") {
                        let name = newFolderName
                        newFolderName = ""
                        isShowingNewFolderSheet = false
                        Task { await appState.createFolder(named: name) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 340)
        }
        .sheet(item: $editingPermissionsFile) { file in
            PermissionsEditorSheet(file: file) { mode in
                Task { await appState.setRemotePermissions(mode, for: file) }
            }
        }
    }

    private var localPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: SparkleTheme.Spacing.tiny) {
                Button {
                    let parent = appState.localCurrentURL.deletingLastPathComponent()
                    Task { await appState.refreshLocalDirectory(parent) }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .help("Parent Directory")

                TextField("Local Path", text: $localPathText)
                    .textFieldStyle(.roundedBorder)
                    .font(SparkleTheme.Typography.monoSmall)
                    .onSubmit {
                        let url = URL(fileURLWithPath: localPathText)
                        Task { await appState.refreshLocalDirectory(url) }
                    }

                Button {
                    if let selectedID = appState.selectedLocalFileIDs.first {
                        quickLookCoordinator.preview(url: URL(fileURLWithPath: selectedID))
                    }
                } label: {
                    Image(systemName: "eye")
                }
                .help("Quick Look")
            }
            .padding(SparkleTheme.Spacing.tiny)
            .background(SparkleTheme.Colors.panelBackground)

            FilePaneTableView(
                files: Array(appState.localFiles.visibleFiles),
                selectedIDs: $appState.selectedLocalFileIDs,
                onActivateRow: { item in
                    if item.isDirectory {
                        Task { await appState.refreshLocalDirectory(URL(fileURLWithPath: item.path.rawValue)) }
                    } else {
                        quickLookCoordinator.preview(url: URL(fileURLWithPath: item.path.rawValue))
                    }
                },
                onSortColumn: { field in
                    Task { await appState.sortLocalFiles(by: field) }
                },
                onFocusPane: { appState.activePane = .left }
            )

            commanderActionBar(isLocal: true)
        }
    }

    private var remotePane: some View {
        VStack(spacing: 0) {
            if let session = appState.currentSession {
                if !session.profile.protocolType.isEncryptedByDefault {
                    SecurityWarningBanner(message: appState.strings.plaintextFTPWarning)
                }

                HStack(spacing: SparkleTheme.Spacing.tiny) {
                    Button {
                        Task { await appState.refreshRemoteDirectory(at: session.currentRemotePath.parent) }
                    } label: {
                        Image(systemName: "arrow.up")
                    }

                    TextField("Remote Path", text: $remotePathText)
                        .textFieldStyle(.roundedBorder)
                        .font(SparkleTheme.Typography.monoSmall)
                        .onSubmit {
                            Task { await appState.refreshRemoteDirectory(at: RemotePath(rawValue: remotePathText)) }
                        }

                    Button {
                        Task { await appState.refreshRemoteDirectory() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .padding(SparkleTheme.Spacing.tiny)
                .background(SparkleTheme.Colors.panelBackground)

                FilePaneTableView(
                    files: Array(session.remoteFiles.visibleFiles),
                    selectedIDs: Binding(
                        get: { session.selectedRemoteFileIDs },
                        set: { newSet in
                            if let idx = appState.activeSessions.firstIndex(where: { $0.id == session.id }) {
                                appState.activeSessions[idx].selectedRemoteFileIDs = newSet
                            }
                        }
                    ),
                    onActivateRow: { item in
                        if item.isDirectory {
                            Task { await appState.refreshRemoteDirectory(at: item.path) }
                        } else {
                            Task { await appState.openRemoteFileInEditor(item) }
                        }
                    },
                    onSortColumn: { field in
                        Task { await appState.sortRemoteFiles(by: field) }
                    },
                    onFocusPane: { appState.activePane = .right }
                )
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }

                commanderActionBar(isLocal: false, session: session)
            } else {
                VStack(spacing: SparkleTheme.Spacing.small) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 34))
                        .foregroundStyle(SparkleTheme.Colors.secondaryText)
                    Text("Select a connection profile and click Connect")
                        .font(SparkleTheme.Typography.body)
                        .foregroundStyle(SparkleTheme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func commanderActionBar(isLocal: Bool, session: ActiveSessionModel? = nil) -> some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            Button(isLocal ? appState.strings.upload : appState.strings.download) {
                appState.activePane = isLocal ? .left : .right
                Task { await appState.enqueueSelectedTransfer() }
            }
            .disabled(appState.currentSession == nil)
            .accessibilityLabel(isLocal ? appState.strings.upload : appState.strings.download)

            Button(appState.strings.newFolder) {
                appState.activePane = isLocal ? .left : .right
                isShowingNewFolderSheet = true
            }
            .disabled(!isLocal && appState.currentSession == nil)
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .accessibilityLabel(appState.strings.newFolder)

            if !isLocal, let session, let firstID = session.selectedRemoteFileIDs.first,
               let file = session.remoteFiles.allFiles.first(where: { $0.id == firstID }) {
                Button("chmod") {
                    editingPermissionsFile = file
                }
                if !file.isDirectory {
                    Button("Edit") {
                        Task { await appState.openRemoteFileInEditor(file) }
                    }
                }
            }

            Button(appState.strings.delete, role: .destructive) {
                appState.activePane = isLocal ? .left : .right
                Task { await appState.deleteSelectedItems() }
            }
            .disabled(!isLocal && appState.currentSession == nil)

            Spacer()
        }
        .padding(.horizontal, SparkleTheme.Spacing.small)
        .padding(.vertical, SparkleTheme.Spacing.tiny)
        .background(SparkleTheme.Colors.panelBackground)
    }

    private func paneFocusBorder(isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .stroke(isFocused ? SparkleTheme.Colors.accent.opacity(0.6) : Color.clear, lineWidth: 1.5)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    await appState.uploadDroppedFiles([url])
                }
            }
        }
        return true
    }
}

public struct PermissionsEditorSheet: View {
    let file: RemoteFile
    let onApply: (UInt32) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var octalText: String

    public init(file: RemoteFile, onApply: @escaping (UInt32) -> Void) {
        self.file = file
        self.onApply = onApply
        self._octalText = State(initialValue: POSIXPermissions(mode: file.permissions).octalString)
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

    nonisolated public func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        MainActor.assumeIsolated { previewURL == nil ? 0 : 1 }
    }

    nonisolated public func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> (any QLPreviewItem)? {
        MainActor.assumeIsolated { previewURL as NSURL? }
    }
}
