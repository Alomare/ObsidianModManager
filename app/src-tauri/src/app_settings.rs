//! The app's own settings (appearance, language, updates, game folder) in `<data>/app.json`.
//! They belong to the app, not to a profile. Window size and position are kept by the
//! window-state plugin.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

const FILE: &str = "app.json";
pub const SCALES: [u32; 4] = [90, 100, 110, 125];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Theme {
    #[default]
    Default,
    Dark,
    Light,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Nav {
    #[default]
    Top,
    Left,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TextSize {
    Small,
    #[default]
    Normal,
    Large,
}

/// What a new version of Obsidian found at startup does.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum UpdateMode {
    Manual,
    #[default]
    Prompt,
    Auto,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AppSettings {
    pub theme: Theme,
    pub nav: Nav,
    /// UI scale in percent, one of `SCALES`.
    pub scale: u32,
    pub text: TextSize,
    /// Animations; `None` follows the Windows reduced-motion setting.
    pub motion: Option<bool>,
    /// UI language; `None` follows the system language.
    pub language: Option<String>,
    pub updates: UpdateMode,
    /// The game folder chosen in Settings; `None` searches the Steam libraries.
    pub game_dir: Option<PathBuf>,
}

impl Default for AppSettings {
    fn default() -> Self {
        AppSettings {
            theme: Theme::Default,
            nav: Nav::Top,
            scale: 100,
            text: TextSize::Normal,
            motion: None,
            language: None,
            updates: UpdateMode::Prompt,
            game_dir: None,
        }
    }
}

impl AppSettings {
    /// The saved settings; a missing or damaged file gives the defaults.
    pub fn load(data: &Path) -> AppSettings {
        let mut s: AppSettings = std::fs::read_to_string(data.join(FILE)).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default();
        if !SCALES.contains(&s.scale) {
            s.scale = 100;
        }
        s
    }

    pub fn save(&self, data: &Path) -> std::io::Result<()> {
        std::fs::create_dir_all(data)?;
        std::fs::write(data.join(FILE), serde_json::to_string_pretty(self)? + "\n")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_when_missing_or_damaged() {
        let t = tempfile::tempdir().unwrap();
        let d = AppSettings::load(t.path());
        assert_eq!(d, AppSettings::default());
        assert_eq!((d.updates, d.scale, d.nav), (UpdateMode::Prompt, 100, Nav::Top));
        std::fs::write(t.path().join(FILE), "{ not json").unwrap();
        assert_eq!(AppSettings::load(t.path()), AppSettings::default());
    }

    #[test]
    fn round_trip_and_partial_files() {
        let t = tempfile::tempdir().unwrap();
        let s = AppSettings { theme: Theme::Light, nav: Nav::Left, scale: 125, motion: Some(false), language: Some("pt-BR".into()), ..Default::default() };
        s.save(t.path()).unwrap();
        assert_eq!(AppSettings::load(t.path()), s);
        std::fs::write(t.path().join(FILE), r#"{"theme":"dark"}"#).unwrap();
        assert_eq!(AppSettings::load(t.path()).theme, Theme::Dark, "missing keys take defaults");
    }

    #[test]
    fn scale_outside_the_steps_becomes_100() {
        let t = tempfile::tempdir().unwrap();
        std::fs::write(t.path().join(FILE), r#"{"scale":300}"#).unwrap();
        assert_eq!(AppSettings::load(t.path()).scale, 100);
    }
}
