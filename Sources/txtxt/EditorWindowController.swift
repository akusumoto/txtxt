import AppKit
import WebKit

/// One document window (= one native tab): the editor, a Markdown preview
/// over it, and a status bar.
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate,
    NSToolbarDelegate, NSMenuItemValidation, WKNavigationDelegate
{
    static let fontSize: CGFloat = 12

    private let grid: MonospaceGrid
    private let layoutDelegate: GridLayoutManagerDelegate
    private let scrollView: NSScrollView
    private let lineNumbers: LineNumberRulerView
    private var textView: NSTextView { scrollView.documentView as! NSTextView }
    private let preview = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private let statusLabel = NSTextField(labelWithString: "")
    private let modeControl = NSSegmentedControl(
        images: [
            NSImage(systemSymbolName: "pencil", accessibilityDescription: "Edit")!,
            NSImage(systemSymbolName: "eye", accessibilityDescription: "Preview")!,
        ],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private static let modeItem = NSToolbarItem.Identifier("txtxt.mode")

    private var isPreviewing = false {
        didSet { updateMode() }
    }

    private var txtxtDocument: Document? { document as? Document }

    var text: String {
        get { textView.string }
        set {
            guard newValue != textView.string else { return }
            textView.string = newValue
            textDidChange()
        }
    }

    /// What File > Print prints: always the source text.
    var printableView: NSView { textView }

    init() {
        grid = MonospaceGrid(fontSize: Self.fontSize)
        layoutDelegate = GridLayoutManagerDelegate(grid: grid)
        scrollView = grid.makeScrollableTextView(layoutDelegate: layoutDelegate)
        lineNumbers = LineNumberRulerView(scrollView: scrollView, baselineOffset: grid.baselineOffset)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        // txtxt is a single-window app: every document opens as a tab,
        // regardless of the system-wide "Prefer tabs" setting.
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "txtxt.document"
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 480, height: 320)
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true
        windowFrameAutosaveName = "txtxt.document"

        configureTextView()
        buildContent(in: window)
        buildToolbar(in: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var document: AnyObject? {
        didSet {
            guard let txtxtDocument else { return }
            text = txtxtDocument.storedText
            // Existing Markdown files open in Preview.
            isPreviewing = txtxtDocument.isMarkdown
            fileURLDidChange()
        }
    }

    /// Save As can turn a plain-text document into a Markdown one (or back).
    func fileURLDidChange() {
        let isMarkdown = txtxtDocument?.isMarkdown ?? false
        window?.toolbar?.items.first { $0.itemIdentifier == Self.modeItem }?.isHidden = !isMarkdown
        if !isMarkdown && isPreviewing {
            isPreviewing = false
        }
    }

    // MARK: Layout

    private func configureTextView() {
        let textView = textView
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.delegate = self
        textView.textStorage?.delegate = self
        // The ruler is ours; keep NSTextView from managing it.
        textView.usesRuler = false

        scrollView.verticalRulerView = lineNumbers
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
    }

    private func buildContent(in window: NSWindow) {
        preview.navigationDelegate = self
        preview.isHidden = true

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor

        let statusBar = NSVisualEffectView()
        statusBar.material = .titlebar
        statusBar.blendingMode = .withinWindow
        let separator = NSBox()
        separator.boxType = .separator

        let content = NSView()
        for view in [scrollView, preview, separator, statusBar, statusLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        statusBar.addSubview(statusLabel)
        for view in [scrollView, preview, separator, statusBar] as [NSView] {
            content.addSubview(view)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor),

            preview.topAnchor.constraint(equalTo: scrollView.topAnchor),
            preview.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),

            statusLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusBar.trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
        ])
        window.contentView = content
    }

    private func buildToolbar(in window: NSWindow) {
        modeControl.target = self
        modeControl.action = #selector(modeControlChanged(_:))
        modeControl.setToolTip("Edit", forSegment: 0)
        modeControl.setToolTip("Preview", forSegment: 1)

        let toolbar = NSToolbar(identifier: "txtxt.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.modeItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.modeItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Mode"
        item.toolTip = "Switch between editing and the rendered preview"
        item.view = modeControl
        item.isHidden = !(txtxtDocument?.isMarkdown ?? false)
        return item
    }

    // MARK: Preview

    @objc func togglePreview(_ sender: Any?) {
        isPreviewing.toggle()
    }

    @objc private func modeControlChanged(_ sender: NSSegmentedControl) {
        isPreviewing = sender.selectedSegment == 1
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(togglePreview(_:)) {
            menuItem.state = isPreviewing ? .on : .off
            return txtxtDocument?.isMarkdown ?? false
        }
        return true
    }

    private func updateMode() {
        modeControl.selectedSegment = isPreviewing ? 1 : 0
        preview.isHidden = !isPreviewing
        if isPreviewing {
            preview.loadHTMLString(MarkdownRenderer.page(from: text), baseURL: txtxtDocument?.fileURL?.deletingLastPathComponent())
            window?.makeFirstResponder(preview)
        } else {
            window?.makeFirstResponder(textView)
        }
    }

    /// Links open in the browser rather than replacing the preview.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
            return .allow
        }
        NSWorkspace.shared.open(url)
        return .cancel
    }

    // MARK: Editing

    /// Route the text view's undo actions to the document's undo manager,
    /// which is what marks the document as edited (and lets Revert clear
    /// them).
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        txtxtDocument?.undoManager
    }

    func textDidChange(_ notification: Notification) {
        textDidChange()
    }

    private func textDidChange() {
        statusLabel.stringValue = TextStats(textView.string).summary
        lineNumbers.textDidChange()
    }

    /// Highlights the current line's number.
    func textViewDidChangeSelection(_ notification: Notification) {
        lineNumbers.redraw()
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // Attribute-only edits too: while composing with an IME, AppKit
        // follows each marked-text change with one that resets the font to
        // the typing attributes, which would leave the marked text in the
        // smaller fallback font until it's committed.
        grid.apply(to: textStorage, in: editedRange)
    }
}

/// The status bar's counts.
struct TextStats {
    let lines: Int
    let characters: Int

    init(_ text: String) {
        // Like most editors, a trailing newline doesn't start another line.
        let newlines = text.utf8.reduce(0) { $0 + ($1 == UInt8(ascii: "\n") ? 1 : 0) }
        lines = max(1, newlines + (text.isEmpty || text.hasSuffix("\n") ? 0 : 1))
        characters = text.count
    }

    var summary: String {
        "\(lines) \(lines == 1 ? "line" : "lines"), \(characters) \(characters == 1 ? "char" : "chars")"
    }
}

