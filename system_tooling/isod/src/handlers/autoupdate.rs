use anyhow::Result;
use console::{Term, style};
use dialoguer::Confirm;
use indicatif::{MultiProgress, ProgressBar, ProgressStyle};
use isod::config::{Config, DistroConfig};
use isod::download::{DownloadManager, DownloadOptions, DownloadProgress};
use isod::registry::{IsoRegistry, ReleaseType};
use isod::usb::UsbManager;
use std::collections::HashMap;
use std::path::PathBuf;
use std::process;
use tokio::fs;

#[derive(Debug)]
struct IsoUpdateInfo {
    filename: String,
    current_path: Option<PathBuf>,
    target_path: PathBuf,
    iso_info: isod::IsoInfo,
    action: UpdateAction,
}

#[derive(Debug)]
enum UpdateAction {
    Download, // New ISO needed
    Update,   // Newer version available
    Keep,     // Current version is up to date
}

pub async fn handle_autoupdate(
    usb_manager: &mut UsbManager,
    iso_registry: &IsoRegistry,
    yes: bool,
    dry_run: bool,
) -> Result<()> {
    let term = Term::stdout();

    if dry_run {
        term.write_line(&format!(
            "{} Dry run - showing what would be updated",
            style("🔍").cyan().bold()
        ))?;
    } else {
        term.write_line(&format!(
            "{} Starting automatic USB ISO update...",
            style("🔄").cyan().bold()
        ))?;
    }

    // Step 1: Find and validate Ventoy USB
    term.write_line(&format!(
        "{} Detecting Ventoy USB devices...",
        style("🔌").cyan()
    ))?;

    let ventoy_devices = usb_manager.find_ventoy_devices().await?;
    if ventoy_devices.is_empty() {
        term.write_line(&format!("{} No Ventoy devices found.", style("❌").red()))?;
        term.write_line(&format!(
            "{} Please ensure your Ventoy USB is connected and mounted.",
            style("💡").yellow()
        ))?;
        process::exit(1);
    }

    // Auto-select if only one device, otherwise prompt user
    let selected_device = if ventoy_devices.len() == 1 {
        &ventoy_devices[0]
    } else {
        term.write_line(&format!(
            "{} Multiple Ventoy devices found. Please use 'isod sync' to select one first.",
            style("⚠️").yellow()
        ))?;
        process::exit(1);
    };

    usb_manager
        .select_device(&selected_device.device_path.to_string_lossy())
        .await?;

    term.write_line(&format!(
        "{} Using device: {} ({})",
        style("✅").green(),
        style(selected_device.device_path.display()).cyan(),
        selected_device.label.as_deref().unwrap_or("unlabeled")
    ))?;

    // Step 2: Read configuration from USB
    term.write_line(&format!(
        "{} Reading configuration from USB...",
        style("📖").cyan()
    ))?;

    let usb_config = read_usb_config(usb_manager).await?;
    let enabled_distros: Vec<_> = usb_config
        .distros
        .iter()
        .filter(|(_, config)| config.enabled)
        .collect();

    if enabled_distros.is_empty() {
        term.write_line(&format!(
            "{} No distributions configured on USB.",
            style("📭").yellow()
        ))?;
        term.write_line(&format!(
            "{} Create a config file at /isod/config.toml on your USB device, or use 'isod add' commands.",
            style("💡").yellow()
        ))?;
        process::exit(1);
    }

    term.write_line(&format!(
        "{} Found {} configured distributions: {}",
        style("📋").green(),
        enabled_distros.len(),
        enabled_distros
            .iter()
            .map(|(name, _)| name.as_str())
            .collect::<Vec<_>>()
            .join(", ")
    ))?;

    // Step 3: Analyze current state and plan updates
    term.write_line(&format!(
        "{} Analyzing current ISOs and available updates...",
        style("🔍").cyan()
    ))?;

    let update_plan = create_update_plan(usb_manager, iso_registry, &usb_config).await?;

    // Step 4: Show update summary
    display_update_summary(&term, &update_plan)?;

    let downloads_needed = update_plan
        .iter()
        .filter(|info| matches!(info.action, UpdateAction::Download | UpdateAction::Update))
        .count();

    let deletions_needed = update_plan
        .iter()
        .filter(|info| matches!(info.action, UpdateAction::Update) && info.current_path.is_some())
        .count();

    if downloads_needed == 0 && deletions_needed == 0 {
        term.write_line(&format!(
            "{} All ISOs are up to date! No changes needed.",
            style("🎉").green().bold()
        ))?;
        return Ok(());
    }

    // Step 5: Confirm with user (unless --yes or --dry-run)
    if !dry_run && !yes {
        term.write_line("")?;
        let confirmed = Confirm::new()
            .with_prompt("Proceed with USB update?")
            .default(true)
            .interact()?;

        if !confirmed {
            term.write_line(&format!("{} Update cancelled.", style("❌").red()))?;
            return Ok(());
        }
    }

    if dry_run {
        term.write_line(&format!(
            "\n{} Dry run complete. Use without --dry-run to perform actual updates.",
            style("✅").green()
        ))?;
        return Ok(());
    }

    // Step 6: Execute the update plan
    execute_update_plan(usb_manager, &update_plan).await?;

    term.write_line(&format!(
        "\n{} USB update completed successfully!",
        style("🎉").green().bold()
    ))?;

    // Show final summary
    let downloaded = update_plan
        .iter()
        .filter(|info| matches!(info.action, UpdateAction::Download | UpdateAction::Update))
        .count();

    if downloaded > 0 {
        term.write_line(&format!(
            "{} Downloaded {} new/updated ISOs",
            style("📥").green(),
            downloaded
        ))?;
    }

    if deletions_needed > 0 {
        term.write_line(&format!(
            "{} Removed {} outdated ISOs",
            style("🗑️").green(),
            deletions_needed
        ))?;
    }

    Ok(())
}

