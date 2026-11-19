import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

extension DualPaneCommanderView {
    private func remoteNavGroup(session: ActiveSessionModel) -> some View {
        HStack(spacing: SparkleTheme.Spacing.tiny) {
            Button {
                appState.activePane = .right
                Task { await appState.goBackInActivePane() }
            } label: { Image(systemName: "chevron.left") }
                .disabled(!session.history.canGoBack)
                .help(appState.strings.t("common.back"))

            Button {
                appState.activePane = .right
                Task { await appState.goForwardInActivePane() }
            } label: { Image(systemName: "chevron.right") }
                .disabled(!session.history.canGoForward)
                .help(appState.strings.t("common.forward"))

            Button {
                Task { await appState.refreshRemoteDirectory(at: session.currentRemotePath.parent) }
            } label: { Image(systemName: "arrow.up") }
                .help(appState.strings.t("nav.parentDirectory"))
        }
    }

    func remoteToolbar(session: ActiveSessionModel) -> some View {
        HStack(spacing: SparkleTheme.Spacing.tiny) {
            Button {
                withAnimation { isShowingRemoteTree.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .foregroundStyle(
                        isShowingRemoteTree
                            ? appState.activePalette.accentColor
                            : appState.activePalette.secondaryTextColor
                    )
            }
            .help(appState.strings.t("tree.toggleTooltip"))

            remoteNavGroup(session: session)

            BreadcrumbsBarView(
                currentPath: session.currentRemotePath.rawValue,
                isLocal: false,
                palette: appState.activePalette,
                isEditingText: $isEditingRemotePath,
                manualPathInput: $remotePathText
            ) { newPath in
                Task { await appState.refreshRemoteDirectory(at: RemotePath(rawValue: newPath)) }
            }

            BookmarkQuickJumpMenu(appState: appState, isLocal: false)

            Button {
                withAnimation { isShowingRemoteFilter.toggle() }
            } label: {
                Image(
                    systemName: isShowingRemoteFilter
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
                .foregroundStyle(
                    isShowingRemoteFilter || !remoteFilterQuery.isEmpty
                        ? appState.activePalette.accentColor
                        : appState.activePalette.secondaryTextColor
                )
            }
            .help("Toggle filter bar (⌘F)")

            Button {
                previewQuickLook(selectedFile(isLocal: false), isLocal: false)
            } label: { Image(systemName: "eye") }
                .help(appState.strings.t("nav.quickLookRemote"))

            Button {
                Task { await appState.refreshRemoteDirectory(recordHistory: false) }
            } label: { Image(systemName: "arrow.clockwise") }
                .help(appState.strings.refresh)
        }
        .padding(SparkleTheme.Spacing.tiny)
        .background(appState.activePalette.windowColor)
    }

    func paginationBanner(isLocal: Bool) -> some View {
        let palette = appState.activePalette
        return HStack {
            Text(appState.strings.t("nav.showingFirstPage"))
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(palette.secondaryTextColor)
            Spacer()
            Button(appState.strings.t("nav.loadMore")) {
                appState.activePane = isLocal ? .left : .right
                appState.loadMoreFilesInActivePane()
            }
            .buttonStyle(.borderless)
            .font(SparkleTheme.Typography.caption)
        }
        .padding(.horizontal, SparkleTheme.Spacing.small)
        .padding(.vertical, 3)
        .background(palette.windowColor)
    }

    @ViewBuilder
    private func commanderSelectAllButtons(isLocal: Bool) -> some View {
        let hasSelection = isLocal
            ? !appState.selectedLocalFileIDs.isEmpty
            : !(appState.currentSession?.selectedRemoteFileIDs.isEmpty ?? true)

        Button(appState.strings.t("conn.selectAllShort")) {
            if isLocal {
                appState.selectAllLocalFiles()
            } else {
                appState.selectAllRemoteFiles()
            }
        }
        .help(appState.strings.t("conn.selectAllTooltip"))

        Button(appState.strings.t("conn.deselectAllShort")) {
            if isLocal {
                appState.deselectAllLocalFiles()
            } else {
                appState.deselectAllRemoteFiles()
            }
        }
        .disabled(!hasSelection)
        .help(appState.strings.t("conn.deselectAllTooltip"))
    }

    func commanderActionBar(isLocal: Bool, session _: ActiveSessionModel? = nil) -> some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            Button(isLocal ? appState.strings.upload : appState.strings.download) {
                appState.activePane = isLocal ? .left : .right
                Task { await appState.enqueueSelectedTransfer() }
            }
            .disabled(appState.currentSession == nil)
            .accessibilityLabel(isLocal ? appState.strings.upload : appState.strings.download)
            .help(isLocal ? appState.strings.t("nav.uploadTooltip") : appState.strings.t("nav.downloadTooltip"))

            Button(appState.strings.newFolder) {
                appState.activePane = isLocal ? .left : .right
                isShowingNewFolderSheet = true
            }
            .disabled(!isLocal && appState.currentSession == nil)
            .accessibilityLabel(appState.strings.newFolder)
            .help(appState.strings.t("nav.newFolderTooltip"))

            commanderSelectionActionButtons(isLocal: isLocal)
            commanderSelectAllButtons(isLocal: isLocal)

            Button(appState.strings.delete, role: .destructive) {
                appState.activePane = isLocal ? .left : .right
                Task { await appState.deleteSelectedItems() }
            }
            .disabled(!isLocal && appState.currentSession == nil)
            .help(appState.strings.t("common.deleteTooltip"))

            Spacer()
        }
        .padding(.horizontal, SparkleTheme.Spacing.small)
        .padding(.vertical, SparkleTheme.Spacing.tiny)
        .background(appState.activePalette.windowColor)
        .onReceive(NotificationCenter.default.publisher(for: .sparkleRequestNewFolder)) { notification in
            guard (notification.object as? UUID) == appState.windowInstanceID else { return }
            if isLocal == (appState.activePane == .left) {
                isShowingNewFolderSheet = true
            }
        }
    }

