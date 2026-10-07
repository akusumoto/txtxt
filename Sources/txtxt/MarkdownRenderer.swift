import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// GitHub-flavored Markdown → a standalone HTML page for the preview.
enum MarkdownRenderer {
    private static let extensions = ["table", "strikethrough", "autolink", "tasklist"]

    /// Raw HTML in the source is left out (cmark's safe default), since
    /// the preview should never run arbitrary markup from a file.
    static func htmlBody(from markdown: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()
        guard let parser = cmark_parser_new(CMARK_OPT_DEFAULT) else { return "" }
        defer { cmark_parser_free(parser) }
        for name in extensions {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }
        cmark_parser_feed(parser, markdown, markdown.utf8.count)
        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }
        guard let html = cmark_render_html(document, CMARK_OPT_DEFAULT, cmark_parser_get_syntax_extensions(parser)) else {
            return ""
        }
        defer { free(html) }
        return String(cString: html)
    }

    static func page(from markdown: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src * data:; style-src 'unsafe-inline'">
        <style>\(css)</style>
        </head><body><article>\(htmlBody(from: markdown))</article></body></html>
        """
    }

    /// GitHub-like styling that follows the system appearance.
    private static let css = """
    :root {
      color-scheme: light dark;
      --fg: #1f2328; --muted: #59636e; --border: #d1d9e0; --subtle: #f6f8fa;
      --link: #0969da; --code-bg: rgba(129,139,152,.12);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --fg: #f0f6fc; --muted: #9198a1; --border: #3d444d; --subtle: #151b23;
        --link: #4493f8; --code-bg: rgba(101,108,118,.2);
      }
    }
    html { background: Canvas; }
    body {
      margin: 0; color: var(--fg);
      font: 15px/1.6 -apple-system, "Hiragino Sans", sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    article { max-width: 820px; margin: 0 auto; padding: 28px 36px 48px; }
    h1, h2, h3, h4, h5, h6 { margin: 1.5em 0 .6em; line-height: 1.25; font-weight: 600; }
    h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
    h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
    h3 { font-size: 1.25em; }
    article > :first-child { margin-top: 0; }
    p, ul, ol, blockquote, pre, table { margin: 0 0 1em; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    code, pre { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 85%; }
    code { background: var(--code-bg); padding: .2em .4em; border-radius: 6px; }
    pre { background: var(--subtle); padding: 14px 16px; border-radius: 8px; overflow: auto; line-height: 1.45; }
    pre code { background: none; padding: 0; font-size: 100%; }
    blockquote { color: var(--muted); border-left: .25em solid var(--border); padding: 0 1em; margin-left: 0; }
    hr { border: 0; height: 1px; background: var(--border); margin: 1.5em 0; }
    table { border-collapse: collapse; display: block; overflow: auto; }
    th, td { border: 1px solid var(--border); padding: 6px 13px; }
    th { font-weight: 600; background: var(--subtle); }
    img { max-width: 100%; }
    /* cmark-gfm emits bare checkboxes, without GitHub's task-list classes. */
    li:has(> input[type=checkbox]) { list-style: none; }
    li > input[type=checkbox] { margin: 0 .4em 0 -1.3em; vertical-align: middle; }
    """
}
