import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// Quick-jump bookmark menu button embedded in commander toolbars (v0.5.0).
public struct BookmarkQuickJumpMenu: View {
    @ObservedObject var appState: AppState
    let isLocal: Bool
    @ObservedObject private var bookmarkManager = BookmarkManager.shared
    @State private var isShowingManageSheet = false
    @State private var isShowingAddSheet = false
    @State private var newBookmarkName = ""

    public init(appState: AppState, isLocal: Bool) {
        self.appState = appState
        self.isLocal = isLocal
    }

    private var currentHost: String? {
        appState.currentSession?.profile.host
    }

    private var currentPath: String {
        if isLocal {
            return appState.localCurrentURL.path
        } else {
            return appState.currentSession?.currentRemotePath.rawValue ?? "/"
        }
    }

    private var currentBookmarks: [BookmarkItem] {
        bookmarkManager.bookmarks(forHost: currentHost, isRemote: !isLocal)
    }

    private var recentHistory: [PathHistoryItem] {
        bookmarkManager.recentPaths(isRemote: !isLocal, hostIdentifier: currentHost)
    }

    public var body: some View {
        Menu {
            Section(header: Text(appState.strings.t("bookmarks.title"))) {
                if currentBookmarks.isEmpty {
                    Text(appState.strings.t("bookmarks.empty"))
                } else {
                    ForEach(currentBookmarks) { item in
                        Button {
                            navigateToBookmark(item)
                        } label: {
                            Label(item.name, systemImage: item.iconName ?? "folder")
                        }
                    }
                }
            }

            Divider()

            Button {
                newBookmarkName = URL(fileURLWithPath: currentPath).lastPathComponent
                if newBookmarkName.isEmpty || newBookmarkName == "/" {
                    newBookmarkName = isLocal ? "Local Home" : "Remote Root"
                }
                isShowingAddSheet = true
            } label: {
                Label(appState.strings.t("bookmarks.addCurrent"), systemImage: "plus.rectangle")
            }

            if !recentHistory.isEmpty {
                Menu(appState.strings.t("bookmarks.recentHistory")) {
                    ForEach(recentHistory.prefix(10)) { item in
                        Button {
                            navigateToPath(item.path)
                        } label: {
                            Label(item.path, systemImage: "clock")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        bookmarkManager.clearHistory(isRemote: !isLocal, hostIdentifier: currentHost)
                    } label: {
                        Label(appState.strings.t("bookmarks.clearHistory"), systemImage: "trash")
                    }
                }
            }

            Divider()

            Toggle(isOn: $bookmarkManager.isSynchronizedBrowsingEnabled) {
                Label(appState.strings.t("bookmarks.synchronizedBrowsing"), systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                isShowingManageSheet = true
            } label: {
                Label(appState.strings.t("bookmarks.manage"), systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "bookmark")
        }
        .help(appState.strings.t("bookmarks.tooltip"))
        .sheet(isPresented: $isShowingAddSheet) {
            addBookmarkSheet
        }
        .sheet(isPresented: $isShowingManageSheet) {
            BookmarkManagementSheet(appState: appState)
                .environment(\.sparklePalette, appState.activePalette)
        }
    }

    private var addBookmarkSheet: some View {
        let palette = appState.activePalette
        return VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            Text(appState.strings.t("bookmarks.addTitle"))
                .font(SparkleTheme.Typography.title)
                .foregroundStyle(palette.primaryTextColor)

            VStack(alignment: .leading, spacing: 6) {
                Text(appState.strings.t("bookmarks.nameLabel"))
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.secondaryTextColor)
                TextField(appState.strings.t("bookmarks.namePlaceholder"), text: $newBookmarkName)
                    .textFieldStyle(.roundedBorder)

                Text(appState.strings.t("bookmarks.pathLabel"))
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.secondaryTextColor)
                Text(currentPath)
                    .font(SparkleTheme.Typography.monoSmall)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(palette.accentColor)
            }

            HStack {
                Spacer()
                Button(appState.strings.t("common.cancel"), role: .cancel) {
                    isShowingAddSheet = false
                }
                Button(appState.strings.t("common.save")) {
                    bookmarkManager.addBookmark(
                        name: newBookmarkName,
                        path: currentPath,
                        isRemote: !isLocal,
                        hostIdentifier: currentHost
                    )
                    isShowingAddSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 380, height: 200)
        .sparkleWorkspaceSurface(palette)
    }

    private func navigateToBookmark(_ bookmark: BookmarkItem) {
        navigateToPath(bookmark.path)
    }

    private func navigateToPath(_ path: String) {
        if isLocal {
            let url = URL(fileURLWithPath: path)
            Task { await appState.refreshLocalDirectory(url) }
        } else {
            Task { await appState.refreshRemoteDirectory(at: RemotePath(rawValue: path)) }
        }
    }
}

/// Full management sheet for creating, removing, and organizing bookmarks (v0.5.0).
public struct BookmarkManagementSheet: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var bookmarkManager = BookmarkManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var filterRemoteOnly = false

    public init(appState: AppState) {
        self.appState = appState
    }

    private var displayedBookmarks: [BookmarkItem] {
        if filterRemoteOnly {
            return bookmarkManager.bookmarks.filter(\.isRemote)
        }
        return bookmarkManager.bookmarks
    }

    public var body: some View {
        let palette = appState.activePalette
        VStack(spacing: 0) {
            HStack {
                Text(appState.strings.t("bookmarks.managementTitle"))
                    .font(SparkleTheme.Typography.title)
                    .foregroundStyle(palette.primaryTextColor)
                Spacer()
                Toggle(appState.strings.t("bookmarks.filterRemote"), isOn: $filterRemoteOnly)
                    .font(SparkleTheme.Typography.caption)
                Button(appState.strings.t("common.done")) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(SparkleTheme.Spacing.medium)
            .background(palette.windowColor)

            Divider().overlay(palette.borderColor)

            if displayedBookmarks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(palette.secondaryTextColor)
                    Text(appState.strings.t("bookmarks.noBookmarks"))
                        .font(SparkleTheme.Typography.body)
                        .foregroundStyle(palette.secondaryTextColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.canvasColor)
            } else {
                List {
                    ForEach(displayedBookmarks) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.isRemote ? "network" : "internaldrive")
                                .foregroundStyle(item.isRemote ? palette.accentColor : palette.secondaryTextColor)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(SparkleTheme.Typography.headline)
                                    .foregroundStyle(palette.primaryTextColor)
                                Text(item.path)
                                    .font(SparkleTheme.Typography.monoSmall)
                                    .foregroundStyle(palette.secondaryTextColor)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            if let host = item.hostIdentifier {
                                Text(host)
                                    .font(SparkleTheme.Typography.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(palette.windowColor)
                                    .cornerRadius(4)
                            }

                            Button(role: .destructive) {
                                bookmarkManager.removeBookmark(id: item.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
                .background(palette.canvasColor)
            }
        }
        .frame(width: 520, height: 380)
        .sparkleWorkspaceSurface(palette)
    }
}
