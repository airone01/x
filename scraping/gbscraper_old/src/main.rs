use anyhow::{Context, Result};
use futures_util::StreamExt;
use governor::{Quota, RateLimiter};
use indicatif::{MultiProgress, ProgressBar, ProgressStyle};
use reqwest::{Client, StatusCode};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use sqlx::sqlite::SqlitePool;
use std::io::{Read, Seek, Write as _};
use std::num::NonZeroU32;
use std::sync::Arc;
use std::time::Duration;
use tempfile::NamedTempFile;
use zip::ZipArchive;

// --- CONFIGURATION ---
const GAME_ID: u32 = 6460; // Celeste

// STRICT LIMIT: 1 request every 1.2 seconds (~50 req/min).
// GameBanana starts blocking around 60 req/min.
const REQUEST_INTERVAL_MS: u64 = 1200;

// Downloads can be slightly parallel, but keep it low.
const DOWNLOAD_CONCURRENCY: usize = 2;

const USER_AGENT: &str = "CelesteNixIndexer/2.0 (contact: GitHub @airone01)";

// --- DATA STRUCTURES ---

#[derive(Debug, Deserialize)]
struct GbModIndexResponse {
    #[serde(rename = "_aRecords")]
    records: Vec<GbModRecord>,
}

#[derive(Debug, Deserialize, Clone)]
struct GbModRecord {
    #[serde(rename = "_idRow")]
    id: i64,
    #[serde(rename = "_sName")]
    name: String,
}

#[derive(Debug, Deserialize, Clone)]
struct GbFileRecord {
    #[serde(rename = "_idRow")]
    file_id: i64,
    #[serde(rename = "_tsDateAdded")]
    date_added: Option<i64>,
    #[serde(rename = "_sFile")]
    file_name: String,
}

#[derive(Debug, Clone)]
struct Job {
    mod_id: i64,
    mod_name: String,
    file: GbFileRecord,
    url: String,
}

// --- HELPER FUNCTIONS ---

// Sleep helper to enforce the rate limit manually and strictly
async fn polite_sleep() {
    tokio::time::sleep(Duration::from_millis(REQUEST_INTERVAL_MS)).await;
}

// 1. Fetch all Mod IDs for Celeste
async fn fetch_all_mod_ids(client: &Client, mp: &MultiProgress) -> Result<Vec<GbModRecord>> {
    let pb = mp.add(ProgressBar::new_spinner());
    pb.set_style(ProgressStyle::default_spinner().template("{spinner:.blue} {msg}")?);
    pb.set_message("Fetching Mod List...");
    pb.tick();

    let mut all_mods = Vec::new();
    let mut page = 1;
    let per_page = 50;

    loop {
        let url = format!(
            "https://gamebanana.com/apiv11/Mod/Index?_nPage={}&_nPerpage={}&_aFilters[Generic_Game]={}",
            page, per_page, GAME_ID
        );

        let resp = client.get(&url).send().await?;

        if resp.status() == StatusCode::TOO_MANY_REQUESTS {
            pb.set_message("Hit 429 during discovery. Sleeping 60s...");
            tokio::time::sleep(Duration::from_secs(60)).await;
            continue;
        }

        if !resp.status().is_success() {
            break;
        }

        let body: GbModIndexResponse = resp.json().await?;
        if body.records.is_empty() {
            break;
        }

        let count = body.records.len();
        all_mods.extend(body.records);
        pb.set_message(format!(
            "Fetched page {} (Total mods: {})",
            page,
            all_mods.len()
        ));

        if count < per_page {
            break;
        }
        page += 1;

        polite_sleep().await; // Be polite between pages
    }

    pb.finish_with_message(format!("Found {} mods total.", all_mods.len()));
    Ok(all_mods)
}

