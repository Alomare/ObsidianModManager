//! `obsidian`: the command line over obsidian-core.

use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use obsidian_core::compose::compose;
use obsidian_core::deploy::{DeployOptions, deploy, purge, status};
use obsidian_core::game::{GameInstall, find_game};
use obsidian_core::gate::KNOWN_BUILDS;
use obsidian_core::hash::{format_name, format_type};
use obsidian_core::import::import_path;
use obsidian_core::library::{InstallOutcome, Library, Profile};
use obsidian_core::manifest::Scope;
use obsidian_core::paths::data_dir;
use obsidian_core::loader::{FEATURES, settings_for};
use obsidian_core::options::validate;
use obsidian_core::{ObsidianError, Result};

#[derive(Parser)]
#[command(name = "obsidian", version, about = "Mod manager for HELLDIVERS (2015)")]
struct Cli {
    /// The Helldivers game folder (skips the Steam search)
    #[arg(long, global = true)]
    game: Option<PathBuf>,
    /// Where Obsidian keeps mods, the profile and backups
    #[arg(long, global = true)]
    data_dir: Option<PathBuf>,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Show the game folder, save folder and build check
    Game,
    /// Import a mod folder or .zip into the library
    Import { path: PathBuf },
    /// List the mods in the library, in load order
    List,
    /// Put these mods first in the load order (later mods win conflicts)
    Order { ids: Vec<String> },
    /// Turn a mod on
    Enable { id: String },
    /// Turn a mod off
    Disable { id: String },
    /// Show which mods change the same resources, without writing anything
    Conflicts,
    /// Write the enabled mods into the game
    Deploy,
    /// Remove everything the last deploy wrote
    Purge,
    /// Show the build check, what is deployed and patches from other tools
    Status,
    /// Turn a built-in feature on or off: skip_intro, skip_login, skip_war_briefs
    Feature { name: String, state: OnOff },
    /// Allow session mods from other Obsidian users (on or off)
    Consent { state: OnOff },
    /// Set a mod option, for example: obsidian set author.mod distance 7
    Set { id: String, option: String, value: String },
}

#[derive(Clone, Copy, clap::ValueEnum)]
enum OnOff {
    On,
    Off,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match run(cli) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("Error: {e}");
            if matches!(e, ObsidianError::UnsupportedBuild(_)) { ExitCode::from(2) } else { ExitCode::FAILURE }
        }
    }
}

