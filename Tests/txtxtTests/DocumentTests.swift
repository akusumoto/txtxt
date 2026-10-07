import Foundation
import Testing
@testable import txtxt

struct MarkdownRendererTests {
    @Test func rendersGitHubExtensions() {
        let html = MarkdownRenderer.htmlBody(from: """
        # Title

        | a | b |
        |---|---|
        | 1 | 2 |

        ~~gone~~ https://example.com

        - [x] done
        """)
        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<table>"))
        #expect(html.contains("<del>gone</del>"))
        #expect(html.contains("<a href=\"https://example.com\">"))
        #expect(html.contains("type=\"checkbox\""))
    }

    @Test func leavesOutRawHTML() {
        let html = MarkdownRenderer.htmlBody(from: "<script>alert(1)</script>\n\nhi")
        #expect(!html.contains("<script>"))
        #expect(html.contains("<p>hi</p>"))
    }

    @Test func rendersJapanese() {
        #expect(MarkdownRenderer.htmlBody(from: "## 見出し").contains("<h2>見出し</h2>"))
    }
}

struct TextStatsTests {
    @Test(arguments: [
        ("", 1, 0),
        ("a", 1, 1),
        ("a\n", 1, 2),
        ("a\nb", 2, 3),
        ("a\n\n", 2, 3),
        ("ああ\n１", 2, 4),
    ])
    func counts(text: String, lines: Int, characters: Int) {
        let stats = TextStats(text)
        #expect(stats.lines == lines)
        #expect(stats.characters == characters)
    }

    @Test func summaryUsesSingularForOne() {
        #expect(TextStats("a").summary == "1 line, 1 char")
        #expect(TextStats("ab\ncd").summary == "2 lines, 5 chars")
    }
}

struct DocumentTests {
    @Test func detectsMarkdownByExtension() {
        #expect(Document.isMarkdown(URL(fileURLWithPath: "/tmp/a.md")))
        #expect(Document.isMarkdown(URL(fileURLWithPath: "/tmp/a.MARKDOWN")))
        #expect(!Document.isMarkdown(URL(fileURLWithPath: "/tmp/a.txt")))
        #expect(!Document.isMarkdown(URL(fileURLWithPath: "/tmp/md")))
    }
}
