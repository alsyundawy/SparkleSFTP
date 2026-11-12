import SparkleCore
import SparkleDesignSystem
import SwiftUI

extension MainWindowView {
    var minimizedTransferBar: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.isTransferDrawerVisible = true
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                    Text(
                        appState.strings.t("transfers.showQueue")
                            + (appState.transferSnapshots.isEmpty ? "" : " (\(appState.transferSnapshots.count))")
                    )
                    .font(SparkleTheme.Typography.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(appState.activePalette.windowColor)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(appState.activePalette.borderColor.opacity(0.8), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(appState.strings.t("transfers.showQueueTooltip"))
            Spacer()
        }
        .padding(.vertical, 2)
        .background(appState.activePalette.windowColor.opacity(0.85))
    }

    var groupedThemeFamilies: [String] {
        var families: [String] = []
        for theme in appState.availableThemes where !families.contains(theme.family) {
            families.append(theme.family)
        }
        return families
    }

    var languageMenuSelector: some View {
        Menu {
            ForEach(appState.availableLocales) { doc in
                Button {
                    appState.selectLocale(code: doc.code)
                } label: {
                    if appState.activeLocaleCode == doc.code {
                        Label("\(doc.displayName) (\(doc.code.uppercased()))", systemImage: "checkmark")
                    } else {
                        Text("\(doc.displayName) (\(doc.code.uppercased()))")
                    }
                }
            }
        } label: {
            Label(appState.activeLocaleCode.uppercased(), systemImage: "globe")
        }
    }
}