// 2. Fetch file metadata for a SINGLE batch (Sequential)
async fn fetch_file_metadata_batch_sequential(
    client: &Client,
    mods: &[GbModRecord],
    batch_idx: usize,
    total_batches: usize,
    pb: &ProgressBar,
) -> Result<Vec<Job>> {
    if mods.is_empty() {
        return Ok(vec![]);
    }

    let ids: Vec<String> = mods.iter().map(|m| m.id.to_string()).collect();
    let mut params: Vec<(String, String)> = vec![
        ("itemtype".to_string(), "Mod".to_string()),
        ("fields".to_string(), "Files().aFiles()".to_string()),
    ];
    for id in &ids {
        params.push(("itemid[]".to_string(), id.clone()));
    }

    loop {
        // Update status so user knows we are moving
        pb.set_message(format!("Batch {}/{}", batch_idx + 1, total_batches));

        // Strict sleep BEFORE request
        polite_sleep().await;

        let resp = client
            .get("https://api.gamebanana.com/Core/Item/Data")
            .query(&params)
            .send()
            .await?;

        if resp.status() == StatusCode::TOO_MANY_REQUESTS {
            pb.println(format!("429 on Batch {}. Sleeping 60s...", batch_idx + 1));
            tokio::time::sleep(Duration::from_secs(60)).await;
            continue;
        }

        if !resp.status().is_success() {
            return Err(anyhow::anyhow!("HTTP {}", resp.status()));
        }

        let root: serde_json::Value = resp.json().await?;
        let json_response = root
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("Invalid API response"))?;

        let mut jobs = Vec::new();
        for (i, item_val) in json_response.iter().enumerate() {
            if let Some(mod_record) = mods.get(i) {
                if let Some(file_map) = item_val.as_object() {
                    for (_key, val) in file_map {
                        if let Ok(file_rec) = serde_json::from_value::<GbFileRecord>(val.clone()) {
                            let dl_url = format!("https://gamebanana.com/dl/{}", file_rec.file_id);
                            jobs.push(Job {
                                mod_id: mod_record.id,
                                mod_name: mod_record.name.clone(),
                                file: file_rec,
                                url: dl_url,
                            });
                        }
                    }
                }
            }
        }
        return Ok(jobs);
    }
}

// --- DOWNLOAD/HASHING LOGIC ---

fn get_version_from_zip<R: Read + Seek>(reader: R) -> Result<String> {
    let mut archive = ZipArchive::new(reader)?;
    let mut content = String::new();

    let found = if let Ok(mut file) = archive.by_name("everest.yaml") {
        file.read_to_string(&mut content)?;
        true
    } else {
        false
    };

    if !found {
        let mut file = archive.by_name("everest.yml")?;
        file.read_to_string(&mut content)?;
    }

    for line in content.lines() {
        let line = line.trim();
        if line.starts_with("Version:") {
            let parts: Vec<&str> = line.splitn(2, ':').collect();
            if parts.len() == 2 {
                return Ok(parts[1].trim().to_string());
            }
        }
    }

    Err(anyhow::anyhow!("Version key not found"))
}

async fn fetch_hash_and_metadata(
    client: &Client,
    url: &str,
    fallback_version: &str,
) -> Result<(String, String)> {
    let res = client.get(url).send().await?;

    if res.status() == StatusCode::TOO_MANY_REQUESTS {
        return Err(anyhow::anyhow!("429"));
    }

    if !res.status().is_success() {
        return Err(anyhow::anyhow!("HTTP {}", res.status()));
    }

    let mut temp_file = NamedTempFile::new()?;
    let mut hasher = Sha256::new();
    let mut stream = res.bytes_stream();

    while let Some(chunk) = stream.next().await {
        let chunk = chunk.context("Stream broke")?;
        hasher.update(&chunk);
        temp_file.write_all(&chunk)?;
    }

    let hash = hasher.finalize();
    use base64::{engine::general_purpose, Engine as _};
    let b64 = general_purpose::STANDARD.encode(hash);
    let sri_hash = format!("sha256-{}", b64);

    temp_file.rewind()?;

    let version = match get_version_from_zip(&temp_file) {
        Ok(v) => v,
        Err(_) => fallback_version.to_string(),
    };

    Ok((sri_hash, version))
}

