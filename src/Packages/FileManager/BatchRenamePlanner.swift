import Foundation

/// Case transformation modes for batch rename.
public enum RenameCaseTransform: String, Sendable, CaseIterable {
    case unchanged
    case lowercase
    case uppercase
    case capitalized
}

/// Parameters configuring find/replace, case formatting, and counter insertion.
public struct BatchRenameRule: Sendable, Equatable {
    public var findText: String
    public var replaceText: String
    public var useRegex: Bool
    public var caseTransform: RenameCaseTransform
    public var counterStart: Int
    public var counterStep: Int
    public var counterPadding: Int
    public var prefix: String
    public var suffix: String

    public init(
        findText: String = "",
        replaceText: String = "",
        useRegex: Bool = false,
        caseTransform: RenameCaseTransform = .unchanged,
        counterStart: Int = 1,
        counterStep: Int = 1,
        counterPadding: Int = 1,
        prefix: String = "",
        suffix: String = ""
    ) {
        self.findText = findText
        self.replaceText = replaceText
        self.useRegex = useRegex
        self.caseTransform = caseTransform
        self.counterStart = max(0, counterStart)
        self.counterStep = max(1, counterStep)
        self.counterPadding = max(1, min(6, counterPadding))
        self.prefix = prefix
        self.suffix = suffix
    }
}

/// Preview of a single planned rename operation.
public struct RenamePreviewItem: Identifiable, Sendable, Equatable {
    public var id: String {
        originalName
    }

    public let originalName: String
    public let proposedName: String
    public let isValid: Bool
    public let errorReason: String?

    public init(
        originalName: String,
        proposedName: String,
        isValid: Bool = true,
        errorReason: String? = nil
    ) {
        self.originalName = originalName
        self.proposedName = proposedName
        self.isValid = isValid
        self.errorReason = errorReason
    }
}

/// Pure rule engine computing planned rename transformations (CWE-22 / CWE-78).
public enum BatchRenamePlanner {
    public static func plan(
        filenames: [String],
        rule: BatchRenameRule,
        existingNames: Set<String> = []
    ) -> [RenamePreviewItem] {
        var results: [RenamePreviewItem] = []
        results.reserveCapacity(filenames.count)

        var plannedNames = Set<String>()
        var counter = rule.counterStart

        for name in filenames {
            let transformed = applyTransform(name: name, rule: rule, counter: counter)
            counter += rule.counterStep

            let validation = validateProposedName(
                transformed: transformed,
                original: name,
                plannedNames: &plannedNames,
                existingNames: existingNames
            )

            results.append(
                RenamePreviewItem(
                    originalName: name,
                    proposedName: transformed,
                    isValid: validation.isValid,
                    errorReason: validation.errorReason
                )
            )
        }
        return results
    }

    private static func applyTransform(name: String, rule: BatchRenameRule, counter: Int) -> String {
        var base = name
        let ext = (name as NSString).pathExtension
        let nameWithoutExt = ext.isEmpty ? name : (name as NSString).deletingPathExtension

        var target = nameWithoutExt
        if !rule.findText.isEmpty {
            if rule.useRegex, let regex = try? NSRegularExpression(pattern: rule.findText) {
                let range = NSRange(target.startIndex..., in: target)
                target = regex.stringByReplacingMatches(in: target, range: range, withTemplate: rule.replaceText)
            } else {
                target = target.replacingOccurrences(of: rule.findText, with: rule.replaceText)
            }
        }

        switch rule.caseTransform {
        case .lowercase: target = target.lowercased()
        case .uppercase: target = target.uppercased()
        case .capitalized: target = target.capitalized
        case .unchanged: break
        }

        if !rule.prefix.isEmpty {
            target = rule.prefix + target
        }
        if !rule.suffix.isEmpty {
            target += rule.suffix
        }

        let counterStr = String(format: "%0\(rule.counterPadding)d", counter)
        target = target.replacingOccurrences(of: "[C]", with: counterStr)

        if !ext.isEmpty {
            base = "\(target).\(ext)"
        } else {
            base = target
        }
        return base
    }

    private static func validateProposedName(
        transformed: String,
        original: String,
        plannedNames: inout Set<String>,
        existingNames: Set<String>
    ) -> (isValid: Bool, errorReason: String?) {
        if transformed.isEmpty {
            return (false, "Filename cannot be empty")
        }
        if transformed.contains("/") || transformed.contains("\0") || transformed == "." || transformed == ".." {
            return (false, "Illegal path characters or directory traversal")
        }
        if plannedNames.contains(transformed) {
            return (false, "Collision with another planned item")
        }
        if transformed != original, existingNames.contains(transformed) {
            return (false, "File with this name already exists in directory")
        }
        plannedNames.insert(transformed)
        return (true, nil)
    }
}
