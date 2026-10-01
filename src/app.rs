use std::path::PathBuf;
use std::sync::Arc;

use eframe::egui;
use egui_commonmark::{CommonMarkCache, CommonMarkViewer};

use crate::tab::Tab;

/// System UI font (San Francisco) for a native, modern look. Loaded from
/// disk at runtime rather than bundled, to keep the binary small.
const UI_FONT_CANDIDATES: &[&str] = &["/System/Library/Fonts/SFNS.ttf"];

/// System monospace font (SF Mono, falling back to Menlo) for the editor.
const MONO_FONT_CANDIDATES: &[&str] = &["/System/Library/Fonts/SFNSMono.ttf", "/System/Library/Fonts/Menlo.ttc"];

/// System fonts (in priority order) that cover Japanese glyphs. `egui`
/// ships only Latin glyphs by default, so without one of these, CJK text
/// renders as tofu boxes.
const JAPANESE_FONT_CANDIDATES: &[&str] = &[
    "/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc",
    "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
];

/// A representative fullwidth ideograph, used to measure a CJK font's glyph
/// advance width relative to its em square.
const CJK_REFERENCE_CHAR: char = '国';

pub fn setup_fonts(ctx: &egui::Context) {
    ctx.set_fonts(build_font_definitions());
}

fn build_font_definitions() -> egui::FontDefinitions {
    let mut fonts = egui::FontDefinitions::default();

    let ui = load_first(UI_FONT_CANDIDATES);
    if let Some(bytes) = ui.clone() {
        insert_primary_font(&mut fonts, "system-ui", bytes, egui::FontTweak::default(), &[
            egui::FontFamily::Proportional,
        ]);
    }

    let mono = load_first(MONO_FONT_CANDIDATES);
    if let Some(bytes) = mono.clone() {
        insert_primary_font(&mut fonts, "system-mono", bytes, egui::FontTweak::default(), &[
            egui::FontFamily::Monospace,
        ]);
    }

    if let Some(bytes) = load_first(JAPANESE_FONT_CANDIDATES) {
        // `egui` lays out each fallback font using *its own* metrics, so
        // pairing a CJK font (fullwidth glyphs) with an unrelated Latin
        // font never lands on a shared baseline by accident — this applies
        // to prose (UI font) just as much as to the monospace editor.
        // Compute the correction from the two fonts' actual metrics rather
        // than hard-coding it, so it stays correct if a different system
        // font gets picked (e.g. Menlo instead of SF Mono on an older
        // macOS).
        let ui_tweak = ui.as_deref().and_then(|ui_bytes| cjk_fallback_tweak(ui_bytes, &bytes, false)).unwrap_or_default();
        push_fallback_font(&mut fonts, "system-japanese-ui", bytes.clone(), ui_tweak, &[egui::FontFamily::Proportional]);

        // The editor additionally needs "1 CJK char = 2 ASCII chars" width,
        // which only makes sense for a monospace grid.
        let mono_tweak =
            mono.as_deref().and_then(|mono_bytes| cjk_fallback_tweak(mono_bytes, &bytes, true)).unwrap_or_default();
        push_fallback_font(&mut fonts, "system-japanese-mono", bytes, mono_tweak, &[egui::FontFamily::Monospace]);
    }

    fonts
}

fn load_first(paths: &[&str]) -> Option<Vec<u8>> {
    paths.iter().find_map(|path| std::fs::read(path).ok())
}

/// Makes `name` the first-choice font for `families` (ahead of egui's
/// built-in defaults).
fn insert_primary_font(
    fonts: &mut egui::FontDefinitions,
    name: &str,
    bytes: Vec<u8>,
    tweak: egui::FontTweak,
    families: &[egui::FontFamily],
) {
    fonts
        .font_data
        .insert(name.to_owned(), Arc::new(egui::FontData::from_owned(bytes).tweak(tweak)));
    for family in families {
        fonts.families.entry(family.clone()).or_default().insert(0, name.to_owned());
    }
}

