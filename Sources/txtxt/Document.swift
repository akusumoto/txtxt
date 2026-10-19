import AppKit

/// A UTF-8 plain-text file. While a window is open, its text view is the
/// source of truth; `storedText` only holds what was last read from disk.
///
/// Edits mark the document as edited through its undo manager, which the
/// text view registers with (see `EditorWindowController`).
@objc(TxtxtDocument)
final class Document: NSDocument {
    private(set) var storedText = ""

    var editor: EditorWindowController? {
        windowControllers.first as? EditorWindowController
    }

    var text: String {
        editor?.text ?? storedText
    }

    var isMarkdown: Bool {
        fileURL.map { Self.isMarkdown($0) } ?? false
    }

    nonisolated static func isMarkdown(_ url: URL) -> Bool {
        ["md", "markdown"].contains(url.pathExtension.lowercased())
    }

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        addWindowController(EditorWindowController())
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding, userInfo: [
                NSStringEncodingErrorKey: String.Encoding.utf8.rawValue,
            ])
        }
        // Only called off the main thread with `canConcurrentlyReadDocuments`,
        // which we don't opt into.
        MainActor.assumeIsolated {
            storedText = text
            // Revert To Saved / external changes reload into an open window.
            editor?.text = text
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(text.utf8)
    }

    // MARK: External changes

    /// Reload silently when another process rewrites the file, as long as
    /// there are no unsaved edits. With edits, AppKit's usual prompt decides.
    override func presentedItemDidChange() {
        DispatchQueue.main.async { [self] in
            guard !isDocumentEdited, let url = fileURL, let type = fileType,
                  let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            else {
                forwardPresentedItemDidChange()
                return
            }
            if let known = fileModificationDate, modified <= known { return }
            do {
                try revert(toContentsOf: url, ofType: type)
            } catch {
                presentError(error)
            }
        }
    }

    private func forwardPresentedItemDidChange() {
        super.presentedItemDidChange()
    }

    override var fileURL: URL? {
        // Only ever set on the main thread, since we don't opt into
        // asynchronous saving (`canAsynchronouslyWrite`).
        didSet { MainActor.assumeIsolated { editor?.fileURLDidChange() } }
    }

    // MARK: Saving as any extension

    /// The document types in Info.plist only matter for opening; what we
    /// write is the same bytes either way. So don't offer a format popup,
    /// and accept whatever extension the user types (`notes.md`, `.env`,
    /// `Makefile`, …) instead of forcing `.txt`.
    override var shouldRunSavePanelWithAccessoryView: Bool { false }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.allowedContentTypes = []
        savePanel.allowsOtherFileTypes = true
        return true
    }

    // MARK: Printing

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let view = editor?.printableView else {
            throw CocoaError(.featureUnsupported)
        }
        return NSPrintOperation(view: view, printInfo: printInfo)
    }
}
