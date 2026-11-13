import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// Modern, sleek 4 pt progress bar with smooth rounded caps and accent fill.
public struct ModernProgressBar: View {
    public let fraction: Double
    public let tint: Color
    public let trackTint: Color?

    public init(
        fraction: Double,
        tint: Color = .blue,
        trackTint: Color? = nil
    ) {
        self.fraction = min(1.0, max(0.0, fraction))
        self.tint = tint
        self.trackTint = trackTint
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background Track
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(trackTint ?? tint.opacity(0.18))
                    .frame(height: 4)

                // Foreground Progress Fill
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: max(0, geometry.size.width * CGFloat(fraction)), height: 4)
            }
        }
        .frame(height: 4)
    }
}
