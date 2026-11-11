import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

enum AboutTabKind: Int, CaseIterable, Identifiable {
    case about
    case maintainer
    case credits
    case libraries
    case diagnostics
    case shortcuts
    case license

    var id: Int {
        rawValue
    }

    func title(strings: AppStrings) -> String {
        switch self {
        case .about: return strings.t("about.aboutTab")
        case .maintainer: return strings.t("about.maintainerTab")
        case .credits: return strings.t("about.creditsTab")
        case .libraries: return strings.t("about.librariesTab")
        case .diagnostics: return strings.t("about.diagnosticsTab")
        case .shortcuts: return strings.t("about.shortcutsTab")
        case .license: return strings.t("about.licenseTab")
        }
    }
}

public struct AboutView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: AboutTabKind = .about
    @State private var copiedBanner = false

    public init(appState: AppState) {
        self.appState = appState
    }

    private var palette: SparkleThemePalette {
        appState.activePalette
    }

    private var strings: AppStrings {
        appState.strings
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabBarHeader
            Divider().overlay(palette.borderColor)

            ScrollView {
                tabContent
                    .padding(SparkleTheme.Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(palette.canvasColor)

            Divider().overlay(palette.borderColor)
            footerBar
        }
        .frame(
            minWidth: 640,
            idealWidth: 720,
            maxWidth: .infinity,
            minHeight: 480,
            idealHeight: 560,
            maxHeight: .infinity
        )
        .sparkleWorkspaceSurface(palette)
        .background(SparkleWindowConfigurator(palette: palette, allowFullScreen: true))
        .onReceive(NotificationCenter.default.publisher(for: .sparklePreferencesDidChange)) { notification in
            if (notification.object as? UUID) != appState.windowInstanceID {
                appState.reloadPreferencesFromNotification()
            }
        }
    }

    private var tabBarHeader: some View {
        HStack(spacing: 6) {
            ForEach(AboutTabKind.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title(strings: strings))
                        .font(isSelected ? SparkleTheme.Typography.headline : SparkleTheme.Typography.body)
                        .foregroundStyle(isSelected ? palette.accentColor : palette.secondaryTextColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isSelected ? palette.canvasColor : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? palette.borderColor : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, SparkleTheme.Spacing.medium)
        .padding(.vertical, 8)
        .background(palette.windowColor)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .about:
            aboutOverviewSection
        case .maintainer:
            maintainerSection
        case .credits:
            creditsSection
        case .libraries:
            librariesSection
        case .diagnostics:
            diagnosticsSection
        case .shortcuts:
            shortcutsSection
        case .license:
            licenseSection
        }
    }

    private var footerBar: some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            Button(strings.t("prefs.checkNow")) {
                Task { await appState.checkForUpdates(manual: true) }
            }
            Button(strings.t("about.copyInfo")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(buildDiagnosticsText(), forType: .string)
                copiedBanner = true
            }
            if copiedBanner {
                Text(strings.t("about.copied"))
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(palette.accentColor)
            }
            Spacer()
            Button(strings.t("common.close")) {
                if let keyWindow = NSApp.keyWindow, keyWindow.contentViewController is NSHostingController<AboutView> {
                    keyWindow.close()
                } else {
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, SparkleTheme.Spacing.large)
        .padding(.vertical, 10)
        .background(palette.windowColor)
    }
}
