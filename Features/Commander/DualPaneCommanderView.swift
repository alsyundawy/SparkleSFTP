import AppKit
import SparkleCore
import SparkleDesignSystem
import SparkleFileManager
import SwiftUI
import UniformTypeIdentifiers

struct FileInspectorContext: Identifiable {
    let id = UUID()
    let item: RemoteFile
    let isLocal: Bool
}

public struct DualPaneCommanderView: View {
    @ObservedObject var appState: AppState
    @State var localPathText: String = ""
    @State var remotePathText: String = ""
    @State var isShowingNewFolderSheet = false
    @State var newFolderName = ""
    @State var editingPermissionsFile: RemoteFile?
    @State var renamingContext: (item: RemoteFile, isLocal: Bool)?
    @State var inspectorContext: FileInspectorContext?
    @State var quickLookCoordinator = QuickLookCoordinator()

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
        .onChange(of: appState.currentSession?.currentRemotePath) { newPath in
            remotePathText = newPath?.rawValue ?? "/"
        }
        .sheet(isPresented: $isShowingNewFolderSheet) {
            newFolderSheet
        }
        .sheet(item: $editingPermissionsFile) { file in
            PermissionsEditorSheet(file: file) { mode in
                Task { await appState.setRemotePermissions(mode, for: file) }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { renamingContext != nil },
                set: {
                    if !$0 {
                        renamingContext = nil
                    }
                }
            )
        ) {
            if let ctx = renamingContext {
                RenameItemSheet(item: ctx.item) { updatedName in
                    Task { await appState.renameItem(ctx.item, to: updatedName, isLocal: ctx.isLocal) }
                }
            }
        }
        .sheet(item: $inspectorContext) { ctx in
            FileInspectorSheet(item: ctx.item, isLocal: ctx.isLocal)
        }
    }

    private var newFolderSheet: some View {
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

    private var localPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: SparkleTheme.Spacing.tiny) {
                Button {
                    appState.activePane = .left
                    Task { await appState.goBackInActivePane() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!appState.localHistory.canGoBack)
                .help("Back")

                Button {
                    appState.activePane = .left
                    Task { await appState.goForwardInActivePane() }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!appState.localHistory.canGoForward)
                .help("Forward")

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
                isLocalPane: true,
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
                onFocusPane: { appState.activePane = .left },
                onContextAction: { action, targetFile in
                    handleContextAction(action, file: targetFile, isLocal: true)
                }
            )

            if appState.localFiles.hasMorePages {
                paginationBanner(isLocal: true)
            }
            commanderActionBar(isLocal: true)
        }
    }

    private var remotePane: some View {
        VStack(spacing: 0) {
            if let session = appState.currentSession {
                if !session.profile.protocolType.isEncryptedByDefault {
                    SecurityWarningBanner(message: appState.strings.plaintextFTPWarning)
                }

                remoteToolbar(session: session)

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
                    isLocalPane: false,
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
                    onFocusPane: { appState.activePane = .right },
                    onContextAction: { action, targetFile in
                        handleContextAction(action, file: targetFile, isLocal: false)
                    }
                )
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }

                if session.remoteFiles.hasMorePages {
                    paginationBanner(isLocal: false)
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
}
