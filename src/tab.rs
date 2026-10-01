use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub struct Tab {
    pub path: Option<PathBuf>,
    pub content: String,
    pub saved_content: String,
    /// Whether a markdown tab is showing the rendered preview instead of
    /// the raw source. Ignored for non-markdown tabs.
    pub preview: bool,
}

impl Tab {
    pub fn untitled() -> Self {
        Self {
            path: None,
            content: String::new(),
            saved_content: String::new(),
            preview: false,
        }
    }

    pub fn open(path: PathBuf) -> io::Result<Self> {
        let content = fs::read_to_string(&path)?;
        let preview = is_markdown_path(&path);
        Ok(Self {
            saved_content: content.clone(),
            content,
            path: Some(path),
            preview,
        })
    }

    pub fn is_markdown(&self) -> bool {
        self.path.as_deref().is_some_and(is_markdown_path)
    }

    pub fn is_dirty(&self) -> bool {
        self.content != self.saved_content
    }

    pub fn title(&self) -> String {
        match &self.path {
            Some(p) => p
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_else(|| "Untitled".to_string()),
            None => "Untitled".to_string(),
        }
    }

    pub fn save(&mut self) -> io::Result<()> {
        let path = self
            .path
            .as_ref()
            .expect("save() requires a path; use save_as for untitled tabs")
            .clone();
        self.save_to(&path)
    }

    pub fn save_as(&mut self, path: PathBuf) -> io::Result<()> {
        self.save_to(&path)?;
        self.path = Some(path);
        Ok(())
    }

    fn save_to(&mut self, path: &Path) -> io::Result<()> {
        fs::write(path, &self.content)?;
        self.saved_content = self.content.clone();
        Ok(())
    }
}

fn is_markdown_path(path: &Path) -> bool {
    path.extension()
        .is_some_and(|ext| ext.eq_ignore_ascii_case("md") || ext.eq_ignore_ascii_case("markdown"))
}
