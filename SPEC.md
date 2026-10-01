# txtxt — Spec

A lightweight, native-feeling plain-text editor for macOS, written in Rust.

## Goals

- **Lightweight**: small binary, fast startup, low memory use. No Electron/webview,
  no bundled browser runtime.
- **Simple UI**: one window, a tab bar, a text area. No project sidebar, no
  plugin system, no themes engine — just editing text.
- **Multi-file**: open several files at once as tabs within a single window.

## Non-goals (v1)

- Syntax highlighting / language servers
- Split panes / multiple windows
- Plugins or extensions
- Rich text editing (formatting toolbars, WYSIWYG) — the one exception is a
  read-only Markdown preview, see below
- Settings UI (a couple of constants in code is enough for now)

These may be revisited later, but are explicitly out of scope for the first
implementation so the app stays small and easy to maintain.

## Tech stack

| Concern            | Choice                                   |
|---------------------|-------------------------------------------|
| Language            | Rust (2024 edition)                       |
| GUI                  | [`egui`](https://github.com/emilk/egui) via [`eframe`](https://docs.rs/eframe) — immediate-mode GUI, pure Rust, no webview |
| Native file dialogs  | [`rfd`](https://docs.rs/rfd) — wraps the native macOS `NSOpenPanel`/`NSSavePanel` |
| Markdown preview     | [`egui_commonmark`](https://docs.rs/egui_commonmark) (CommonMark via `pulldown-cmark`), `load-images`/syntax-highlighting features disabled to keep it light |
| Packaging            | `scripts/bundle-mac.sh` produces `target/release/bundle/macos/txtxt.app` (also copied to `./txtxt.app`), a real bundle with `packaging/Info.plist`. Required for Finder double-click to launch the GUI directly instead of via Terminal.app (a bare Unix executable opens in Terminal when double-clicked). A real macOS menu bar is still a follow-up. |
| Fonts                | System San Francisco (`SFNS.ttf`) for UI text and SF Mono (`SFNSMono.ttf`, falling back to Menlo) for the editor, loaded from `/System/Library/Fonts` at startup for a native, modern look — not bundled, to keep the binary small. Hiragino Sans is layered in as a fallback on both for Japanese glyphs, which `egui`'s built-in fonts don't cover. |
| CJK fallback tuning  | `egui` lays out each fallback font using its own metrics, so a CJK font paired with an unrelated Latin font won't naturally land on a shared baseline (Proportional and Monospace families), or "1 CJK char = 2 ASCII chars" width (Monospace only). `cjk_fallback_tweak()` in `app.rs` computes the correct [`FontTweak`] at startup: `scale` via binary search (against `ab_glyph` advance metrics) so it's exact regardless of the specific rounding `epaint` applies internally, and `baseline_offset_factor` by running the *real* `egui` layout engine once at startup (`calibrate_baseline_offset_factor()`) and solving for the value that closes the measured gap — chosen over hand-deriving every rounding/centering term `epaint` applies internally (`FontImpl::new` in `epaint::text::font`), which turned out easy to get subtly wrong. Verified by `cjk_monospace_alignment`/`cjk_proportional_baseline_alignment` in `app.rs`'s test module, which run the same real layout engine against a range of kanji/hiragana/katakana. Self-corrects if a different font gets picked (e.g. Menlo instead of SF Mono). |

`eframe`/`egui` was chosen over Tauri because it is a single Rust crate with
no JS/web frontend and no bundled webview process — it compiles to one native
binary, which best matches "lightweight."

## Functional requirements

### Tabs & files

- App starts with one empty, untitled tab.
- `File > New Tab` (⌘T) opens another empty, untitled tab.
- `File > Open…` (⌘O) shows a native file picker; the chosen file opens in a
  new tab. Opening the same file twice focuses the existing tab instead of
  duplicating it.
- Files can also be opened by dragging them onto the app / launching via
  `open txtxt file.txt` (CLI args are opened as tabs at startup).
- Each tab shows the file name (or "Untitled") and a `•` marker when the tab
  has unsaved changes.
- Clicking a tab switches to it. A close (`×`) button on each tab, and ⌘W,
  close the active tab. Closing a tab with unsaved changes prompts
  Save / Don't Save / Cancel.
- ⌘S saves the active tab (Save As dialog if it's an untitled tab); ⌘⇧S is
  always Save As.
- Quitting the app with unsaved tabs prompts per-tab, same as closing a tab.

### Editing

- Single scrollable plain-text area per tab, monospace font.
- Standard text editing behavior (selection, copy/paste/cut, undo/redo) comes
  from `egui`'s built-in `TextEdit` widget.
- No line-length limit; large files are handled by `egui`'s `TextEdit`
  (acceptable for a lightweight plain-text tool; very large files, e.g.
  hundreds of MB, are out of scope).
- Tabs for `.md`/`.markdown` files show an **Edit / Preview** toggle (top
  right of the menu bar), and open in Preview by default. Preview replaces
  the whole tab with a read-only rendered view — there is no split view;
  toggling to Edit shows the raw source. Non-markdown tabs never show the
  toggle.
- Line/column indicator and character count in a thin status bar at the
  bottom of the window.

### Window & menus

- One native window, resizable, with the standard macOS title bar.
- A minimal `File` menu (New Tab, Open…, Save, Save As…, Close Tab) rendered
  as an in-window egui menu bar for v1 (a true macOS menu bar is a follow-up
  once packaged as a `.app`).
- Keyboard shortcuts are the primary interaction path; the menu bar mirrors
  them for discoverability.

## Data model (sketch)

```rust
struct Tab {
    path: Option<PathBuf>, // None = untitled, not yet saved
    title: String,         // derived from path, or "Untitled"
    content: String,       // current buffer text
    saved_content: String, // last-saved text, used to detect dirty state
}

struct TxtxtApp {
    tabs: Vec<Tab>,
    active: usize,
    pending_close: Option<PendingClose>, // drives the save-prompt dialog
}
```

Dirty state is `tab.content != tab.saved_content` rather than a separate
bool, so it can never drift out of sync.

## Keyboard shortcuts (v1)

| Shortcut | Action        |
|----------|---------------|
| ⌘N / ⌘T  | New tab       |
| ⌘O       | Open…         |
| ⌘S       | Save          |
| ⌘⇧S      | Save As…      |
| ⌘W       | Close tab     |
| ⌘⌥→ / ⌘⌥←| Next / previous tab |

## File structure

```
txtxt/
├── Cargo.toml
├── SPEC.md
├── packaging/
│   └── Info.plist    # .app bundle metadata
├── scripts/
│   └── bundle-mac.sh # builds target/release/bundle/macos/txtxt.app
└── src/
    ├── main.rs   # entry point, eframe setup, CLI args
    ├── app.rs    # TxtxtApp: state + egui UI + update loop
    └── tab.rs    # Tab struct + load/save helpers
```

## Future enhancements (explicitly deferred)

- App icon and a native macOS menu bar (currently an in-window egui menu).
- Session restore (reopen tabs from last run).
- Basic syntax highlighting for common file types.
- Find/replace within a tab.
- Word wrap toggle, font size setting.
