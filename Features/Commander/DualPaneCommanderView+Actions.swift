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

            Button {
                appState.activePane = .right
                Task { await appState.goForwardInActivePane() }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!session.history.canGoForward)

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
                previewQuickLook(selectedFile(isLocal: false), isLocal: false)
            } label: {
                Image(systemName: "eye")
            }
            .help("Quick Look Remote")

            Button {
                Task { await appState.refreshRemoteDirectory(recordHistory: false) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .padding(SparkleTheme.Spacing.tiny)
        .background(SparkleTheme.Colors.panelBackground)
    }

    func paginationBanner(isLocal: Bool) -> some View {
        HStack {
            Text("Showing first page of large directory")
                .font(SparkleTheme.Typography.caption)
                .foregroundStyle(SparkleTheme.Colors.secondaryText)
            Spacer()
            Button("Load More") {
                appState.activePane = isLocal ? .left : .right
                appState.loadMoreFilesInActivePane()
            }
            .buttonStyle(.borderless)
            .font(SparkleTheme.Typography.caption)
        }
        .padding(.horizontal, SparkleTheme.Spacing.small)
        .padding(.vertical, 3)
        .background(SparkleTheme.Colors.panelBackground.opacity(0.7))
    }

    func commanderActionBar(isLocal: Bool, session _: ActiveSessionModel? = nil) -> some View {
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

            if let target = selectedFile(isLocal: isLocal) {
                Button("Rename") { renamingContext = (target, isLocal) }
                Button("Info") { inspectorContext = FileInspectorContext(item: target, isLocal: isLocal) }
                if !isLocal {
                    Button("chmod") { editingPermissionsFile = target }
                    if !target.isDirectory {
                        Button("Edit") { Task { await appState.openRemoteFileInEditor(target) } }
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

    func selectedFile(isLocal: Bool) -> RemoteFile? {
        if isLocal {
            guard let id = appState.selectedLocalFileIDs.first else { return nil }
            return appState.localFiles.allFiles.first { $0.id == id }
        }
        guard let session = appState.currentSession,
              let id = session.selectedRemoteFileIDs.first
        else { return nil }
        return session.remoteFiles.allFiles.first { $0.id == id }
    }

    func handleContextAction(_ action: FilePaneContextAction, file: RemoteFile?, isLocal: Bool) {
        let target = file ?? selectedFile(isLocal: isLocal)
        switch action {
        case .open:
            activateItem(target, isLocal: isLocal)
        case .transfer:
            Task { await appState.enqueueSelectedTransfer() }
        case .quickLook:
            previewQuickLook(target, isLocal: isLocal)
        case .edit, .permissions:
            handleRemoteOnlyAction(action, target: target, isLocal: isLocal)
        case .rename:
            target.map { renamingContext = ($0, isLocal) }
        case .inspect:
            target.map { inspectorContext = FileInspectorContext(item: $0, isLocal: isLocal) }
        case .newFolder:
            isShowingNewFolderSheet = true
        case .delete:
            Task { await appState.deleteSelectedItems() }
        }
    }

    private func handleRemoteOnlyAction(_ action: FilePaneContextAction, target: RemoteFile?, isLocal: Bool) {
        guard !isLocal, let target else { return }
        if action == .edit, !target.isDirectory {
            Task { await appState.openRemoteFileInEditor(target) }
        } else if action == .permissions {
            editingPermissionsFile = target
        }
    }

    private func activateItem(_ target: RemoteFile?, isLocal: Bool) {
        guard let target else { return }
        if isLocal {
            let localURL = URL(fileURLWithPath: target.path.rawValue)
            if target.isDirectory {
                Task { await appState.refreshLocalDirectory(localURL) }
            } else {
                quickLookCoordinator.preview(url: localURL)
            }
        } else if target.isDirectory {
            Task { await appState.refreshRemoteDirectory(at: target.path) }
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
            .stroke(isFocused ? SparkleTheme.Colors.accent.opacity(0.6) : Color.clear, lineWidth: 1.5)
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
