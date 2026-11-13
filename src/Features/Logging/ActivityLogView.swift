import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

public struct ActivityLogView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var logger: ActivityLogger = .shared

    public init(appState: AppState) {
        self.appState = appState
    }

    private var palette: SparkleThemePalette {
        appState.activePalette
    }

    private var strings: AppStrings {
        appState.strings
    }

    private var filteredEntries: [ActivityLogEntry] {
        logger.entries.filter { logger.selectedFilter.matches($0.type) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(palette.borderColor)
            logContent
        }
        .frame(minHeight: 80, idealHeight: 140)
        .sparkleWorkspaceSurface(palette, useCanvas: true)
    }

    private var headerBar: some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            Label(strings.t("activityLog.title"), systemImage: "list.bullet.rectangle")
                .font(SparkleTheme.Typography.headline)

            Picker("", selection: $logger.selectedFilter) {
                ForEach(ActivityLogFilter.allCases) { filter in
                    Text(filter.localizedTitle(strings: strings)).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .font(SparkleTheme.Typography.caption)
            .help(strings.t("activityLog.filterTooltip"))

            Spacer()

            // Centered Minimize / Hide button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.isActivityLogVisible = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                    Text(strings.t("activityLog.hideMinimize"))
                        .font(SparkleTheme.Typography.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(palette.windowColor)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(palette.borderColor.opacity(0.6), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(strings.t("activityLog.hideMinimizeTooltip"))

            Spacer()

            Toggle(isOn: $logger.isAutoScrollEnabled) {
                Text(strings.t("activityLog.autoScroll"))
                    .font(SparkleTheme.Typography.caption)
            }
            .toggleStyle(.checkbox)
            .help(strings.t("activityLog.autoScrollTooltip"))

            Button(strings.t("activityLog.copy")) {
                let formatted = logger.copyAllFormatted()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(formatted, forType: .string)
            }
            .buttonStyle(.borderless)
            .font(SparkleTheme.Typography.caption)
            .foregroundStyle(palette.accentColor)
            .help(strings.t("activityLog.copyTooltip"))

            Button(strings.t("activityLog.clear")) {
                logger.clear()
            }
            .buttonStyle(.borderless)
            .font(SparkleTheme.Typography.caption)
            .foregroundStyle(SparkleTheme.Colors.danger)
            .help(strings.t("activityLog.clearTooltip"))
        }
        .padding(.horizontal, SparkleTheme.Spacing.medium)
        .padding(.vertical, SparkleTheme.Spacing.tiny)
        .background(palette.windowColor)
    }

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if filteredEntries.isEmpty {
                    VStack {
                        Spacer(minLength: 24)
                        Text(strings.t("activityLog.empty"))
                            .font(SparkleTheme.Typography.caption)
                            .foregroundStyle(palette.secondaryTextColor)
                        Spacer(minLength: 24)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredEntries) { entry in
                            logRow(entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, SparkleTheme.Spacing.small)
                    .padding(.vertical, 4)
                }
            }
            .background(palette.canvasColor)
            .onChange(of: logger.entries.count) { _ in
                if logger.isAutoScrollEnabled, let lastID = filteredEntries.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func logRow(_ entry: ActivityLogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("[\(entry.formattedTimeString)]")
                .font(SparkleTheme.Typography.monoSmall)
                .foregroundStyle(palette.secondaryTextColor)

            Text(entry.type.prefix)
                .font(SparkleTheme.Typography.monoSmall.bold())
                .foregroundStyle(prefixColor(for: entry.type))
                .frame(width: 80, alignment: .leading)

            Text(entry.message)
                .font(SparkleTheme.Typography.monoSmall)
                .foregroundStyle(messageColor(for: entry.type))
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .contextMenu {
            Button(strings.t("activityLog.copyRow")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.formattedFullLine, forType: .string)
            }
            Button(strings.t("activityLog.copyMessage")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.message, forType: .string)
            }
            Divider()
            Button(strings.t("activityLog.clear")) {
                logger.clear()
            }
        }
    }

    private func prefixColor(for type: ActivityLogType) -> Color {
        switch type {
        case .status:
            return palette.primaryTextColor.opacity(0.8)
        case .command:
            return palette.accentColor
        case .response:
            return SparkleTheme.Colors.success
        case .error:
            return SparkleTheme.Colors.danger
        case .transfer:
            return palette.isDark ? Color.purple : Color.indigo
        }
    }

    private func messageColor(for type: ActivityLogType) -> Color {
        switch type {
        case .error:
            return SparkleTheme.Colors.danger
        case .response:
            return SparkleTheme.Colors.success
        default:
            return palette.primaryTextColor
        }
    }
}
