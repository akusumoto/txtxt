import AppKit

/// Line numbers in the editor's left margin. Lines are counted like the
/// status bar counts them: a wrapped line has one number, on its first row.
final class LineNumberRulerView: NSRulerView {
    private static let padding: CGFloat = 8
    private static let minimumDigits = 3

    private let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    /// The text's baseline within a line fragment, so numbers sit on it.
    private let baselineOffset: CGFloat
    /// UTF-16 offset of each line's first character. Rebuilt lazily after
    /// edits; a trailing newline starts a last (empty) line here, since
    /// that's where the insertion point goes.
    private var cachedLineStarts: [Int]?

    private var textView: NSTextView? { clientView as? NSTextView }

    init(scrollView: NSScrollView, baselineOffset: CGFloat) {
        self.baselineOffset = baselineOffset
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = scrollView.documentView
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
        // Views don't clip to their bounds by default (macOS 14+), so the
        // background fill would paint over the text next to the ruler.
        clipsToBounds = true
        updateThickness()

        // Scrolling, and rewrapping when the window resizes.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(redraw), name: NSView.frameDidChangeNotification, object: scrollView.documentView
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override var requiredThickness: CGFloat { ruleThickness }

    /// Call after every edit.
    func textDidChange() {
        cachedLineStarts = nil
        updateThickness()
        needsDisplay = true
    }

    @objc func redraw() {
        needsDisplay = true
    }

    private var lineStarts: [Int] {
        if let cachedLineStarts { return cachedLineStarts }
        var starts = [0]
        for (offset, unit) in (textView?.string ?? "").utf16.enumerated() where unit == 0x0A { // "\n"
            starts.append(offset + 1)
        }
        cachedLineStarts = starts
        return starts
    }

    /// Index of the line containing UTF-16 offset `location`.
    private func lineIndex(of location: Int) -> Int {
        let starts = lineStarts
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }

    private func updateThickness() {
        let digits = max(Self.minimumDigits, String(lineStarts.count).count)
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        let thickness = ceil(digitWidth * CGFloat(digits) + 2 * Self.padding)
        if ruleThickness != thickness {
            ruleThickness = thickness
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        (textView?.backgroundColor ?? .textBackgroundColor).setFill()
        dirtyRect.fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else {
            return
        }
        let starts = lineStarts
        let currentLine = lineIndex(of: textView.selectedRange().location)
        let containerOrigin = textView.textContainerOrigin

        func drawNumber(ofLine index: Int, fragmentTop: CGFloat) {
            let baseline = convert(NSPoint(x: 0, y: fragmentTop + containerOrigin.y + baselineOffset), from: textView).y
            let label = NSAttributedString(
                string: String(index + 1),
                attributes: [
                    .font: font,
                    .foregroundColor: index == currentLine ? NSColor.secondaryLabelColor : .tertiaryLabelColor,
                ]
            )
            let x = ruleThickness - Self.padding - label.size().width
            label.draw(at: NSPoint(x: x, y: baseline - font.ascender))
        }

        let glyphs = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: container)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, fragmentGlyphs, _ in
            let start = layoutManager.characterIndexForGlyph(at: fragmentGlyphs.location)
            let index = self.lineIndex(of: start)
            // Continuation rows of a wrapped line stay unnumbered.
            guard starts[index] == start else { return }
            drawNumber(ofLine: index, fragmentTop: fragment.minY)
        }
        // The empty last line after a trailing newline (or of an empty
        // document) has no glyphs, only the extra line fragment.
        let extra = layoutManager.extraLineFragmentRect
        if !extra.isEmpty {
            drawNumber(ofLine: starts.count - 1, fragmentTop: extra.minY)
        }
    }
}