async fn read_usb_config(usb_manager: &UsbManager) -> Result<Config> {
    let current = usb_manager
        .get_current_device()
        .await
        .ok_or_else(|| anyhow::anyhow!("No USB device selected"))?;

    let mount_point = current
        .mount_point
        .ok_or_else(|| anyhow::anyhow!("USB device not mounted"))?;

    let config_path = mount_point.join("isod").join("config.toml");

    if config_path.exists() {
        let config_content = fs::read_to_string(&config_path).await?;
        Ok(toml::from_str(&config_content)?)
    } else {
        // Create a basic config with some common distros
        let mut config = Config::default();

        // Add some sensible defaults
        config.distros.insert(
            "ubuntu".to_string(),
            DistroConfig {
                variants: vec!["desktop".to_string()],
                architectures: vec!["amd64".to_string()],
                enabled: false, // Disabled by default
                ..Default::default()
            },
        );

        config.distros.insert(
            "fedora".to_string(),
            DistroConfig {
                variants: vec!["workstation".to_string()],
                architectures: vec!["x86_64".to_string()],
                enabled: false,
                ..Default::default()
            },
        );

        // Create the config directory and write the default config
        let config_dir = mount_point.join("isod");
        fs::create_dir_all(&config_dir).await?;

        let config_content = toml::to_string_pretty(&config)?;
        fs::write(&config_path, config_content).await?;

        Ok(config)
    }
}

