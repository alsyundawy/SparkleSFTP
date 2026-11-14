import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

extension DualPaneCommanderView {
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

    private func handleSelectionAction(_ action: FilePaneContextAction, isLocal: Bool) -> Bool {
        switch action {
        case .selectAll:
            if isLocal {
                appState.selectAllLocalFiles()
            } else {
                appState.selectAllRemoteFiles()
            }
            return true
        case .deselectAll:
            if isLocal {
                appState.deselectAllLocalFiles()
            } else {
                appState.deselectAllRemoteFiles()
            }
            return true
        default:
            return false
        }
    }

    private func handleBasicPaneAction(
        _ action: FilePaneContextAction,
        target: RemoteFile?,
        selection: [RemoteFile],
        isLocal: Bool
    ) -> Bool {
        if handleSelectionAction(action, isLocal: isLocal) {
            return true
        }
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

    func previewQuickLook(_ target: RemoteFile?, isLocal: Bool) {
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
}
