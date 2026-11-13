import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

// MARK: - Contrast Inspector Panel

struct ContrastInspectorPanel: View {
    let palette: SparkleThemePalette
    let tokens: SparkleSemanticTokens

    var body: some View {
        let ratio = palette.primaryContrastRatio
        let passesAA = palette.meetsWCAGAA
        let passesAAA = ratio >= 7.0

        return ScrollView {
            VStack(alignment: .leading, spacing: SparkleSemanticTokens.spacingLg) {
                headerSection
                scoreSection(ratio: ratio, passesAA: passesAA, passesAAA: passesAAA)
                swatchesSection
                actionButtons
            }
            .padding(SparkleSemanticTokens.spacingMd)
        }
        .background(tokens.sidebarBackground)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WCAG 2.1 Contrast Inspector")
                .font(SparkleSemanticTokens.titleFont)
                .foregroundStyle(tokens.primaryText)
            Text("Evaluating \(palette.displayName)")
                .font(SparkleSemanticTokens.captionFont)
                .foregroundStyle(tokens.secondaryText)
        }
    }

    private func scoreSection(ratio: Double, passesAA: Bool, passesAAA: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: "%.2f : 1", ratio))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(passesAA ? Color.green : Color.orange)
                Spacer()
                StatusBadge(
                    title: passesAAA ? "WCAG AAA" : (passesAA ? "WCAG AA" : "LOW CONTRAST"),
                    iconName: passesAA ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                    tint: passesAA ? .green : .orange
                )
            }

            ModernProgressBar(
                fraction: min(1.0, ratio / 12.0),
                tint: passesAA ? .green : .orange,
                trackTint: tokens.hairlineBorder
            )

            Text("Primary text vs. canvas luminance contrast ratio.")
                .font(.system(size: 10))
                .foregroundStyle(tokens.tertiaryText)
        }
        .padding(12)
        .sparkleCardStyle(tokens: tokens)
    }

    private var swatchesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Semantic Color Tokens")
                .font(SparkleSemanticTokens.captionSemiboldFont)
                .foregroundStyle(tokens.secondaryText)

            swatchRow(name: "Window Surface", color: palette.windowColor, hex: palette.windowHex)
            swatchRow(name: "Card Canvas", color: palette.canvasColor, hex: palette.canvasHex)
            swatchRow(name: "Primary Accent", color: palette.accentColor, hex: palette.accentHex)
            swatchRow(name: "Primary Text", color: palette.primaryTextColor, hex: palette.primaryTextHex)
            swatchRow(name: "Secondary Text", color: palette.secondaryTextColor, hex: palette.secondaryTextHex)
        }
        .padding(12)
        .sparkleCardStyle(tokens: tokens)
    }

    private func swatchRow(name: String, color: Color, hex: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 20, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(tokens.hairlineBorder, lineWidth: 1))

            Text(name)
                .font(SparkleSemanticTokens.captionFont)
                .foregroundStyle(tokens.primaryText)

            Spacer()

            Text(hex.uppercased())
                .font(SparkleSemanticTokens.monoFont)
                .foregroundStyle(tokens.secondaryText)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {} label: {
                Label("Import JSON", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {} label: {
                Label("Apply Theme", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(tokens.accent)
        }
    }
}