async fn create_update_plan(
    usb_manager: &UsbManager,
    iso_registry: &IsoRegistry,
    usb_config: &Config,
) -> Result<Vec<IsoUpdateInfo>> {
    let iso_dir = usb_manager.get_iso_directory().await?;
    let current_isos = scan_current_isos(&iso_dir).await?;
    let mut update_plan = Vec::new();

    for (distro_name, distro_config) in &usb_config.distros {
        if !distro_config.enabled {
            continue;
        }

        // Get latest version for this distro
        let latest_version = match iso_registry.get_latest_version(distro_name).await {
            Ok(version) => version,
            Err(e) => {
                eprintln!(
                    "Warning: Could not get latest version for {}: {}",
                    distro_name, e
                );
                continue;
            }
        };

        // Only consider stable and LTS releases unless specifically configured otherwise
        if !matches!(
            latest_version.release_type,
            ReleaseType::Stable | ReleaseType::LTS
        ) {
            continue;
        }

        // Check each variant/arch combination
        for variant in &distro_config.variants {
            for arch in &distro_config.architectures {
                let iso_info = match iso_registry
                    .get_iso_info(
                        distro_name,
                        Some(&latest_version.version),
                        Some(arch),
                        Some(variant),
                    )
                    .await
                {
                    Ok(info) => info,
                    Err(e) => {
                        eprintln!(
                            "Warning: Could not get ISO info for {}-{}-{}: {}",
                            distro_name, arch, variant, e
                        );
                        continue;
                    }
                };

                let target_path = iso_dir.join(&iso_info.filename);
                let current_path = current_isos.get(&iso_info.filename).cloned();

                let action = if current_path.is_some() {
                    // TODO: Check if the current version is outdated
                    // For now, assume current version is up to date
                    UpdateAction::Keep
                } else {
                    UpdateAction::Download
                };

                update_plan.push(IsoUpdateInfo {
                    filename: iso_info.filename.clone(),
                    current_path,
                    target_path,
                    iso_info,
                    action,
                });
            }
        }
    }

    Ok(update_plan)
}

async fn scan_current_isos(iso_dir: &PathBuf) -> Result<HashMap<String, PathBuf>> {
    let mut isos = HashMap::new();

    if iso_dir.exists() {
        let mut entries = fs::read_dir(iso_dir).await?;
        while let Ok(Some(entry)) = entries.next_entry().await {
            let path = entry.path();
            if path.extension().and_then(|s| s.to_str()) == Some("iso") {
                if let Some(filename) = path.file_name().and_then(|s| s.to_str()) {
                    isos.insert(filename.to_string(), path);
                }
            }
        }
    }

    Ok(isos)
}

fn display_update_summary(term: &Term, update_plan: &[IsoUpdateInfo]) -> Result<()> {
    term.write_line(&format!("\n{} Update Summary:", style("📊").cyan().bold()))?;

    let mut downloads = 0;
    let mut updates = 0;
    let mut kept = 0;

    for info in update_plan {
        match info.action {
            UpdateAction::Download => {
                term.write_line(&format!(
                    "  {} {} (new)",
                    style("⬇️").green(),
                    style(&info.filename).cyan()
                ))?;
                downloads += 1;
            }
            UpdateAction::Update => {
                term.write_line(&format!(
                    "  {} {} (update)",
                    style("🔄").yellow(),
                    style(&info.filename).cyan()
                ))?;
                updates += 1;
            }
            UpdateAction::Keep => {
                term.write_line(&format!(
                    "  {} {} (current)",
                    style("✅").dim(),
                    style(&info.filename).dim()
                ))?;
                kept += 1;
            }
        }
    }

    term.write_line("")?;
    term.write_line(&format!(
        "  {}: {}",
        style("New downloads").green(),
        downloads
    ))?;
    term.write_line(&format!("  {}: {}", style("Updates").yellow(), updates))?;
    term.write_line(&format!("  {}: {}", style("Up to date").dim(), kept))?;

    Ok(())
}