/// Adds `name` as a last-resort fallback for `families` (used for glyphs
/// the primary font doesn't cover, e.g. CJK).
fn push_fallback_font(
    fonts: &mut egui::FontDefinitions,
    name: &str,
    bytes: Vec<u8>,
    tweak: egui::FontTweak,
    families: &[egui::FontFamily],
) {
    fonts
        .font_data
        .insert(name.to_owned(), Arc::new(egui::FontData::from_owned(bytes).tweak(tweak)));
    for family in families {
        fonts.families.entry(family.clone()).or_default().push(name.to_owned());
    }
}

fn advance(font: &ab_glyph::FontRef<'_>, scale_in_points: f32, tweak_scale: f32, ch: char) -> Option<f32> {
    use ab_glyph::{Font as _, ScaleFont as _};
    let glyph = font.glyph_id(ch);
    if glyph.0 == 0 {
        return None; // Font doesn't contain this character.
    }
    let font_scaling = font.height_unscaled() / font.units_per_em().unwrap_or(font.height_unscaled());
    let scaled = font.as_scaled(scale_in_points * font_scaling * tweak_scale);
    Some(scaled.h_advance(glyph))
}

/// A nominal size (in points) used only to measure/calibrate tweaks — the
/// values we derive from it are ratios/offsets that `FontTweak` expresses
/// relative to the font size, so they come out the same regardless of
/// which size we measure at (confirmed by `cjk_monospace_alignment` running
/// at a different size).
const REFERENCE_SIZE: f32 = 16.0;

/// Derives a [`egui::FontTweak`] that puts `cjk_bytes`' glyphs (rendered as
/// a fallback alongside `latin_bytes`) on the same baseline as the Latin
/// font, and — when `scale_for_width` is set — scales them to exactly
/// twice the Latin glyph width (only meaningful for a monospace grid, not
/// for prose).
///
/// `egui` lays out every glyph using *its own* font's metrics — there's no
/// built-in concept of a shared character cell across fonts — so two
/// unrelated fonts (a Latin font and a CJK font) generally won't agree on
/// either width or baseline unless corrected for.
fn cjk_fallback_tweak(latin_bytes: &[u8], cjk_bytes: &[u8], scale_for_width: bool) -> Option<egui::FontTweak> {
    let latin = ab_glyph::FontRef::try_from_slice_and_index(latin_bytes, 0).ok()?;
    let cjk = ab_glyph::FontRef::try_from_slice_and_index(cjk_bytes, 0).ok()?;

    let scale = if scale_for_width {
        let latin_advance = advance(&latin, REFERENCE_SIZE, 1.0, 'M')?;
        // Binary-search the scale that makes the (already-scaled) CJK
        // advance exactly double the Latin one — avoids re-deriving the
        // relationship between `tweak.scale` and advance width by hand.
        let target = 2.0 * latin_advance;
        let mut lo = 0.01_f32;
        let mut hi = 10.0_f32;
        for _ in 0..40 {
            let mid = (lo + hi) / 2.0;
            let cjk_advance = advance(&cjk, REFERENCE_SIZE, mid, CJK_REFERENCE_CHAR)?;
            if cjk_advance < target { lo = mid } else { hi = mid }
        }
        (lo + hi) / 2.0
    } else {
        1.0
    };

    // Baseline: `pos.y` is the *font's own* declared baseline placement
    // (from its ascent/descent/line-gap metrics), the same for every glyph
    // that font renders — unlike each individual glyph's ink extent, which
    // naturally varies per character (a katakana "エ" and a kanji "国"
    // don't fill the same vertical space even in a correctly-aligned font,
    // just like Latin "x" and "O" don't). So we align fonts, not glyphs.
    //
    // Rather than hand-deriving every rounding/centering term `epaint`
    // applies when placing a fallback font (see `FontImpl::new` in
    // `epaint::text::font`), measure the actual `pos.y` mismatch by running
    // the real layout engine once at `baseline_offset_factor = 0`, then
    // solve for the factor that cancels it — `pos.y` is linear in that
    // factor, so one measurement is enough.
    let baseline_offset_factor = calibrate_baseline_offset_factor(latin_bytes, cjk_bytes, scale)?;

    Some(egui::FontTweak {
        scale,
        baseline_offset_factor,
        ..Default::default()
    })
}

