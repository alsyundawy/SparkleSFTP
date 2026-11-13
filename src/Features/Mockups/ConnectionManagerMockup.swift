import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// Connection Manager mockup screen with grouped profiles sidebar and detailed inspector card.
public struct ConnectionManagerMockup: View {
    @State private var selectedProfileID: String? = "profile-1"
    @State private var searchText: String = ""

    @Environment(\.sparklePalette) private var palette

    public init() {}

    private var selectedProfile: MockConnectionProfile? {
        MockData.mockProfiles.first { $0.id == selectedProfileID } ?? MockData.mockProfiles.first
    }

    private var groupedProfiles: [String: [MockConnectionProfile]] {
        Dictionary(grouping: MockData.mockProfiles, by: \.groupName)
    }

    public var body: some View {
        let tokens = SparkleSemanticTokens(palette: palette)

        HSplitView {
            // MARK: - Sidebar (~220 pt)

            sidebarView(tokens: tokens)
                .frame(minWidth: 200, idealWidth: SparkleSemanticTokens.sidebarWidth, maxWidth: 260)

            // MARK: - Detail Inspector Card

            detailInspectorView(tokens: tokens)
                .frame(minWidth: 600, maxWidth: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(tokens.windowBackground)
    }

    // MARK: - Sidebar View

    private func sidebarView(tokens: SparkleSemanticTokens) -> some View {
        VStack(spacing: 0) {
            sidebarSearchField(tokens: tokens)
            Divider().overlay(tokens.hairlineBorder)
            sidebarProfileList(tokens: tokens)
            Divider().overlay(tokens.hairlineBorder)
            sidebarBottomToolbar(tokens: tokens)
        }
        .background(tokens.sidebarBackground)
    }

    private func sidebarSearchField(tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(tokens.secondaryText)
            TextField("Search profiles...", text: $searchText)
                .textFieldStyle(.plain)
                .font(SparkleSemanticTokens.bodyFont)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(tokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(tokens.hairlineBorder, lineWidth: 1))
        .padding(SparkleSemanticTokens.spacingSm)
    }

    private func sidebarProfileList(tokens: SparkleSemanticTokens) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(groupedProfiles.keys.sorted(), id: \.self) { groupName in
                    let profiles = groupedProfiles[groupName] ?? []

                    Text(groupName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tokens.tertiaryText)
                        .padding(.horizontal, SparkleSemanticTokens.spacingSm)
                        .padding(.top, 10)
                        .padding(.bottom, 2)

                    ForEach(profiles) { profile in
                        let isSelected = (selectedProfileID == profile.id)
                        sidebarProfileRow(profile: profile, isSelected: isSelected, tokens: tokens)
                    }
                }
            }
            .padding(.horizontal, SparkleSemanticTokens.spacingSm)
            .padding(.vertical, 4)
        }
    }

    private func sidebarProfileRow(
        profile: MockConnectionProfile,
        isSelected: Bool,
        tokens: SparkleSemanticTokens
    ) -> some View {
        Button {
            selectedProfileID = profile.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: profile.protocolType.iconName)
                    .font(.system(size: 10))
                    .sparkleIconContainer(tint: profile.protocolType.badgeTint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name)
                        .font(SparkleSemanticTokens.captionSemiboldFont)
                        .foregroundStyle(isSelected ? tokens.accent : tokens.primaryText)
                        .lineLimit(1)
                    Text(profile.host)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(tokens.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                StatusBadge(
                    title: profile.protocolType.rawValue,
                    iconName: profile.protocolType.iconName,
                    tint: profile.protocolType.badgeTint
                )
            }
            .padding(.horizontal, SparkleSemanticTokens.spacingSm)
            .frame(height: SparkleSemanticTokens.sidebarRowHeight + 6)
            .background(
                RoundedRectangle(cornerRadius: SparkleSemanticTokens.rowCornerRadius, style: .continuous)
                    .fill(isSelected ? tokens.rowSelectionBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func sidebarBottomToolbar(tokens: SparkleSemanticTokens) -> some View {
        HStack {
            Button {} label: {
                Label("New Connection", systemImage: "plus")
                    .font(SparkleSemanticTokens.captionSemiboldFont)
            }
            .buttonStyle(.bordered)
            .tint(tokens.accent)

            Spacer()

            Button {} label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(SparkleSemanticTokens.spacingSm)
        .background(tokens.elevatedHeaderBackground)
    }

    // MARK: - Detail Inspector View

    private func detailInspectorView(tokens: SparkleSemanticTokens) -> some View {
        ConnectionManagerDetailView(profile: selectedProfile, tokens: tokens)
    }
}

// MARK: - Connection Manager Detail View

private struct ConnectionManagerDetailView: View {
    let profile: MockConnectionProfile?
    let tokens: SparkleSemanticTokens

    var body: some View {
        if let profile {
            ScrollView {
                VStack(alignment: .leading, spacing: SparkleSemanticTokens.spacingLg) {
                    profileBannerCard(profile: profile, tokens: tokens)
                    connectionParametersCard(profile: profile, tokens: tokens)
                    hostKeyVerificationCard(tokens: tokens)
                    profileActionsBar()
                }
                .padding(SparkleSemanticTokens.spacingLg)
            }
        } else {
            EmptyStateView(
                iconName: "network.badge.shield.half.filled",
                title: "No Profile Selected",
                description: "Select a server profile from the sidebar to inspect or edit connection settings.",
                actionTitle: "Create Profile",
                action: {}
            )
            .padding(SparkleSemanticTokens.spacingLg)
        }
    }

    private func profileBannerCard(profile: MockConnectionProfile, tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 16) {
            Image(systemName: profile.protocolType.iconName)
                .font(.system(size: 24))
                .frame(width: 48, height: 48)
                .background(profile.protocolType.badgeTint.opacity(0.18))
                .foregroundStyle(profile.protocolType.badgeTint)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(profile.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tokens.primaryText)

                    if profile.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.yellow)
                    }

                    StatusBadge(
                        title: profile.protocolType.rawValue,
                        iconName: profile.protocolType.iconName,
                        tint: profile.protocolType.badgeTint
                    )
                }

                Text("Last connected: \(profile.lastConnected)")
                    .font(SparkleSemanticTokens.captionFont)
                    .foregroundStyle(tokens.secondaryText)
            }

            Spacer()

            Button {} label: {
                Label("Connect Now", systemImage: "bolt.fill")
                    .font(SparkleSemanticTokens.bodyFont)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(tokens.accent)
        }
        .padding(SparkleSemanticTokens.spacingLg)
        .sparkleCardStyle(tokens: tokens)
    }

    private func connectionParametersCard(
        profile: MockConnectionProfile,
        tokens: SparkleSemanticTokens
    ) -> some View {
        let authText = profile.keyPath != nil ? "Public Key (Ed25519)" : "Password (Keychain)"
        let gridCols = [GridItem(.flexible()), GridItem(.flexible())]

        return VStack(alignment: .leading, spacing: 12) {
            Text("Connection Parameters")
                .font(SparkleSemanticTokens.titleFont)
                .foregroundStyle(tokens.primaryText)

            LazyVGrid(columns: gridCols, spacing: 12) {
                detailCell(label: "Host Name", value: profile.host, isMono: true, tokens: tokens)
                detailCell(label: "Port Number", value: "\(profile.port)", isMono: true, tokens: tokens)
                detailCell(label: "Username", value: profile.username, isMono: true, tokens: tokens)
                detailCell(label: "Scheme", value: profile.protocolType.rawValue, isMono: false, tokens: tokens)
                detailCell(label: "Authentication", value: authText, isMono: false, tokens: tokens)
                detailCell(label: "Group Folder", value: profile.groupName, isMono: false, tokens: tokens)
            }
        }
        .padding(SparkleSemanticTokens.spacingLg)
        .sparkleCardStyle(tokens: tokens)
    }

    private func hostKeyVerificationCard(tokens: SparkleSemanticTokens) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Host Key & Fingerprint Verification")
                .font(SparkleSemanticTokens.titleFont)
                .foregroundStyle(tokens.primaryText)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Verified Host Key")
                        .font(SparkleSemanticTokens.captionSemiboldFont)
                        .foregroundStyle(tokens.primaryText)
                    Text("SHA256:4y+L8+rQyN2rF10w9x1eE2+dE1q7m8J3k4L5v6P7r8s (Ed25519 256-bit)")
                        .font(SparkleSemanticTokens.monoFont)
                        .foregroundStyle(tokens.secondaryText)
                }
            }
            .padding(10)
            .background(tokens.windowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(tokens.hairlineBorder, lineWidth: 1))
        }
        .padding(SparkleSemanticTokens.spacingLg)
        .sparkleCardStyle(tokens: tokens)
    }

    private func profileActionsBar() -> some View {
        HStack(spacing: 12) {
            Button {} label: {
                Label("Edit Settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)

            Button {} label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button {} label: {
                Label("Export Profile", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(role: .destructive) {} label: {
                Label("Delete Profile", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.top, 4)
    }

    private func detailCell(label: String, value: String, isMono: Bool, tokens: SparkleSemanticTokens) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(SparkleSemanticTokens.captionFont)
                .foregroundStyle(tokens.tertiaryText)
            Text(value)
                .font(isMono ? SparkleSemanticTokens.monoFont : SparkleSemanticTokens.bodyFont)
                .foregroundStyle(tokens.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tokens.windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(tokens.hairlineBorder, lineWidth: 1))
    }
}

// MARK: - Xcode Previews (1280×800)

#if DEBUG
    struct ConnectionManagerMockup_Previews: PreviewProvider {
        @MainActor
        static var previews: some View {
            Group {
                ConnectionManagerMockup()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultDark)
                    .preferredColorScheme(.dark)
                    .previewDisplayName("Connection Manager Dark (1280×800)")

                ConnectionManagerMockup()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultLight)
                    .preferredColorScheme(.light)
                    .previewDisplayName("Connection Manager Light (1280×800)")
            }
            .frame(width: 1280, height: 800)
        }
    }
#endif