async fn execute_update_plan(
    usb_manager: &UsbManager,
    update_plan: &[IsoUpdateInfo],
) -> Result<()> {
    let term = Term::stdout();
    let iso_dir = usb_manager.get_iso_directory().await?;

    // Create ISO directory if it doesn't exist
    fs::create_dir_all(&iso_dir).await?;

    let items_to_download: Vec<_> = update_plan
        .iter()
        .filter(|info| matches!(info.action, UpdateAction::Download | UpdateAction::Update))
        .collect();

    if items_to_download.is_empty() {
        return Ok(());
    }

    term.write_line(&format!(
        "{} Downloading {} ISOs to USB...",
        style("📥").cyan(),
        items_to_download.len()
    ))?;

    // Set up download manager to target USB directory
    let download_options = DownloadOptions {
        max_concurrent: 2,      // Be gentle with USB bandwidth
        prefer_torrents: false, // HTTP is more reliable for USB
        output_directory: iso_dir.clone(),
        verify_checksums: true,
        resume_downloads: true,
    };

    let (download_manager, mut progress_receiver) = DownloadManager::new(download_options.clone())?;
    let multi_progress = MultiProgress::new();
    let mut active_downloads = HashMap::new();

    // Start downloads
    for info in &items_to_download {
        let download_id = download_manager
            .download_iso(&info.iso_info, &download_options)
            .await?;

        let progress_bar = multi_progress.add(ProgressBar::new(100));
        progress_bar.set_style(
            ProgressStyle::default_bar()
                .template("{spinner:.green} [{elapsed_precise}] [{bar:.cyan/blue}] {bytes}/{total_bytes} ({bytes_per_sec}) {msg}")
                .unwrap()
                .progress_chars("#>-")
        );
        progress_bar.set_message(info.filename.clone());

        active_downloads.insert(download_id, (progress_bar, info));
    }

    // Handle progress updates
    let mut completed_downloads = 0;
    let total_downloads = active_downloads.len();

    while let Some(progress) = progress_receiver.recv().await {
        if let Some((progress_bar, info)) = active_downloads.get(
            &match &progress {
                DownloadProgress::Started { id, .. } => id,
                DownloadProgress::Progress { id, .. } => id,
                DownloadProgress::VerifyingChecksum { id } => id,
                DownloadProgress::ChecksumVerified { id } => id,
                DownloadProgress::ChecksumFailed { id, .. } => id,
                DownloadProgress::Completed { id, .. } => id,
                DownloadProgress::Failed { id, .. } => id,
                DownloadProgress::Retry { id, .. } => id,
                DownloadProgress::Cancelled { id } => id,
                DownloadProgress::Error { id, .. } => id,
            }
            .clone(),
        ) {
            match &progress {
                DownloadProgress::Progress {
                    bytes_downloaded,
                    total_bytes,
                    ..
                } => {
                    if *total_bytes > 0 {
                        progress_bar.set_length(*total_bytes);
                        progress_bar.set_position(*bytes_downloaded);
                    }
                }
                DownloadProgress::VerifyingChecksum { .. } => {
                    progress_bar.set_message(format!("{} - Verifying checksum...", info.filename));
                }
                DownloadProgress::Completed { .. } => {
                    progress_bar.finish_with_message(format!(
                        "{} {}",
                        style("✅").green(),
                        info.filename
                    ));
                    completed_downloads += 1;

                    // Remove old version if this was an update
                    if matches!(info.action, UpdateAction::Update) {
                        if let Some(old_path) = &info.current_path {
                            let _ = fs::remove_file(old_path).await;
                        }
                    }
                }
                DownloadProgress::Failed { error, .. } => {
                    progress_bar.finish_with_message(format!(
                        "{} Failed: {}",
                        style("❌").red(),
                        error
                    ));
                    completed_downloads += 1;
                }
                DownloadProgress::ChecksumFailed { .. } => {
                    progress_bar.finish_with_message(format!(
                        "{} Checksum verification failed",
                        style("❌").red()
                    ));
                    completed_downloads += 1;
                }
                _ => {}
            }
        }

        if completed_downloads >= total_downloads {
            break;
        }
    }

    Ok(())
}
