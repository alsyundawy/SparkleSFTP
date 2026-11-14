import SparkleDesignSystem
import SwiftUI

public enum PasswordStrengthLevel: Int, CaseIterable, Sendable {
    case empty = 0
    case weak = 1
    case fair = 2
    case good = 3
    case strong = 4

    public var title: String {
        switch self {
        case .empty: return ""
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .good: return "Good"
        case .strong: return "Strong"
        }
    }

    public var color: Color {
        switch self {
        case .empty: return .clear
        case .weak: return SparkleTheme.Colors.danger
        case .fair: return SparkleTheme.Colors.warning
        case .good: return .blue
        case .strong: return SparkleTheme.Colors.success
        }
    }

    public static func evaluate(_ string: String) -> PasswordStrengthLevel {
        if string.isEmpty {
            return .empty
        }
        if string.count < 8 {
            return .weak
        }

        var score = 0
        if string.count >= 12 {
            score += 1
        }
        if string.count >= 16 {
            score += 1
        }

        let hasLower = string.contains(where: \.isLowercase)
        let hasUpper = string.contains(where: \.isUppercase)
        let hasDigit = string.contains(where: \.isNumber)
        let hasSymbol = string.contains(where: { !$0.isLetter && !$0.isNumber })

        let classes = [hasLower, hasUpper, hasDigit, hasSymbol].filter(\.self).count
        if classes >= 3 {
            score += 1
        }
        if classes == 4 {
            score += 1
        }

        switch score {
        case 0, 1: return .weak
        case 2: return .fair
        case 3: return .good
        default: return .strong
        }
    }
}

public struct PasswordStrengthMeter: View {
    let level: PasswordStrengthLevel

    public init(level: PasswordStrengthLevel) {
        self.level = level
    }

    public var body: some View {
        if level != .empty {
            HStack(spacing: 4) {
                ForEach(1 ... 4, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(step <= level.rawValue ? level.color : SparkleTheme.Colors.subtleBorder)
                        .frame(height: 4)
                }
                Text(level.title)
                    .font(SparkleTheme.Typography.caption)
                    .foregroundStyle(level.color)
                    .padding(.leading, 4)
            }
        }
    }
}
