mod app;
mod tab;

use std::path::PathBuf;

use app::{setup_fonts, setup_style, TxtxtApp};

fn main() -> eframe::Result<()> {
    let initial_paths: Vec<PathBuf> = std::env::args().skip(1).map(PathBuf::from).collect();

    let options = eframe::NativeOptions {
        viewport: eframe::egui::ViewportBuilder::default()
            .with_title("txtxt")
            .with_inner_size([1000.0, 680.0]),
        ..Default::default()
    };

    eframe::run_native(
        "txtxt",
        options,
        Box::new(|cc| {
            setup_fonts(&cc.egui_ctx);
            setup_style(&cc.egui_ctx);
            Ok(Box::new(TxtxtApp::new(initial_paths)))
        }),
    )
}
