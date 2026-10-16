# txtxt — Spec

A plain-text editor for macOS that looks and behaves like a native Mac app,
written in Swift on AppKit.

## Goals

- **Native**: real macOS menu bar, native window tabs, standard document
  behavior (autosave, Revert, Open Recent, Rename/Move), native IME and
  find bar — all from AppKit rather than reimplemented.
- **Simple UI**: one window, tabs, a text area, a status bar. No project
  sidebar, no plugin system, no themes engine.
- **Japanese-friendly monospace**: mixed Latin/Japanese text stays on a
  strict grid (see [CJK grid](#cjk-grid)).
- **Small**: system frameworks only, plus `cmark-gfm` for Markdown; the
  app bundle is under 1 MB.

## Non-goals (for now)

- Syntax highlighting / language servers
- Split panes
- Plugins or extensions
- Rich text editing — the one exception is a read-only Markdown preview
- Settings UI (a couple of constants in code is enough for now)

## Tech stack

| Concern | Choice |
|---|---|
| Language | Swift 6 (strict concurrency), Swift Package Manager |
| UI | AppKit: `NSDocument` + `NSWindowController` + `NSTextView` (TextKit 1). Not SwiftUI: on the macOS 27 SDK, SwiftUI needs the `SwiftUIMacros` compiler plugin, which ships only with full Xcode, and this project builds with just the Command Line Tools. |
| Markdown preview | [`swift-cmark`](https://github.com/swiftlang/swift-cmark) (cmark-gfm: tables, strikethrough, autolinks, task lists) → HTML in a `WKWebView`, GitHub-like CSS that follows light/dark mode. Raw HTML in the source is not rendered. |
| Fonts | SF Mono Regular (loaded from `SFNSMono.ttf`, see below) for the editor; Hiragino Sans W3 for Japanese. |
| Packaging | `scripts/bundle-mac.sh` builds `./txtxt.app` (ad-hoc signed) with `packaging/Info.plist`, which declares the document types `NSDocument` needs. |
| Tests | Swift Testing (`Tests/txtxtTests`). |

## Functional requirements

### Documents & tabs

- Each document is an `NSDocument` (`Document`, UTF-8 plain text) with one
  window; every document window opens as a **native tab** of the existing
  window (`tabbingMode = .preferred`, regardless of the system-wide tab
  preference).
- New (⌘N) and New Tab (⌘T, also the tab bar's `+`) open an untitled
  document. Open… (⌘O), Open Recent, Finder "Open With", dropping files on
  the Dock icon, and `open -a txtxt.app file…` all open files as tabs.
  Opening an already-open file focuses its tab.
- Any file opens (plain text, Markdown, source code, files with no
  recognized type such as `Makefile`); files that aren't valid UTF-8 fail
  to open with an error.
- **Autosave in place** (like TextEdit): edits are saved automatically, and
  the title bar shows "Edited" until then. File > Revert To Saved, Rename,
  Move To, Duplicate and the version browser come from `NSDocument`.
  Closing an untitled document with content asks whether to save it.
- Save As accepts any extension the user types (`notes.md`, `.env`, …);
  there's no file-format popup since every type is written the same way.
- Session restore: windows and tabs reopen on relaunch (AppKit state
  restoration).

### Editing

- One scrollable plain-text `NSTextView` per tab, SF Mono 12 pt.
- View > Zoom In / Zoom Out (⇧⌘+ / ⌘−) change the font size 1 pt at a
  time, between 8 and 48 pt, for the current tab only (not saved). The grid,
  line numbers and Markdown preview scale along.
- Native selection, undo/redo, IME (including inline Japanese
  composition), find bar (⌘F / ⌥⌘F), Print. Smart quotes/dashes, text
  replacement and spelling autocorrect are off.
- Undo goes through the document's undo manager, which is what marks the
  document edited.
- Markdown files (`.md`, `.markdown`) get an **Edit / Preview** segmented
  control in the toolbar (and View > Markdown Preview, ⌥⌘P), and open in
  Preview. The preview covers the editor (the editor stays alive
  underneath, so undo history survives toggling). Links in the preview open
  in the default browser. The control appears/disappears when Save As
  changes the file to/from Markdown.
- Line numbers in the left margin (an `NSRulerView`); a wrapped line has
  one number, and the current line's number is emphasized.
- Status bar: line and character count.

### CJK grid

`MonospaceGrid` keeps every character on a monospace grid: ASCII takes one
SF Mono column, fullwidth characters exactly two, halfwidth katakana one.
Verified by `MonospaceGridTests`, which lay text out with Core Text and
check every glyph's origin.

- Fullwidth glyphs are drawn at 90% of their two-column cell
  (`cjkCellFill`), so they don't look bigger than the Latin text; the rest
  is added back as trailing `.tracking`.
- `.kern` is pinned to 0, which disables Hiragino's pair kerning (it pulls
  kana pairs like "アイ" together; any non-zero `.kern` adds to that instead
  of replacing it).
- SF Mono is loaded from its font file at weight 400, not via
  `NSFont.monospacedSystemFont`: the system-font version adds
  language-aware spacing after Japanese glyphs (~⅛ em before Latin, ½ em
  after "。"), which breaks the grid.
- Hiragino W3, not W4: W4 (especially fullwidth digits) looks bold next to
  SF Mono Regular.
- Every line gets the same height and baseline (a `NSLayoutManager`
  delegate), so ASCII-only and Japanese lines are evenly spaced. That's
  the reason for TextKit 1.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘N / ⌘T | New document / new tab |
| ⌘O | Open… |
| ⌘S | Save… |
| ⌘⇧S | Save As… |
| ⌘W | Close tab |
| ⌘⌥→ / ⌘⌥← | Next / previous tab (also ⌃Tab / ⌃⇧Tab) |
| ⌥⌘P | Toggle Markdown preview |
| ⇧⌘+ / ⌘− | Zoom in / out |
| ⌘F / ⌥⌘F | Find / Find and Replace |
| ⌘P / ⌘⇧P | Print / Page Setup |

## Building

```sh
./scripts/bundle-mac.sh   # → ./txtxt.app
```

Tests (Swift Testing's macro plugin path has to be passed explicitly with
the Command Line Tools):

```sh
swift test -Xswiftc -plugin-path \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

If `swift build`/`swift test` fail with "Invalid manifest" (undefined
`PackageDescription.Package.__allocating_init`), the Command Line Tools
contain stale `*.private.swiftinterface` files from an older install.
Remove them (`sudo rm
/Library/Developer/CommandLineTools/usr/lib/swift/pm/*/*.swiftmodule/*.private.swiftinterface`)
or reinstall the Command Line Tools. `bundle-mac.sh` works around it
automatically.

## File structure

```
txtxt/
├── Package.swift
├── SPEC.md
├── packaging/
│   └── Info.plist              # bundle metadata + document types
├── scripts/
│   └── bundle-mac.sh           # builds ./txtxt.app
├── Sources/txtxt/
│   ├── main.swift              # NSApplication entry point
│   ├── AppDelegate.swift       # app delegate + menu bar
│   ├── Document.swift          # NSDocument: load/save, Markdown detection
│   ├── EditorWindowController.swift  # window: editor, preview, toolbar, status bar
│   ├── MonospaceGrid.swift     # CJK grid fonts/attributes + text view factory
│   └── MarkdownRenderer.swift  # cmark-gfm → HTML page
└── Tests/txtxtTests/
```

## Future enhancements

- App icon.
- Syntax highlighting for common file types.
- Word wrap toggle, a persistent font size setting.
- Live-updating preview / split view.
- Local images in the Markdown preview (`WKWebView` can't read files next
  to the document yet).