    @ViewBuilder
    private func commanderSelectionActionButtons(isLocal: Bool) -> some View {
        if let target = selectedFile(isLocal: isLocal) {
            Button(appState.strings.t("common.rename")) { renamingContext = (target, isLocal) }
                .help(appState.strings.t("common.renameTooltip"))
            Button(appState.strings.t("pane.info")) {
                inspectorContext = FileInspectorContext(item: target, isLocal: isLocal)
            }
            .help(appState.strings.t("pane.infoTooltip"))
            if !target.isDirectory {
                Button(appState.strings.t("common.edit")) {
                    if isLocal {
                        appState.openLocalFileInInternalEditor(target)
                    } else {
                        Task { await appState.openRemoteFileInInternalEditor(target) }
                    }
                }
                .help(appState.strings.t("common.editTooltip"))
            }
            if !isLocal {
                Button("chmod") { editingPermissionsFile = target }
                    .help(appState.strings.t("pane.chmodTooltip"))
            }
        }
    }

    func selectedFile(isLocal: Bool) -> RemoteFile? {
        selectedFiles(isLocal: isLocal, preferred: nil).first
    }

    func selectedFiles(isLocal: Bool, preferred: RemoteFile?) -> [RemoteFile] {
        let matches: [RemoteFile] = if isLocal {
            appState.localFiles.allFiles.filter { appState.selectedLocalFileIDs.contains($0.id) }
        } else if let session = appState.currentSession {
            session.remoteFiles.allFiles.filter { session.selectedRemoteFileIDs.contains($0.id) }
        } else {
            []
        }
        if matches.isEmpty, let preferred {
            return [preferred]
        }
        return matches
    }