async fn process_single_job(
    job: Job,
    pool: SqlitePool,
    client: Client,
    pb: ProgressBar,
    // No shared limiter passed here, we use internal sleep
) {
    pb.inc(1);
    if job.file.file_id == 0 {
        return;
    }

    let exists = sqlx::query("SELECT 1 FROM mods WHERE file_id = ?")
        .bind(job.file.file_id)
        .fetch_optional(&pool)
        .await;

    if let Ok(Some(_)) = exists {
        pb.set_message(format!("Skipping {}", job.mod_name));
        return;
    }

    let date_ts = job.file.date_added.unwrap_or(0);
    let fallback_version = format!("0.0.0+{}", date_ts);

    pb.set_message(format!("Hashing: {}", job.mod_name));

    // Wait before starting download to avoid burst
    polite_sleep().await;

    let mut attempts = 0;
    loop {
        match fetch_hash_and_metadata(&client, &job.url, &fallback_version).await {
            Ok((sri_hash, real_version)) => {
                let res = sqlx::query(
                    "INSERT INTO mods (file_id, gb_id, name, version, url, sri_hash) VALUES (?, ?, ?, ?, ?, ?)"
                )
                .bind(job.file.file_id)
                .bind(job.mod_id)
                .bind(&job.mod_name)
                .bind(&real_version)
                .bind(&job.url)
                .bind(&sri_hash)
                .execute(&pool)
                .await;

                if let Err(e) = res {
                    pb.println(format!("DB Write Error {}: {}", job.mod_name, e));
                }
                break;
            }
            Err(e) => {
                let msg = e.to_string();
                if msg.contains("429") {
                    pb.println(format!("429 on download {}. Sleeping 60s...", job.mod_name));
                    tokio::time::sleep(Duration::from_secs(60)).await;
                } else {
                    attempts += 1;
                    if attempts >= 3 {
                        pb.println(format!("FAILED {} ({}): {}", job.mod_name, job.url, e));
                        break;
                    }
                    tokio::time::sleep(Duration::from_secs(5)).await;
                }
            }
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    println!("Started celeste-nix-indexer (Safe Mode)");

    let pool = SqlitePool::connect("sqlite:celeste_lock.db?mode=rwc").await?;
    sqlx::query("PRAGMA journal_mode=WAL;")
        .execute(&pool)
        .await?;
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS mods (
            file_id INTEGER PRIMARY KEY,
            gb_id INTEGER, 
            name TEXT,
            version TEXT,
            url TEXT,
            sri_hash TEXT,
            last_checked TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )",
    )
    .execute(&pool)
    .await?;

    // 10 second timeout for connections
    let client = Client::builder()
        .user_agent(USER_AGENT)
        .timeout(Duration::from_secs(15))
        .build()?;

    let mp = MultiProgress::new();

    // --- PHASE 1: DISCOVERY ---
    let all_mods = fetch_all_mod_ids(&client, &mp).await?;

    // --- PHASE 2: METADATA FETCHING (SEQUENTIAL) ---
    // We do this strictly sequentially to avoid the 429
    let meta_pb = mp.add(ProgressBar::new(all_mods.len() as u64));
    meta_pb.set_style(
        ProgressStyle::default_bar()
            .template(
                "{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {pos}/{len} {msg}",
            )?
            .progress_chars("#>-"),
    );
    meta_pb.tick();

    let chunk_size = 20;
    let mut all_jobs = Vec::new();
    let chunks: Vec<Vec<GbModRecord>> = all_mods.chunks(chunk_size).map(|c| c.to_vec()).collect();
    let total_chunks = chunks.len();

    // SEQUENTIAL LOOP - No concurrency here
    for (i, chunk) in chunks.iter().enumerate() {
        match fetch_file_metadata_batch_sequential(&client, chunk, i, total_chunks, &meta_pb).await
        {
            Ok(jobs) => {
                all_jobs.extend(jobs);
                meta_pb.inc(chunk.len() as u64);
            }
            Err(e) => {
                meta_pb.println(format!("Failed batch {}: {}", i, e));
            }
        }
    }
    meta_pb.finish_with_message("Metadata fetched!");

    println!("Found {} files to process.", all_jobs.len());

    // --- PHASE 3: PROCESSING (LOW CONCURRENCY) ---
    let pb = mp.add(ProgressBar::new(all_jobs.len() as u64));
    pb.set_style(ProgressStyle::default_bar()
        .template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {pos}/{len} ({eta}) {msg}")?
        .progress_chars("#>-"));

    // We use a stream buffer for downloads, but keep it very low (2 concurrent)
    futures_util::stream::iter(all_jobs)
        .map(|job| {
            let pool = pool.clone();
            let client = client.clone();
            let pb = pb.clone();

            tokio::spawn(async move { process_single_job(job, pool, client, pb).await })
        })
        .buffer_unordered(DOWNLOAD_CONCURRENCY)
        .collect::<Vec<_>>()
        .await;

    pb.finish_with_message("Done!");
    Ok(())
}