fn calibrate_baseline_offset_factor(latin_bytes: &[u8], cjk_bytes: &[u8], scale: f32) -> Option<f32> {
    use egui::epaint::AlphaFromCoverage;
    use egui::text::Fonts;
    use egui::{Color32, FontId};

    let mut defs = egui::FontDefinitions {
        font_data: Default::default(),
        families: Default::default(),
    };
    defs.font_data.insert("latin".to_owned(), Arc::new(egui::FontData::from_owned(latin_bytes.to_vec())));
    defs.font_data.insert(
        "cjk".to_owned(),
        Arc::new(egui::FontData::from_owned(cjk_bytes.to_vec()).tweak(egui::FontTweak {
            scale,
            ..Default::default()
        })),
    );
    defs.families.insert(egui::FontFamily::Monospace, vec!["latin".to_owned(), "cjk".to_owned()]);
    defs.families.insert(egui::FontFamily::Proportional, vec!["latin".to_owned()]);

    // A high `pixels_per_point` keeps `round_to_pixel` from swamping the
    // measurement with quantization noise.
    let fonts = Fonts::new(8.0, 8192, AlphaFromCoverage::default(), defs);
    let galley = fonts.layout_no_wrap(format!("M{CJK_REFERENCE_CHAR}"), FontId::monospace(REFERENCE_SIZE), Color32::WHITE);
    let row = galley.rows.first()?;
    let latin_glyph = row.glyphs.first()?;
    let cjk_glyph = row.glyphs.get(1)?;
    let gap = latin_glyph.pos.y - cjk_glyph.pos.y;

    // `pos.y` is linear in `baseline_offset_factor`, but the slope is
    // *not* `REFERENCE_SIZE` — inside `FontImpl::new`, the local
    // `scale_in_points` used for `baseline_offset` is
    // `REFERENCE_SIZE * font_scaling(cjk) * tweak.scale` (see
    // `FontImplCache::font_impl` / `FontImpl::new` in `epaint::text::font`:
    // the pre-tweak `scale_in_pixels` already has `font_scaling` folded in,
    // and gets multiplied by `tweak.scale` before being divided back down
    // to points). Measuring at `factor = 0` and dividing by `REFERENCE_SIZE`
    // alone under-corrects whenever `scale != 1.0`.
    use ab_glyph::Font as _;
    let cjk_font = ab_glyph::FontRef::try_from_slice_and_index(cjk_bytes, 0).ok()?;
    let cjk_font_scaling = cjk_font.height_unscaled() / cjk_font.units_per_em().unwrap_or(cjk_font.height_unscaled());
    let slope = REFERENCE_SIZE * cjk_font_scaling * scale;

    Some(gap / slope)
}

/// A bit more breathing room and softer corners than egui's defaults, for a
/// more modern look.
pub fn setup_style(ctx: &egui::Context) {
    ctx.style_mut(|style| {
        style.spacing.item_spacing = egui::vec2(10.0, 8.0);
        style.spacing.button_padding = egui::vec2(10.0, 6.0);
        style.spacing.menu_margin = egui::Margin::same(8);
        style.spacing.window_margin = egui::Margin::same(12);
        style.spacing.interact_size.y = 28.0;

        for widget in [
            &mut style.visuals.widgets.noninteractive,
            &mut style.visuals.widgets.inactive,
            &mut style.visuals.widgets.hovered,
            &mut style.visuals.widgets.active,
            &mut style.visuals.widgets.open,
        ] {
            widget.corner_radius = egui::CornerRadius::same(6);
        }
        style.visuals.window_corner_radius = egui::CornerRadius::same(10);
        style.visuals.menu_corner_radius = egui::CornerRadius::same(8);
    });
}

/// What triggered the "save before closing?" prompt, so we know what to do
/// once the user answers it.
enum PendingAction {
    CloseTab(usize),
    Quit,
}

enum SavePromptChoice {
    Save,
    DontSave,
    Cancel,
}

