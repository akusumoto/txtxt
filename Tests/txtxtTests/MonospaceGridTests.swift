import AppKit
import CoreText
import Testing
@testable import txtxt

struct MonospaceGridTests {
    let grid = MonospaceGrid(fontSize: 12)

    /// Lays out `cells` (each character paired with the columns it should
    /// occupy) after `apply`, and checks every character's glyph is drawn
    /// starting exactly at its column.
    ///
    /// Glyph origins, not caret offsets: Core Text reports the caret
    /// halfway through a character's trailing padding.
    private func expectOnGrid(_ cells: [(String, Int)]) {
        let text = cells.map(\.0).joined()
        let storage = NSTextStorage(string: text, attributes: grid.baseAttributes)
        grid.apply(to: storage, in: NSRange(location: 0, length: storage.length))
        let line = CTLineCreateWithAttributedString(storage)

        var glyphX: [Int: CGFloat] = [:]
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var positions = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetPositions(run, CFRange(), &positions)
            CTRunGetStringIndices(run, CFRange(), &indices)
            for (index, position) in zip(indices, positions) where glyphX[index] == nil {
                glyphX[index] = position.x
            }
        }

        var utf16Offset = 0
        var column = 0
        for (char, columns) in cells {
            let expected = CGFloat(column) * grid.cellWidth
            let x = glyphX[utf16Offset]
            #expect(x.map { abs($0 - expected) < 0.01 } == true, "\(char.debugDescription) drawn at x=\(String(describing: x)), expected \(expected)")
            utf16Offset += char.utf16.count
            column += columns
        }
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        #expect(abs(width - CGFloat(column) * grid.cellWidth) < 0.01, "line is \(width) wide, expected \(column) columns")
    }

    @Test func asciiAndFullwidthShareTheGrid() {
        expectOnGrid([
            ("a", 1), ("a", 1), ("国", 2), ("あ", 2), ("い", 2), ("ア", 2), ("イ", 2),
            ("漢", 2), ("字", 2), ("１", 2), ("２", 2), ("Ａ", 2), ("。", 2), ("a", 1),
        ])
    }

    /// Latin right after Japanese is where the system monospaced font adds
    /// language-aware spacing; see `MonospaceGrid.sfMono`.
    @Test func latinAfterJapaneseStaysOnGrid() {
        expectOnGrid([("国", 2), ("a", 1), ("。", 2), ("1", 1), ("、", 2), ("(", 1), ("あ", 2), (" ", 1), ("x", 1)])
    }

    @Test func halfwidthKatakanaTakesOneColumn() {
        expectOnGrid([("a", 1), ("ｱ", 1), ("ｲ", 1), ("a", 1)])
    }

    @Test func decomposedDakutenTakesTwoColumns() {
        // "か" + COMBINING KATAKANA-HIRAGANA VOICED SOUND MARK, i.e. a "が"
        // that wasn't normalized.
        expectOnGrid([("a", 1), ("\u{304B}\u{3099}", 2), ("a", 1)])
    }

    @Test func fullwidthGlyphsUseLighterHiraginoAtReducedSize() throws {
        let cjkFont = try #require(grid.cjkFont)
        #expect(cjkFont.fontName == "HiraginoSans-W3")
        for char in ["国", "あ", "１"] {
            let (font, _) = grid.attributes(for: char)
            #expect(font == cjkFont, "\(char) should render in Hiragino, not another fallback")
            let fill = MonospaceGrid.advance(of: char, in: cjkFont) / (2 * grid.cellWidth)
            #expect(abs(fill - MonospaceGrid.cjkCellFill) < 0.01, "\(char) fills \(fill) of its cell")
        }
    }

    @Test func baseFontIsRegularSFMono() {
        #expect(grid.baseFont.fontName.contains("SFNSMono"))
        let variation = CTFontCopyVariation(grid.baseFont) as? [Int: Double]
        #expect(variation?[0x7767_6874] == 400)
    }
}
