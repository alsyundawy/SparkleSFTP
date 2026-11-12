import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

extension DualPaneCommanderView {
    func remoteToolbar(session: ActiveSessionModel) -> some View {
        HStack(spacing: SparkleTheme.Spacing.tiny) {
            Button {
                appState.activePane = .right
                Task { await appState.goBackInActivePane() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!session.history.canGoBack)
            .help(appState.strings.t("common.back"))

            Button {
                appState.activePane = .right
                Task { await appState.goForwardInActivePane() }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!session.history.canGoForward)
            .help(appState.strings.t("common.forward"))

            Button {
                Task { await appState.refreshRemoteDirectory(at: session.currentRemotePath.parent) }
            } label: {
                Image(systemName: "arrow.up")
            }
            .help(appState.strings.t("nav.parentDirectory"))

            TextField(appState.strings.t("nav.remotePath"), text: $remotePathText)
                .textFieldStyle(.roundedBorder)
                .font(SparkleTheme.Typography.monoSmall)
                .onSubmit {
                    Task { await appState.refreshRemoteDirectory(at: RemotePath(rawValue: remotePathText)) }
                }

            Button {
                previewQuickLook(selectedFile(isLocal: false), isLocal: false)
            } label: {
                Image(systemName: "eye")
            }
            .help(appState.strings.t("nav.quickLookRemote"))

            Button {
                Task { await appState.refreshRemoteDirectory(recordHistory: false) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
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

            Button(appState.strings.t("conn.selectAllShort")) {
                if isLocal {
                    appState.selectAllLocalFiles()
                } else {
                    appState.selectAllRemoteFiles()
                }
            }
            .help(appState.strings.t("conn.selectAllTooltip"))

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
        if let preferred, matches.contains(where: { $0.id == preferred.id }) {
            return matches
        }
        return preferred.map { [$0] } ?? matches
    }

    func handleContextAction(_ action: FilePaneContextAction, file: RemoteFile?, isLocal: Bool) {
        let target = file ?? selectedFile(isLocal: isLocal)
        let selection = selectedFiles(isLocal: isLocal, preferred: target)
        if handleBasicPaneAction(action, target: target, selection: selection, isLocal: isLocal) {
            return
        }
        if handleEditorAndFinderAction(action, target: target, isLocal: isLocal) {
            return
        }
        if handleTransferAndCopyMoveAction(action, target: target, selection: selection, isLocal: isLocal) {
            return
        }
        if handleCustomCommandAction(action, target: target, selection: selection, isLocal: isLocal) {
            return
        }
        handleFileNamesAction(action, selection: selection, isLocal: isLocal)
    }

    private func handleBasicPaneAction(
        _ action: FilePaneContextAction,
        target: RemoteFile?,
        selection: [RemoteFile],
        isLocal: Bool
    ) -> Bool {
        switch action {
        case .open:
            activateItem(target, isLocal: isLocal)
        case .quickLook:
            previewQuickLook(target, isLocal: isLocal)
        case .permissions:
            handleRemotePermissions(target: target, isLocal: isLocal)
        case .inspect:
            target.map { inspectorContext = FileInspectorContext(item: $0, isLocal: isLocal) }
        case .newFolder:
            isShowingNewFolderSheet = true
        case .selectAll:
            if isLocal {
                appState.selectAllLocalFiles()
            } else {
                appState.selectAllRemoteFiles()
            }
        case .copyClipboard:
            appState.copyItemsToClipboard(files: selection, isLocal: isLocal)
        default:
            return false
        }
        return true
    }

    private func handleEditorAndFinderAction(
        _ action: FilePaneContextAction,
        target: RemoteFile?,
        isLocal: Bool
    ) -> Bool {
        switch action {
        case .edit:
            openTargetInInternalEditor(target, isLocal: isLocal)
        case .openExternalApp:
            Task { await appState.openInExternalEditor(file: target, isLocal: isLocal) }
        case .configureEditor:
            appState.openPreferencesWindow()
        case .showInFinder:
            if isLocal {
                appState.showInFinder(file: target)
            }
        default:
            return false
        }
        return true
    }

    private func handleTransferAndCopyMoveAction(
        _ action: FilePaneContextAction,
        target: RemoteFile?,
        selection: [RemoteFile],
        isLocal: Bool
    ) -> Bool {
        switch action {
        case .transfer:
            Task { await appState.enqueueSelectedTransfer() }
        case .copyTo:
            openCopyMovePrompt(files: selection, isLocal: isLocal, isMove: false)
        case .moveTo:
            openCopyMovePrompt(files: selection, isLocal: isLocal, isMove: true)
        case .rename:
            target.map { renamingContext = ($0, isLocal) }
        case .delete:
            Task { await appState.deleteSelectedItems() }
        default:
            return false
        }
        return true
    }

    private func handleCustomCommandAction(
        _ action: FilePaneContextAction,
        target: RemoteFile?,
        selection: [RemoteFile],
        isLocal: Bool
    ) -> Bool {
        switch action {
        case .compareFiles:
            if let target {
                Task { await appState.compareWithOppositePane(file: target, isLocal: isLocal) }
            }
        case .compressAndUpload:
            if isLocal {
                Task { await appState.compressAndUploadLocalFiles(selection) }
            }
        case .verifyChecksum:
            if let target {
                Task { await appState.verifySHA256Checksum(for: target, isLocal: isLocal) }
            }
        case .customSSHCommand:
            if !isLocal, let session = appState.currentSession {
                appState.pendingCustomCommandRequest = CustomCommandRequest(
                    targetFile: target,
                    currentRemoteDir: session.currentRemotePath.rawValue
                )
            }
        default:
            return false
        }
        return true
    }

    private func handleFileNamesAction(
        _ action: FilePaneContextAction,
        selection: [RemoteFile],
        isLocal: Bool
    ) {
        switch action {
        case .insertCommandLine:
            Task { await appState.insertFileNamesToCommandLine(files: selection, useFullPath: !isLocal) }
        case .copyFileNames:
            appState.copyFileNamesToClipboard(files: selection, includePaths: false)
        case .copyFullPaths:
            appState.copyFileNamesToClipboard(files: selection, includePaths: true)
        default:
            break
        }
    }

    private func openCopyMovePrompt(files: [RemoteFile], isLocal: Bool, isMove: Bool) {
        guard !files.isEmpty else { return }
        let defaultDest = isLocal
            ? (appState.currentSession?.currentRemotePath.rawValue ?? appState.localCurrentURL.path)
            : appState.localCurrentURL.path
        appState.pendingCopyMoveRequest = CopyMoveRequest(
            files: files,
            isLocal: isLocal,
            isMove: isMove,
            defaultDestinationDir: defaultDest
        )
    }

    private func handleRemotePermissions(target: RemoteFile?, isLocal: Bool) {
        guard !isLocal, let target else { return }
        editingPermissionsFile = target
    }

    private func openTargetInInternalEditor(_ target: RemoteFile?, isLocal: Bool) {
        guard let target, !target.isDirectory else { return }
        if isLocal {
            appState.openLocalFileInInternalEditor(target)
        } else {
            Task { await appState.openRemoteFileInInternalEditor(target) }
        }
    }

    private func activateItem(_ target: RemoteFile?, isLocal: Bool) {
        guard let target else { return }
        if isLocal {
            let localURL = URL(fileURLWithPath: target.path.rawValue)
            if target.isDirectory {
                Task { await appState.refreshLocalDirectory(localURL) }
            } else if appState.openDoubleClickInInternalEditor {
                appState.openLocalFileInInternalEditor(target)
            } else {
                quickLookCoordinator.preview(url: localURL)
            }
        } else if target.isDirectory {
            Task { await appState.refreshRemoteDirectory(at: target.path) }
        } else if appState.openDoubleClickInInternalEditor {
            Task { await appState.openRemoteFileInInternalEditor(target) }
        } else {
            Task { await appState.openRemoteFileInEditor(target) }
        }
    }

    private func previewQuickLook(_ target: RemoteFile?, isLocal: Bool) {
        guard let target, !target.isDirectory else { return }
        if isLocal {
            quickLookCoordinator.preview(url: URL(fileURLWithPath: target.path.rawValue))
            return
        }
        Task {
            if let previewURL = await appState.quickLookRemoteFile(target) {
                quickLookCoordinator.preview(url: previewURL)
            }
        }
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
}