struct PendingClose {
    /// Indices (into `TxtxtApp::tabs`) that still need to be resolved,
    /// front-to-back. We ask about one dirty tab at a time.
    dirty_indices: Vec<usize>,
    action: PendingAction,
}

pub struct TxtxtApp {
    tabs: Vec<Tab>,
    active: usize,
    pending_close: Option<PendingClose>,
    quit_requested: bool,
    markdown_cache: CommonMarkCache,
}

impl TxtxtApp {
    pub fn new(initial_paths: Vec<PathBuf>) -> Self {
        let mut tabs: Vec<Tab> = initial_paths
            .into_iter()
            .filter_map(|p| Tab::open(p).ok())
            .collect();
        if tabs.is_empty() {
            tabs.push(Tab::untitled());
        }
        Self {
            tabs,
            active: 0,
            pending_close: None,
            quit_requested: false,
            markdown_cache: CommonMarkCache::default(),
        }
    }

    fn new_tab(&mut self) {
        self.tabs.push(Tab::untitled());
        self.active = self.tabs.len() - 1;
    }

    fn open_file(&mut self) {
        if let Some(path) = rfd::FileDialog::new().pick_file() {
            // Focus the existing tab instead of duplicating it.
            if let Some(idx) = self.tabs.iter().position(|t| t.path.as_deref() == Some(path.as_path())) {
                self.active = idx;
                return;
            }
            match Tab::open(path) {
                Ok(tab) => {
                    self.tabs.push(tab);
                    self.active = self.tabs.len() - 1;
                }
                Err(err) => {
                    eprintln!("failed to open file: {err}");
                }
            }
        }
    }

    fn save_tab(&mut self, idx: usize) {
        if self.tabs[idx].path.is_some() {
            if let Err(err) = self.tabs[idx].save() {
                eprintln!("failed to save file: {err}");
            }
        } else {
            self.save_tab_as(idx);
        }
    }

    fn save_tab_as(&mut self, idx: usize) {
        let default_name = self.tabs[idx].title();
        if let Some(path) = rfd::FileDialog::new().set_file_name(&default_name).save_file() {
            if let Err(err) = self.tabs[idx].save_as(path) {
                eprintln!("failed to save file: {err}");
            }
        }
    }

    /// Begin closing a tab, prompting to save first if it has unsaved changes.
    fn request_close_tab(&mut self, idx: usize) {
        if self.tabs[idx].is_dirty() {
            self.pending_close = Some(PendingClose {
                dirty_indices: vec![idx],
                action: PendingAction::CloseTab(idx),
            });
        } else {
            self.close_tab_now(idx);
        }
    }

    fn request_quit(&mut self) {
        let dirty_indices: Vec<usize> = self
            .tabs
            .iter()
            .enumerate()
            .filter(|(_, t)| t.is_dirty())
            .map(|(i, _)| i)
            .collect();
        if dirty_indices.is_empty() {
            self.quit_requested = true;
        } else {
            self.pending_close = Some(PendingClose {
                dirty_indices,
                action: PendingAction::Quit,
            });
        }
    }

    fn close_tab_now(&mut self, idx: usize) {
        self.tabs.remove(idx);
        if self.tabs.is_empty() {
            self.tabs.push(Tab::untitled());
        }
        if self.active >= self.tabs.len() {
            self.active = self.tabs.len() - 1;
        } else if idx <= self.active && self.active > 0 {
            self.active -= 1;
        }
    }

    fn next_tab(&mut self) {
        self.active = (self.active + 1) % self.tabs.len();
    }

    fn prev_tab(&mut self) {
        self.active = (self.active + self.tabs.len() - 1) % self.tabs.len();
    }

