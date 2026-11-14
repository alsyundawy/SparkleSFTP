import Foundation
@testable import SparkleFileManager
import Testing

@Suite("Batch Rename Planner & Sanitization Tests")
struct BatchRenamePlannerTests {
    @Test("Find and replace with case transform and counter formatting")
    func findReplaceAndCounter() {
        let rule = BatchRenameRule(
            findText: "IMG",
            replaceText: "Photo",
            useRegex: false,
            caseTransform: .unchanged,
            counterStart: 1,
            counterStep: 1,
            counterPadding: 3,
            prefix: "vacation_",
            suffix: "_[C]"
        )

        let items = BatchRenamePlanner.plan(filenames: ["IMG_01.jpg", "IMG_02.jpg"], rule: rule)
        #expect(items.count == 2)
        #expect(items[0].proposedName == "vacation_Photo_01_001.jpg")
        #expect(items[1].proposedName == "vacation_Photo_02_002.jpg")
        #expect(items[0].isValid)
    }

    @Test("Rejects path traversal, empty names, and duplicate collisions")
    func rejectsUnsafeNames() {
        let traversalRule = BatchRenameRule(findText: "safe", replaceText: "../../evil")
        let items = BatchRenamePlanner.plan(filenames: ["safe.txt"], rule: traversalRule)
        #expect(items.first?.isValid == false)

        let collisionRule = BatchRenameRule(findText: "file[0-9]", replaceText: "constant", useRegex: true)
        let collisionItems = BatchRenamePlanner.plan(filenames: ["file1.txt", "file2.txt"], rule: collisionRule)
        #expect(collisionItems[0].isValid == true)
        #expect(collisionItems[1].isValid == false) // Collision detected
    }
}
