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
    @State var isShowingLocalTree = false
    @State var isShowingRemoteTree = false
    @State var isEditingLocalPath = false
    @State var isEditingRemotePath = false
    @State var isShowingLocalFilter = false
    @State var isShowingRemoteFilter = false
    @State var localFilterQuery = ""
    @State var remoteFilterQuery = ""

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        attachCommanderSheets(
            VStack(spacing: 0) {
                HSplitView {
                    localPane
                        .frame(minWidth: 180)
                        .overlay(paneFocusBorder(isFocused: appState.activePane == .left))

                    remotePane
                        .frame(minWidth: 180)
                        .overlay(paneFocusBorder(isFocused: appState.activePane == .right))
                }

                commanderFunctionKeys
            }
            .frame(
                minWidth: 380,
                idealWidth: 760,
                maxWidth: .infinity,
                minHeight: 160,
                idealHeight: 380,
                maxHeight: .infinity
            )
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
            .onChange(of: appState.activeTabID) { _ in
                localPathText = appState.localCurrentURL.path
                remotePathText = appState.currentSession?.currentRemotePath.rawValue ?? "/"
            }
            .onChange(of: appState.currentSession?.currentRemotePath) { newPath in
                remotePathText = newPath?.rawValue ?? "/"
            }
        )
    }
}