    fn handle_shortcuts(&mut self, ctx: &egui::Context) {
        ctx.input_mut(|i| {
            let cmd_shift_s = i.consume_shortcut(&egui::KeyboardShortcut::new(
                egui::Modifiers::COMMAND.plus(egui::Modifiers::SHIFT),
                egui::Key::S,
            ));
            let cmd_s = !cmd_shift_s
                && i.consume_shortcut(&egui::KeyboardShortcut::new(egui::Modifiers::COMMAND, egui::Key::S));
            let cmd_o = i.consume_shortcut(&egui::KeyboardShortcut::new(egui::Modifiers::COMMAND, egui::Key::O));
            let cmd_t = i.consume_shortcut(&egui::KeyboardShortcut::new(egui::Modifiers::COMMAND, egui::Key::T));
            let cmd_n = i.consume_shortcut(&egui::KeyboardShortcut::new(egui::Modifiers::COMMAND, egui::Key::N));
            let cmd_w = i.consume_shortcut(&egui::KeyboardShortcut::new(egui::Modifiers::COMMAND, egui::Key::W));
            let cmd_alt_right = i.consume_shortcut(&egui::KeyboardShortcut::new(
                egui::Modifiers::COMMAND.plus(egui::Modifiers::ALT),
                egui::Key::ArrowRight,
            ));
            let cmd_alt_left = i.consume_shortcut(&egui::KeyboardShortcut::new(
                egui::Modifiers::COMMAND.plus(egui::Modifiers::ALT),
                egui::Key::ArrowLeft,
            ));

            (
                cmd_shift_s,
                cmd_s,
                cmd_o,
                cmd_t || cmd_n,
                cmd_w,
                cmd_alt_right,
                cmd_alt_left,
            )
        })
        .apply(self);
    }

    /// A `TopBottomPanel`/`CentralPanel` frame with a bit more breathing
    /// room than egui's tight defaults (8h/2v for top-bottom panels).
    fn panel_frame(ctx: &egui::Context, margin: egui::Margin) -> egui::Frame {
        egui::Frame::side_top_panel(&ctx.style()).inner_margin(margin)
    }