    func paneFocusBorder(isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .stroke(isFocused ? appState.activePalette.accentColor.opacity(0.75) : Color.clear, lineWidth: 1.5)
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
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

    var commanderFunctionKeys: some View {
        CommanderFunctionKeyBar(
            palette: appState.activePalette,
            onView: { triggerQuickLookOnActivePane() },
            onEdit: { triggerEditOnActivePane() },
            onCopy: { Task { await appState.enqueueSelectedTransfer() } },
            onMove: { triggerMoveOnActivePane() },
            onMkdir: { isShowingNewFolderSheet = true },
            onDelete: { Task { await appState.deleteSelectedItems() } }
        )
    }

    var newFolderSheet: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Text(appState.strings.newFolder).font(SparkleTheme.Typography.title)
            TextField(appState.strings.t("pane.folderName"), text: $newFolderName)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(appState.strings.t("common.cancel"), role: .cancel) { isShowingNewFolderSheet = false }
                Button(appState.strings.t("common.create")) {
                    let name = newFolderName
                    newFolderName = ""
                    isShowingNewFolderSheet = false
                    Task { await appState.createFolder(named: name) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 360, height: 165)
        .sparkleWorkspaceSurface(appState.activePalette)
    }

    func triggerQuickLookOnActivePane() {
        let isLocal = appState.activePane == .left
        if isLocal {
            if let selectedID = appState.selectedLocalFileIDs.first {
                quickLookCoordinator.preview(url: URL(fileURLWithPath: selectedID))
            }
        } else {
            previewQuickLook(selectedFile(isLocal: false), isLocal: false)
        }
    }

    func triggerEditOnActivePane() {
        let isLocal = appState.activePane == .left
        guard let file = selectedFile(isLocal: isLocal), !file.isDirectory else { return }
        if isLocal {
            appState.openLocalFileInInternalEditor(file)
        } else {
            Task { await appState.openRemoteFileInInternalEditor(file) }
        }
    }

    func triggerMoveOnActivePane() {
        let isLocal = appState.activePane == .left
        guard let file = selectedFile(isLocal: isLocal) else { return }
        renamingContext = (file, isLocal)
    }

    func attachCommanderSheets<Content: View>(_ content: Content) -> some View {
        attachTransferAndReportSheets(attachCoreSheets(content))
    }

    private func attachCoreSheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $isShowingNewFolderSheet) {
                newFolderSheet
            }
            .sheet(item: $editingPermissionsFile) { file in
                PermissionsEditorSheet(file: file, strings: appState.strings) { mode in
                    Task { await appState.setRemotePermissions(mode, for: file) }
                }
                .environment(\.sparklePalette, appState.activePalette)
            }
            .sheet(
                isPresented: Binding(
                    get: { renamingContext != nil },
                    set: { if !$0 { renamingContext = nil } }
                )
            ) {
                if let ctx = renamingContext {
                    RenameItemSheet(item: ctx.item, strings: appState.strings) { updatedName in
                        Task { await appState.renameItem(ctx.item, to: updatedName, isLocal: ctx.isLocal) }
                    }
                    .environment(\.sparklePalette, appState.activePalette)
                }
            }
            .sheet(item: $inspectorContext) { ctx in
                FileInspectorSheet(item: ctx.item, isLocal: ctx.isLocal, strings: appState.strings)
                    .environment(\.sparklePalette, appState.activePalette)
            }
    }

    private func attachTransferAndReportSheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(item: $appState.pendingCopyMoveRequest) { req in
                let oppDefault = req.isLocal
                    ? (appState.currentSession?.currentRemotePath.rawValue ?? "/")
                    : appState.localCurrentURL.path
                let sameDefault = req.isLocal
                    ? appState.localCurrentURL.path
                    : (appState.currentSession?.currentRemotePath.rawValue ?? "/")
                CopyMoveItemSheet(
                    request: req,
                    hasActiveSession: appState.currentSession != nil,
                    oppositeDefaultPath: oppDefault,
                    sameSideDefaultPath: sameDefault,
                    strings: appState.strings
                ) { destDir, crossPane in
                    Task {
                        await appState.performCopyOrMove(
                            request: req,
                            destinationDir: destDir,
                            transferToOppositePane: crossPane
                        )
                    }
                }
                .environment(\.sparklePalette, appState.activePalette)
            }
            .sheet(item: $appState.pendingChecksumReport) { report in
                ChecksumResultSheet(report: report, strings: appState.strings)
                    .environment(\.sparklePalette, appState.activePalette)
            }
            .sheet(item: $appState.pendingComparisonReport) { report in
                FileComparisonSheet(report: report, strings: appState.strings)
                    .environment(\.sparklePalette, appState.activePalette)
            }
            .sheet(item: $appState.pendingCustomCommandRequest) { req in
                CustomSSHCommandSheet(appState: appState, request: req)
                    .environment(\.sparklePalette, appState.activePalette)
            }
    }
}