private extension DualPaneCommanderView {
    var localPane: some View {
        let palette = appState.activePalette
        return VStack(spacing: 0) {
            HStack(spacing: SparkleTheme.Spacing.tiny) {
                Button {
                    withAnimation {
                        isShowingLocalTree.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .foregroundStyle(isShowingLocalTree ? palette.accentColor : palette.secondaryTextColor)
                }
                .help(appState.strings.t("tree.toggleTooltip"))

                Button {
                    appState.activePane = .left
                    Task { await appState.goBackInActivePane() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!appState.localHistory.canGoBack)
                .help(appState.strings.t("common.back"))

                Button {
                    appState.activePane = .left
                    Task { await appState.goForwardInActivePane() }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!appState.localHistory.canGoForward)
                .help(appState.strings.t("common.forward"))

                Button {
                    let parent = appState.localCurrentURL.deletingLastPathComponent()
                    Task { await appState.refreshLocalDirectory(parent) }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .help(appState.strings.t("nav.parentDirectory"))

                BreadcrumbsBarView(
                    currentPath: appState.localCurrentURL.path,
                    isLocal: true,
                    palette: palette,
                    isEditingText: $isEditingLocalPath,
                    manualPathInput: $localPathText
                ) { newPath in
                    let url = URL(fileURLWithPath: newPath)
                    Task { await appState.refreshLocalDirectory(url) }
                }

                BookmarkQuickJumpMenu(appState: appState, isLocal: true)

                Button {
                    withAnimation { isShowingLocalFilter.toggle() }
                } label: {
                    Image(
                        systemName: isShowingLocalFilter
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                    .foregroundStyle(
                        isShowingLocalFilter || !localFilterQuery.isEmpty
                            ? palette.accentColor
                            : palette.secondaryTextColor
                    )
                }
                .help("Toggle filter bar (⌘F)")

                Button {
                    if let selectedID = appState.selectedLocalFileIDs.first {
                        quickLookCoordinator.preview(url: URL(fileURLWithPath: selectedID))
                    }
                } label: {
                    Image(systemName: "eye")
                }
                .help(appState.strings.t("nav.quickLook"))
            }
            .padding(SparkleTheme.Spacing.tiny)
            .background(palette.windowColor)

            if isShowingLocalFilter {
                FileListingFilterBar(
                    query: $localFilterQuery,
                    isPresented: $isShowingLocalFilter,
                    totalCount: appState.localFiles.allFiles.count,
                    filteredCount: appState.localFiles.filteredFiles.count,
                    palette: palette
                ) { newQuery in
                    appState.filterLocalFiles(newQuery)
                }
            }

            HSplitView {
                if isShowingLocalTree {
                    DirectoryTreeView(appState: appState, isLocal: true)
                        .frame(minWidth: 140, idealWidth: 180, maxWidth: 280)
                }

                FilePaneTableView(
                    files: Array(appState.localFiles.visibleFiles),
                    selectedIDs: $appState.selectedLocalFileIDs,
                    isLocalPane: true,
                    strings: appState.strings,
                    palette: palette,
                    onActivateRow: { item in
                        if item.isDirectory {
                            Task { await appState.refreshLocalDirectory(URL(fileURLWithPath: item.path.rawValue)) }
                        } else if appState.openDoubleClickInInternalEditor {
                            appState.openLocalFileInInternalEditor(item)
                        } else {
                            quickLookCoordinator.preview(url: URL(fileURLWithPath: item.path.rawValue))
                        }
                    },
                    onQuickLookRow: { item in
                        if !item.isDirectory {
                            quickLookCoordinator.preview(url: URL(fileURLWithPath: item.path.rawValue))
                        }
                    },
                    onGoParent: {
                        let parent = appState.localCurrentURL.deletingLastPathComponent()
                        Task { await appState.refreshLocalDirectory(parent) }
                    },
                    onSortColumn: { field in
                        Task { await appState.sortLocalFiles(by: field) }
                    },
                    onFocusPane: { appState.activePane = .left },
                    onContextAction: { action, targetFile in
                        handleContextAction(action, file: targetFile, isLocal: true)
                    }
                )
            }

            if appState.localFiles.hasMorePages {
                paginationBanner(isLocal: true)
            }
            commanderActionBar(isLocal: true)
        }
        .background(palette.canvasColor)
    }

    var remotePane: some View {
        let palette = appState.activePalette
        return VStack(spacing: 0) {
            if let session = appState.currentSession {
                if !session.profile.protocolType.isEncryptedByDefault {
                    SecurityWarningBanner(message: appState.strings.plaintextFTPWarning)
                }

                remoteToolbar(session: session)

                if isShowingRemoteFilter {
                    FileListingFilterBar(
                        query: $remoteFilterQuery,
                        isPresented: $isShowingRemoteFilter,
                        totalCount: session.remoteFiles.allFiles.count,
                        filteredCount: session.remoteFiles.filteredFiles.count,
                        palette: palette
                    ) { newQuery in
                        appState.filterRemoteFiles(newQuery)
                    }
                }

                HSplitView {
                    if isShowingRemoteTree {
                        DirectoryTreeView(appState: appState, isLocal: false)
                            .frame(minWidth: 140, idealWidth: 180, maxWidth: 280)
                    }

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
                        strings: appState.strings,
                        palette: palette,
                        onActivateRow: { item in
                            if item.isDirectory {
                                Task { await appState.refreshRemoteDirectory(at: item.path) }
                            } else if appState.openDoubleClickInInternalEditor {
                                Task { await appState.openRemoteFileInInternalEditor(item) }
                            } else {
                                Task { await appState.openRemoteFileInEditor(item) }
                            }
                        },
                        onQuickLookRow: { item in
                            if !item.isDirectory {
                                Task {
                                    if let url = await appState.quickLookRemoteFile(item) {
                                        quickLookCoordinator.preview(url: url)
                                    }
                                }
                            }
                        },
                        onGoParent: {
                            Task { await appState.refreshRemoteDirectory(at: session.currentRemotePath.parent) }
                        },
                        onSortColumn: { field in
                            Task { await appState.sortRemoteFiles(by: field) }
                        },
                        onFocusPane: { appState.activePane = .right },
                        onContextAction: { action, targetFile in
                            handleContextAction(action, file: targetFile, isLocal: false)
                        }
                    )
                    .id(session.id)
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        handleDrop(providers: providers)
                    }
                }

                if session.remoteFiles.hasMorePages {
                    paginationBanner(isLocal: false)
                }
                commanderActionBar(isLocal: false, session: session)
                RemoteCommandBar(appState: appState)
            } else {
                VStack(spacing: SparkleTheme.Spacing.medium) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 34))
                        .foregroundStyle(palette.secondaryTextColor)
                    Text(appState.strings.t("nav.selectConnectionPrompt"))
                        .font(SparkleTheme.Typography.body)
                        .foregroundStyle(palette.secondaryTextColor)
                    if !appState.recentProfiles.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(appState.recentProfiles.prefix(3)) { recent in
                                Button {
                                    Task { await appState.connect(profile: recent) }
                                } label: {
                                    Label(recent.name, systemImage: SparkleTheme.Symbols.connect)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.canvasColor)
            }
        }
        .background(palette.canvasColor)
    }
}
