import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// Dashboard overview and quick launch mockup showcasing system status, favorite connections, and transfer statistics.
public struct DashboardMockup: View {
    @Environment(\.sparklePalette) private var palette

    public init() {}

    public var body: some View {
        let tokens = SparkleSemanticTokens(palette: palette)

        ScrollView {
            VStack(alignment: .leading, spacing: SparkleSemanticTokens.spacingLg) {
                // Header Welcome Banner
                welcomeBanner(tokens: tokens)

                // Metrics Grid
                let gridColumns = Array(repeating: GridItem(.flexible()), count: 4)
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    metricCard(
                        data: MetricData(
                            title: "Active Connections",
                            value: "3",
                            subtitle: "2 SFTP · 1 SCP",
                            icon: "bolt.fill",
                            tint: .blue
                        ),
                        tokens: tokens
                    )
                    metricCard(
                        data: MetricData(
                            title: "Queue Throughput",
                            value: "24.2 MB/s",
                            subtitle: "2 active streams",
                            icon: "speedometer",
                            tint: .green
                        ),
                        tokens: tokens
                    )
                    metricCard(
                        data: MetricData(
                            title: "Session Trust Store",
                            value: "12 Hosts",
                            subtitle: "All keys verified",
                            icon: "checkmark.shield.fill",
                            tint: .teal
                        ),
                        tokens: tokens
                    )
                    metricCard(
                        data: MetricData(
                            title: "Free Remote Space",
                            value: "48.2 GB",
                            subtitle: "40.2% available (/var)",
                            icon: "internaldrive.fill",
                            tint: .purple
                        ),
                        tokens: tokens
                    )
                }

                // Quick Launch Favorites & Active Transfers Row
                HStack(alignment: .top, spacing: SparkleSemanticTokens.spacingMd) {
                    // Quick Launch Favorites
                    favoritesCard(tokens: tokens)
                        .frame(maxWidth: .infinity)

                    // Active Transfers Mini-View
                    activeTransfersCard(tokens: tokens)
                        .frame(maxWidth: .infinity)
                }

                // Recent Sessions & Activity Log Stream
                recentSessionsCard(tokens: tokens)
            }
            .padding(SparkleSemanticTokens.spacingLg)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(tokens.windowBackground)
    }

    // MARK: - Welcome Banner

    private func welcomeBanner(tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .sparkleIconContainer(tint: tokens.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("SparkleSFTP Commander Dashboard")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tokens.primaryText)
                Text("Native macOS dual-pane secure transfers, multi-session tabs, and terminal workspace.")
                    .font(SparkleSemanticTokens.bodyFont)
                    .foregroundStyle(tokens.secondaryText)
            }

            Spacer()

            Button {} label: {
                Label("New Tab", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(tokens.accent)
        }
        .padding(16)
        .sparkleCardStyle(tokens: tokens)
    }

    private struct MetricData {
        let title: String
        let value: String
        let subtitle: String
        let icon: String
        let tint: Color
    }

    // MARK: - Metric Card

    private func metricCard(data: MetricData, tokens: SparkleSemanticTokens) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(data.title)
                    .font(SparkleSemanticTokens.captionFont)
                    .foregroundStyle(tokens.tertiaryText)
                Spacer()
                Image(systemName: data.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(data.tint)
            }

            Text(data.value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(tokens.primaryText)

            Text(data.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(tokens.secondaryText)
        }
        .padding(14)
        .sparkleCardStyle(tokens: tokens)
    }

    // MARK: - Favorites Card