    fn show_menu_bar(&mut self, ctx: &egui::Context) {
        egui::TopBottomPanel::top("menu_bar")
            .frame(Self::panel_frame(ctx, egui::Margin::symmetric(14, 10)))
            .show(ctx, |ui| {
            egui::MenuBar::new().ui(ui, |ui| {
                ui.menu_button("File", |ui| {
                    if ui.button("New Tab\t⌘T").clicked() {
                        self.new_tab();
                        ui.close();
                    }
                    if ui.button("Open…\t⌘O").clicked() {
                        self.open_file();
                        ui.close();
                    }
                    ui.separator();
                    if ui.button("Save\t⌘S").clicked() {
                        self.save_tab(self.active);
                        ui.close();
                    }
                    if ui.button("Save As…\t⇧⌘S").clicked() {
                        self.save_tab_as(self.active);
                        ui.close();
                    }
                    ui.separator();
                    if ui.button("Close Tab\t⌘W").clicked() {
                        self.request_close_tab(self.active);
                        ui.close();
                    }
                });

                if self.tabs[self.active].is_markdown() {
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        let tab = &mut self.tabs[self.active];
                        if ui.selectable_label(tab.preview, "Preview").clicked() {
                            tab.preview = true;
                        }
                        if ui.selectable_label(!tab.preview, "Edit").clicked() {
                            tab.preview = false;
                        }
                    });
                }
            });
        });
    }

    fn show_tab_bar(&mut self, ctx: &egui::Context) {
        egui::TopBottomPanel::top("tab_bar")
            .frame(Self::panel_frame(ctx, egui::Margin::symmetric(14, 8)))
            .show(ctx, |ui| {
            ui.horizontal(|ui| {
                let mut close_idx = None;
                for idx in 0..self.tabs.len() {
                    let tab = &self.tabs[idx];
                    let mut label = tab.title();
                    if tab.is_dirty() {
                        label.push_str(" \u{2022}"); // •
                    }
                    let selected = idx == self.active;
                    if ui.selectable_label(selected, label).clicked() {
                        self.active = idx;
                    }
                    if ui.small_button("×").clicked() {
                        close_idx = Some(idx);
                    }
                    ui.separator();
                }
                if let Some(idx) = close_idx {
                    self.request_close_tab(idx);
                }
            });
        });
    }

    fn show_status_bar(&mut self, ctx: &egui::Context) {
        let tab = &self.tabs[self.active];
        let char_count = tab.content.chars().count();
        let line_count = tab.content.lines().count().max(1);
        egui::TopBottomPanel::bottom("status_bar")
            .frame(Self::panel_frame(ctx, egui::Margin::symmetric(14, 6)))
            .show(ctx, |ui| {
            ui.horizontal(|ui| {
                ui.label(format!("{line_count} lines, {char_count} chars"));
            });
        });
    }

    fn show_editor(&mut self, ctx: &egui::Context) {
        let frame = egui::Frame::central_panel(&ctx.style()).inner_margin(10);
        egui::CentralPanel::default().frame(frame).show(ctx, |ui| {
            let tab = &self.tabs[self.active];
            if tab.is_markdown() && tab.preview {
                let content = tab.content.clone();
                egui::ScrollArea::vertical()
                    .auto_shrink([false, false])
                    .show(ui, |ui| {
                        CommonMarkViewer::new().show(ui, &mut self.markdown_cache, &content);
                    });
                return;
            }

            let tab = &mut self.tabs[self.active];
            egui::ScrollArea::vertical()
                .auto_shrink([false, false])
                .show(ui, |ui| {
                    ui.add_sized(
                        ui.available_size(),
                        egui::TextEdit::multiline(&mut tab.content)
                            .font(egui::TextStyle::Monospace)
                            .code_editor()
                            .desired_width(f32::INFINITY),
                    );
                });
        });
    }

    fn show_save_prompt(&mut self, ctx: &egui::Context) {
        let Some(pending) = &self.pending_close else { return };
        let Some(&idx) = pending.dirty_indices.first() else {
            // Nothing left to confirm; carry out the original action.
            let action_is_quit = matches!(pending.action, PendingAction::Quit);
            let close_idx = match pending.action {
                PendingAction::CloseTab(i) => Some(i),
                PendingAction::Quit => None,
            };
            self.pending_close = None;
            if let Some(i) = close_idx {
                self.close_tab_now(i);
            }
            if action_is_quit {
                self.quit_requested = true;
            }
            return;
        };

        let title = self.tabs[idx].title();
        let mut choice = None;
        egui::Window::new("Unsaved Changes")
            .collapsible(false)
            .resizable(false)
            .anchor(egui::Align2::CENTER_CENTER, egui::vec2(0.0, 0.0))
            .show(ctx, |ui| {
                ui.label(format!("\"{title}\" has unsaved changes. Save before closing?"));
                ui.horizontal(|ui| {
                    if ui.button("Save").clicked() {
                        choice = Some(SavePromptChoice::Save);
                    }
                    if ui.button("Don't Save").clicked() {
                        choice = Some(SavePromptChoice::DontSave);
                    }
                    if ui.button("Cancel").clicked() {
                        choice = Some(SavePromptChoice::Cancel);
                    }
                });
            });

        match choice {
            Some(SavePromptChoice::Save) => {
                self.save_tab(idx);
                if let Some(p) = &mut self.pending_close {
                    p.dirty_indices.remove(0);
                }
            }
            Some(SavePromptChoice::DontSave) => {
                if let Some(p) = &mut self.pending_close {
                    p.dirty_indices.remove(0);
                }
            }
            Some(SavePromptChoice::Cancel) => {
                self.pending_close = None;
            }
            None => {}
        }
    }
}

/// Small helper so `handle_shortcuts` can apply the results it collected
/// under a single borrow of `ctx.input_mut`.
trait ApplyShortcuts {
    fn apply(self, app: &mut TxtxtApp);
}

impl ApplyShortcuts for (bool, bool, bool, bool, bool, bool, bool) {
    fn apply(self, app: &mut TxtxtApp) {
        let (cmd_shift_s, cmd_s, cmd_o, cmd_new_tab, cmd_w, next, prev) = self;
        if cmd_shift_s {
            app.save_tab_as(app.active);
        } else if cmd_s {
            app.save_tab(app.active);
        }
        if cmd_o {
            app.open_file();
        }
        if cmd_new_tab {
            app.new_tab();
        }
        if cmd_w {
            app.request_close_tab(app.active);
        }
        if next {
            app.next_tab();
        }
        if prev {
            app.prev_tab();
        }
    }
}

