import AppKit
import SparkleDesignSystem
import SwiftUI

/// Segment model representing a single folder node along the directory hierarchy.
struct BreadcrumbSegment: Identifiable, Equatable {
    let id: String
    let name: String
    let fullPath: String
    let isLast: Bool
}

/// Interactive breadcrumbs navigation bar allowing instant jump to any parent path segment.
public struct BreadcrumbsBarView: View {
    let currentPath: String
    let isLocal: Bool
    let palette: SparkleThemePalette
    @Binding var isEditingText: Bool
    @Binding var manualPathInput: String
    let onNavigate: (String) -> Void

    public init(
        currentPath: String,
        isLocal: Bool,
        palette: SparkleThemePalette,
        isEditingText: Binding<Bool>,
        manualPathInput: Binding<String>,
        onNavigate: @escaping (String) -> Void
    ) {
        self.currentPath = currentPath
        self.isLocal = isLocal
        self.palette = palette
        self._isEditingText = isEditingText
        self._manualPathInput = manualPathInput
        self.onNavigate = onNavigate
    }

    private var segments: [BreadcrumbSegment] {
        let clean = currentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty && clean != "/" else {
            return [BreadcrumbSegment(id: "/", name: "/", fullPath: "/", isLast: true)]
        }
        let parts = clean.split(separator: "/", omittingEmptySubsequences: true)
        var accumulated = ""
        var list: [BreadcrumbSegment] = [
            BreadcrumbSegment(id: "/", name: "/", fullPath: "/", isLast: parts.isEmpty)
        ]
        for (idx, part) in parts.enumerated() {
            accumulated += "/" + part
            let isLast = idx == parts.count - 1
            list.append(
                BreadcrumbSegment(
                    id: accumulated,
                    name: String(part),
                    fullPath: accumulated,
                    isLast: isLast
                )
            )
        }
        return list
    }

    public var body: some View {
        HStack(spacing: 3) {
            if isEditingText {
                manualInputField
            } else {
                breadcrumbsPillsView
            }
        }
    }

    private var manualInputField: some View {
        HStack(spacing: 4) {
            TextField("Path", text: $manualPathInput)
                .textFieldStyle(.roundedBorder)
                .font(SparkleTheme.Typography.monoSmall)
                .onSubmit {
                    commitManualInput()
                }

            Button {
                commitManualInput()
            } label: {
                Image(systemName: "checkmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Go to path (Return)")

            Button {
                manualPathInput = currentPath
                isEditingText = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Cancel editing")
        }
    }

    private var breadcrumbsPillsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(segments) { seg in
                    segmentButton(seg)
                    if !seg.isLast {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(palette.secondaryTextColor.opacity(0.6))
                    }
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(palette.canvasColor.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(palette.borderColor.opacity(0.5), lineWidth: 1)
        )
        .onTapGesture(count: 2) {
            manualPathInput = currentPath
            isEditingText = true
        }
    }

    private func segmentButton(_ seg: BreadcrumbSegment) -> some View {
        Button {
            onNavigate(seg.fullPath)
        } label: {
            HStack(spacing: 3) {
                if seg.fullPath == "/" {
                    Image(systemName: isLocal ? "internaldrive" : "externaldrive.connected.to.line.below")
                        .font(.system(size: 10))
                }
                Text(seg.name)
                    .font(SparkleTheme.Typography.caption)
                    .fontWeight(seg.isLast ? .semibold : .regular)
                    .foregroundStyle(seg.isLast ? palette.primaryTextColor : palette.secondaryTextColor)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(seg.isLast ? palette.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .help("Jump to \(seg.fullPath)")
        .contextMenu {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(seg.fullPath, forType: .string)
            }
            Button("Edit Path Manually") {
                manualPathInput = seg.fullPath
                isEditingText = true
            }
        }
    }

    private func commitManualInput() {
        let trimmed = manualPathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onNavigate(trimmed)
        }
        isEditingText = false
    }
}