    private func favoritesCard(tokens: SparkleSemanticTokens) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Favorite Servers")
                    .font(SparkleSemanticTokens.titleFont)
                    .foregroundStyle(tokens.primaryText)
                Spacer()
                Button("Manage") {}
                    .buttonStyle(.plain)
                    .font(SparkleSemanticTokens.captionSemiboldFont)
                    .foregroundStyle(tokens.accent)
            }

            VStack(spacing: 6) {
                ForEach(MockData.mockProfiles.prefix(3)) { profile in
                    HStack(spacing: 10) {
                        Image(systemName: profile.protocolType.iconName)
                            .font(.system(size: 12))
                            .sparkleIconContainer(tint: profile.protocolType.badgeTint)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.name)
                                .font(SparkleSemanticTokens.captionSemiboldFont)
                                .foregroundStyle(tokens.primaryText)
                            Text("\(profile.username)@\(profile.host):\(profile.port)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(tokens.secondaryText)
                        }

                        Spacer()

                        Button("Connect") {}
                            .buttonStyle(.bordered)
                            .font(SparkleSemanticTokens.captionFont)
                    }
                    .padding(8)
                    .background(tokens.windowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(tokens.hairlineBorder, lineWidth: 1))
                }
            }
        }
        .padding(16)
        .sparkleCardStyle(tokens: tokens)
    }

    // MARK: - Active Transfers Card

    private func activeTransfersCard(tokens: SparkleSemanticTokens) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active Transfers")
                    .font(SparkleSemanticTokens.titleFont)
                    .foregroundStyle(tokens.primaryText)
                Spacer()
                Button("View All (5)") {}
                    .buttonStyle(.plain)
                    .font(SparkleSemanticTokens.captionSemiboldFont)
                    .foregroundStyle(tokens.accent)
            }

            VStack(spacing: 8) {
                ForEach(MockData.mockTransfers.prefix(2)) { transfer in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(transfer.filename)
                                .font(SparkleSemanticTokens.captionSemiboldFont)
                                .foregroundStyle(tokens.primaryText)
                                .lineLimit(1)
                            Spacer()
                            Text(transfer.formattedSpeed)
                                .font(SparkleSemanticTokens.monoBoldFont)
                                .foregroundStyle(tokens.accent)
                        }

                        ModernProgressBar(fraction: transfer.fraction, tint: transfer.status.badgeTint)

                        HStack {
                            Text("\(Int(transfer.fraction * 100))% · ETA: \(transfer.etaString)")
                                .font(.system(size: 10))
                                .foregroundStyle(tokens.secondaryText)
                            Spacer()
                            Text(transfer.formattedTotalSize)
                                .font(SparkleSemanticTokens.monoFont)
                                .foregroundStyle(tokens.tertiaryText)
                        }
                    }
                    .padding(8)
                    .background(tokens.windowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(tokens.hairlineBorder, lineWidth: 1))
                }
            }
        }
        .padding(16)
        .sparkleCardStyle(tokens: tokens)
    }

    // MARK: - Recent Sessions Card

    private func recentSessionsCard(tokens: SparkleSemanticTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Activity Log")
                .font(SparkleSemanticTokens.titleFont)
                .foregroundStyle(tokens.primaryText)

            VStack(spacing: 4) {
                activityRow(
                    time: "22:28:14",
                    text: "SFTP Download complete: access.log (40.5 MB) from web-01.eu-west.internal",
                    isSuccess: true,
                    tokens: tokens
                )
                activityRow(
                    time: "22:20:00",
                    text: "Collision detected on nginx_access.log: Destination file already exists",
                    isSuccess: false,
                    tokens: tokens
                )
                activityRow(
                    time: "22:15:02",
                    text: "Host key verified for web-01.eu-west.internal (Ed25519 SHA256:4y+L8+rQ...)",
                    isSuccess: true,
                    tokens: tokens
                )
            }
        }
        .padding(16)
        .sparkleCardStyle(tokens: tokens)
    }

    private func activityRow(time: String, text: String, isSuccess: Bool, tokens: SparkleSemanticTokens) -> some View {
        HStack(spacing: 8) {
            Text(time)
                .font(SparkleSemanticTokens.monoFont)
                .foregroundStyle(tokens.tertiaryText)
                .frame(width: 60, alignment: .leading)

            Circle()
                .fill(isSuccess ? Color.green : Color.orange)
                .frame(width: 6, height: 6)

            Text(text)
                .font(SparkleSemanticTokens.captionFont)
                .foregroundStyle(tokens.primaryText)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Xcode Previews (1280×800)

#if DEBUG
    struct DashboardMockup_Previews: PreviewProvider {
        @MainActor
        static var previews: some View {
            Group {
                DashboardMockup()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultDark)
                    .preferredColorScheme(.dark)
                    .previewDisplayName("Dashboard Dark (1280×800)")

                DashboardMockup()
                    .environment(\.sparklePalette, SparkleThemeCatalog.defaultLight)
                    .preferredColorScheme(.light)
                    .previewDisplayName("Dashboard Light (1280×800)")
            }
            .frame(width: 1280, height: 800)
        }
    }
#endif