fn run(cli: Cli) -> Result<()> {
    let data = data_dir(cli.data_dir.as_deref());
    let game = || find_game(cli.game.as_deref());
    let lib = Library::open(&data)?;
    // Purge and status must work even when a mod folder or the profile is damaged,
    // so only the commands that use the library read and sync it.
    let uses_library = matches!(
        cli.command,
        Command::Import { .. } | Command::List | Command::Order { .. } | Command::Enable { .. } | Command::Disable { .. } | Command::Conflicts
            | Command::Feature { .. } | Command::Consent { .. } | Command::Set { .. }
    );
    let mut profile = Profile::default();
    if uses_library {
        profile = Profile::load(&data)?;
        profile.sync(&lib)?;
        profile.save(&data)?;
    }
    match cli.command {
        Command::Game => {
            let g = game()?;
            println!("Game folder: {}", g.root.display());
            println!("Save folder: {}", g.saves_dir.display());
            print_gate(&g)?;
        }
        Command::Import { path } => {
            let r = import_path(&path, &game()?, &lib)?;
            let what = if r.legacy { "legacy mod" } else { "Obsidian mod" };
            let how = match r.outcome {
                InstallOutcome::Added => "added".to_string(),
                InstallOutcome::Replaced { old_version } => format!("replaced version {old_version}"),
            };
            println!("Imported {} ({what}, {how})", r.id);
            if r.legacy {
                println!("  {} changed, {} added resources", r.changed, r.added);
                if r.removed_ignored > 0 {
                    println!("  {} resources missing from the mod were left as in the game", r.removed_ignored);
                }
            }
            profile.sync(&lib)?;
            profile.save(&data)?;
        }
        Command::List => {
            let mods = lib.list()?;
            if profile.mods.is_empty() {
                println!("The library is empty. Add mods with: obsidian import <folder or .zip>");
            }
            for (i, entry) in profile.mods.iter().enumerate() {
                let Some(m) = mods.iter().find(|m| m.id == entry.id) else { continue };
                let on = if entry.enabled { "on " } else { "off" };
                let scope = if m.scope == Scope::Client { "client" } else { "session" };
                println!("{:>3}. [{on}] {} {} ({scope})", i + 1, m.id, m.version);
            }
        }
        Command::Order { ids } => {
            profile.set_order(&ids);
            profile.save(&data)?;
            println!("Load order: {}", profile.mods.iter().map(|m| m.id.as_str()).collect::<Vec<_>>().join(", "));
        }
        Command::Enable { id } => toggle(&mut profile, &data, &id, true)?,
        Command::Disable { id } => toggle(&mut profile, &data, &id, false)?,
        Command::Conflicts => {
            let c = compose(&lib, &profile)?;
            if c.conflicts.is_empty() {
                println!("No conflicts between the enabled mods.");
            }
            for x in c.conflicts {
                println!(
                    "{} {} in {}: {} wins over {}",
                    format_type(x.type_hash),
                    format_name(x.name_hash),
                    x.bundle,
                    x.winner,
                    x.losers.join(", ")
                );
            }
        }
        Command::Deploy => {
            let r = deploy(&game()?, &data, &DeployOptions::default())?;
            for p in &r.patches {
                println!("Wrote {}", p.display());
            }
            for p in &r.foreign {
                println!("Left in place (another tool): {}", p.display());
            }
            if let Some(b) = &r.backup {
                println!("Saves backed up to {}", b.display());
            }
            if !r.conflicts.is_empty() {
                println!("{} conflicts resolved by load order (see: obsidian conflicts)", r.conflicts.len());
            }
            if r.patches.is_empty() {
                println!("No mods enabled, so the game is vanilla.");
            }
        }
        Command::Purge => {
            let r = purge(&game()?, &data)?;
            for p in &r.removed {
                println!("Removed {}", p.display());
            }
            for p in &r.kept_changed {
                println!("Kept {} (changed since Obsidian wrote the file)", p.display());
            }
            if r.removed.is_empty() && r.kept_changed.is_empty() {
                println!("Nothing to purge.");
            }
        }
        Command::Status => {
            let g = game()?;
            print_gate(&g)?;
            let s = status(&g, &data, KNOWN_BUILDS)?;
            match &s.deployed {
                Some(d) if !d.files.is_empty() => println!("Deployed: {} ({} patches, {})", d.mods.join(", "), d.files.len(), d.time),
                _ => println!("Deployed: nothing, the game is vanilla"),
            }
            for p in &s.foreign {
                println!("Patch from another tool: {}", p.display());
            }
            if let Some(id) = &s.crash_culprit {
                println!("The last game launch stopped while loading {id}. If the game crashed, disable that mod and deploy again.");
            }
        }
        Command::Feature { name, state } => {
            if !FEATURES.contains(&name.as_str()) {
                return Err(ObsidianError::UnknownFeature(name));
            }
            profile.features.retain(|f| *f != name);
            if matches!(state, OnOff::On) {
                profile.features.push(name.clone());
            }
            live_change(&profile, &data, &lib, &game()?, &format!("{name} is now {}", on_off(state)))?;
        }
        Command::Consent { state } => {
            profile.consent = matches!(state, OnOff::On);
            live_change(&profile, &data, &lib, &game()?, &format!("Session mods from other Obsidian users are now {}", if profile.consent { "allowed" } else { "not allowed" }))?;
        }
        Command::Set { id, option, value } => {
            let m = lib.list()?.into_iter().find(|m| m.id == id).ok_or_else(|| ObsidianError::ModMissing(id.clone()))?;
            let specs = m.option_specs()?;
            let spec = specs.iter().find(|s| s.id == option).ok_or_else(|| ObsidianError::UnknownOption { mod_id: id.clone(), option: option.clone() })?;
            // 7, true and "night" all work; anything that isn't JSON is taken as text.
            let parsed = serde_json::from_str(&value).unwrap_or(serde_json::Value::String(value.clone()));
            let v = validate(spec, &parsed)?;
            profile.options.entry(id.clone()).or_default().insert(option.clone(), v.clone());
            let redeploy = m.resources.iter().any(|r| r.when.contains_key(&option)) || (m.scope == Scope::Session && !spec.client) || m.entry.is_none();
            if redeploy {
                profile.save(&data)?;
                println!("{id} {option} is now {v}. Run obsidian deploy to apply.");
            } else {
                live_change(&profile, &data, &lib, &game()?, &format!("{id} {option} is now {v}"))?;
            }
        }
    }
    Ok(())
}

fn on_off(s: OnOff) -> &'static str {
    if matches!(s, OnOff::On) { "on" } else { "off" }
}

/// Saves the profile and rewrites the settings file the loader reads at launch, so the change
/// needs no redeploy once the loader is in the game.
fn live_change(profile: &Profile, data: &std::path::Path, lib: &Library, g: &GameInstall, what: &str) -> Result<()> {
    profile.save(data)?;
    obsidian_core::settings::write(&obsidian_core::settings::game_side_dir(&g.saves_dir), &settings_for(lib, profile)?)?;
    // The loader lives in the boot bundle patch, so a deploy that wrote none has no loader in the game.
    let loader_deployed = status(g, data, KNOWN_BUILDS)
        .ok()
        .and_then(|s| s.deployed)
        .is_some_and(|d| d.files.iter().any(|f| f.path.file_name().is_some_and(|n| n.to_string_lossy().starts_with(obsidian_core::loader::BUNDLE))));
    if loader_deployed {
        println!("{what}. Applies at the next game launch.");
    } else {
        println!("{what}. Run obsidian deploy to apply.");
    }
    Ok(())
}

fn toggle(profile: &mut Profile, data: &std::path::Path, id: &str, on: bool) -> Result<()> {
    profile.set_enabled(id, on)?;
    profile.save(data)?;
    println!("{id} is now {}. Run obsidian deploy to apply.", if on { "on" } else { "off" });
    Ok(())
}

fn print_gate(g: &GameInstall) -> Result<()> {
    let r = obsidian_core::gate::check_build(&g.root, KNOWN_BUILDS)?;
    match r.build {
        Some(b) => println!("Game build: {b}"),
        None => println!("Game build: not recognised (differs in {})", r.mismatches.join(", ")),
    }
    Ok(())
}
