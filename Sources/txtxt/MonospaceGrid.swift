import AppKit
import CoreText

/// Keeps mixed Latin/Japanese text on a strict monospace grid: ASCII takes
/// one column of SF Mono and fullwidth characters take exactly two.
///
/// Font fallback alone doesn't get there — Hiragino's em-wide glyphs come
/// out a bit narrower than two SF Mono columns, and scaling them up to fill
/// the cell makes them look bigger than the Latin text. So fullwidth
/// glyphs are drawn at `cjkCellFill` of their cell, and the slack is added
/// back as trailing `.tracking`.
///
/// `.kern` is pinned to 0 everywhere, which is what turns off the font's
/// own pair kerning: Hiragino kerns kana pairs ("アイ" pulls "ア" in by
/// ~8%), and any non-zero `.kern` would add to that rather than replace it.
struct MonospaceGrid {
    /// How much of its two-column cell a fullwidth glyph fills.
    static let cjkCellFill: CGFloat = 0.9
    /// Line height relative to the fonts' combined ascent + descent
    /// (1.0 = as tight as possible without glyphs touching).
    static let lineSpacing: CGFloat = 1.0

    let baseFont: NSFont
    /// Hiragino Sans W3 sized to `cjkCellFill`. W3 matches SF's regular
    /// stroke weight; W4 reads as bold next to it (especially digits).
    let cjkFont: NSFont?
    let cellWidth: CGFloat
    /// One line height and baseline for every line, fitting both fonts —
    /// otherwise each line takes the metrics of whichever fonts it happens
    /// to contain, so ASCII-only and Japanese lines end up unevenly spaced.
    /// Applied by `GridLayoutManagerDelegate`.
    let lineHeight: CGFloat
    let baselineOffset: CGFloat

    init(fontSize: CGFloat) {
        baseFont = Self.sfMono(size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        cellWidth = Self.advance(of: "M", in: baseFont)

        if let unit = NSFont(name: "HiraginoSans-W3", size: 1) {
            let emAdvance = Self.advance(of: "国", in: unit)
            cjkFont = NSFont(name: "HiraginoSans-W3", size: 2 * cellWidth * Self.cjkCellFill / emAdvance)
        } else {
            cjkFont = nil
        }

        let fonts = [baseFont, cjkFont].compactMap { $0 }
        let ascent = fonts.map(\.ascender).max()!
        let descent = fonts.map { -$0.descender }.max()!
        // Not `NSLayoutManager.defaultLineHeight`: Hiragino declares ~½ em
        // of line gap, which made lines over twice the font size apart.
        lineHeight = ceil((ascent + descent) * Self.lineSpacing)
        // Center the tallest ascent/descent within the line.
        baselineOffset = round((lineHeight - ascent - descent) / 2 + ascent)
    }

    /// SF Mono Regular, loaded from its font file rather than via
    /// `NSFont.monospacedSystemFont`: the system-font version comes with
    /// language-aware spacing that adds ~⅛ em between a Japanese glyph and
    /// the Latin one after it (and ½ em after "。"), which knocks
    /// everything after it off the grid.
    private static func sfMono(size: CGFloat) -> NSFont? {
        let url = URL(fileURLWithPath: "/System/Library/Fonts/SFNSMono.ttf")
        guard let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first else {
            return nil
        }
        // A variable font whose default instance is Light.
        let weightAxis = 0x7767_6874 // 'wght'
        let regular = CTFontDescriptorCreateCopyWithAttributes(
            descriptor,
            [kCTFontVariationAttribute: [weightAxis: 400]] as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(regular, size, nil) as NSFont
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .kern: 0]
    }

    /// Re-applies grid attributes to the paragraphs touching `range`.
    func apply(to storage: NSTextStorage, in range: NSRange) {
        let string = storage.string as NSString
        let paragraphs = string.paragraphRange(for: range)
        // `add`/`remove` rather than `setAttributes`, so attributes AppKit
        // manages itself (e.g. IME marked-text styling) survive.
        storage.addAttributes(baseAttributes, range: paragraphs)
        storage.removeAttribute(.tracking, range: paragraphs)

        string.enumerateSubstrings(in: paragraphs, options: .byComposedCharacterSequences) { sub, subRange, _, _ in
            guard let sub, !sub.allSatisfy(\.isASCII), sub != "\n" else { return }
            let (font, padding) = attributes(for: sub)
            if let font {
                storage.addAttribute(.font, value: font, range: subRange)
            }
            if padding > 0.01 {
                // Over the whole sequence: a base character plus combining
                // dakuten shapes into one glyph, which takes it once.
                storage.addAttribute(.tracking, value: padding, range: subRange)
            }
        }
    }

    /// The font override (`nil` keeps the base font, or lets Core Text
    /// fall back) and trailing padding that puts `sequence` on the grid.
    func attributes(for sequence: String) -> (font: NSFont?, padding: CGFloat) {
        if Self.covers(baseFont, sequence) {
            let width = Self.advance(of: sequence, in: baseFont)
            return (nil, max(0, cellWidth - width))
        }
        let font = cjkFont.flatMap { Self.covers($0, sequence) ? $0 : nil }
        let width = Self.advance(of: sequence, in: font ?? baseFont)
        let target = width > cellWidth * 1.25 ? 2 * cellWidth : cellWidth
        return (font, max(0, target - width))
    }

    /// Typographic width of `string`, including Core Text font fallback
    /// for any glyph `font` lacks.
    static func advance(of string: String, in font: NSFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    static func covers(_ font: NSFont, _ string: String) -> Bool {
        let utf16 = Array(string.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        return CTFontGetGlyphsForCharacters(font, utf16, &glyphs, utf16.count)
    }
}

/// Pins every line fragment to `MonospaceGrid`'s line height and baseline.
final class GridLayoutManagerDelegate: NSObject, NSLayoutManagerDelegate {
    let grid: MonospaceGrid

    init(grid: MonospaceGrid) {
        self.grid = grid
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        lineFragmentRect.pointee.size.height = grid.lineHeight
        lineFragmentUsedRect.pointee.size.height = grid.lineHeight
        baselineOffset.pointee = grid.baselineOffset
        return true
    }
}

extension MonospaceGrid {
    /// A plain-text editor laid out on this grid. TextKit 1, because only
    /// its layout-manager delegate can fix every line's baseline.
    @MainActor
    func makeScrollableTextView(layoutDelegate: GridLayoutManagerDelegate) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView(usingTextLayoutManager: false)
        textView.layoutManager?.delegate = layoutDelegate
        textView.autoresizingMask = .width
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = baseFont
        textView.typingAttributes = baseAttributes
        scrollView.documentView = textView
        return scrollView
    }
}