impl eframe::App for TxtxtApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        let close_requested = ctx.input(|i| i.viewport().close_requested());
        if close_requested && !self.quit_requested {
            // Abort the OS-driven close; we'll re-issue it ourselves once any
            // unsaved-changes prompt is resolved.
            ctx.send_viewport_cmd(egui::ViewportCommand::CancelClose);
            if self.pending_close.is_none() {
                self.request_quit();
            }
        }
        if self.pending_close.is_none() {
            self.handle_shortcuts(ctx);
        }

        self.show_menu_bar(ctx);
        self.show_tab_bar(ctx);
        self.show_status_bar(ctx);
        self.show_editor(ctx);

        if self.pending_close.is_some() {
            self.show_save_prompt(ctx);
        }

        if self.quit_requested {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use egui::epaint::AlphaFromCoverage;
    use egui::text::Fonts;
    use egui::{Color32, FontId};

    /// Runs the real `egui` text-layout engine (no window needed — pure CPU
    /// glyph-metric math) over a representative Latin/CJK string, using our
    /// actual font setup, and checks that the monospace-family fallback
    /// lands on the "1 CJK char = 2 ASCII chars" width and a shared
    /// baseline that `cjk_fallback_tweak` is supposed to produce.
    #[test]
    fn cjk_monospace_alignment() {
        // pixels_per_point=2.0 matches a real Retina display; round_to_pixel
        // granularity (1 / pixels_per_point) affects how tight a tolerance
        // is meaningful below.
        let fonts = Fonts::new(2.0, 8192, AlphaFromCoverage::default(), build_font_definitions());
        let galley = fonts.layout_no_wrap("aa国あいうえおアイウエオ漢字".to_owned(), FontId::monospace(16.0), Color32::WHITE);
        let row = &galley.rows[0];
        // `pos.y` is the *font's own* baseline placement — identical for
        // every glyph that font renders, regardless of that glyph's
        // individual ink extent (which naturally varies per character,
        // just like Latin "x" vs "O" — not something we try to equalize).
        let glyphs: Vec<_> = row.glyphs.iter().map(|g| (g.chr, g.advance_width, g.pos.y)).collect();
        println!("glyphs (chr, advance_width, pos.y): {glyphs:?}");

        let ascii_width = glyphs[0].1;
        for (chr, width, _) in &glyphs {
            if !chr.is_ascii() {
                let ratio = width / ascii_width;
                assert!(
                    (ratio - 2.0).abs() < 0.05,
                    "{chr:?} width {width} is not ~2x ascii width {ascii_width} (ratio {ratio})"
                );
            }
        }

        let ascii_y = glyphs[0].2;
        for (chr, _, y) in &glyphs {
            assert!((y - ascii_y).abs() < 0.5, "{chr:?} baseline y={y} does not match ascii baseline y={ascii_y}");
        }
    }

    /// Same baseline check as `cjk_monospace_alignment`, but for the
    /// Proportional family (used by the tab bar, menu, and Markdown
    /// preview pane) — width is irrelevant there, only baseline alignment.
    #[test]
    fn cjk_proportional_baseline_alignment() {
        let fonts = Fonts::new(2.0, 8192, AlphaFromCoverage::default(), build_font_definitions());
        let galley = fonts.layout_no_wrap("a国あ".to_owned(), FontId::proportional(16.0), Color32::WHITE);
        let row = &galley.rows[0];
        let glyphs: Vec<_> = row.glyphs.iter().map(|g| (g.chr, g.pos.y)).collect();
        println!("glyphs (chr, pos.y): {glyphs:?}");

        let ascii_y = glyphs[0].1;
        for (chr, y) in &glyphs {
            assert!((y - ascii_y).abs() < 0.5, "{chr:?} baseline y={y} does not match ascii baseline y={ascii_y}");
        }
    }
}
