//! Host-only measurement for T10: cover-cache files and scan time for a corpus
//! where several tracks share one embedded cover.
//!
//! `cargo run --release -p sistrum-local --example cover_cache_probe -- <audio-dir> <data-dir>`
//! Use a fresh data directory for a cold run; reuse it for a warm run.
//! Existing files are never removed.

use sistrum_local::backend::Backend;
use std::path::Path;

fn main() {
    let audio_dir = std::env::args().nth(1).expect("audio directory");
    let audio_dir = Path::new(&audio_dir);
    let data_dir = std::env::args().nth(2).expect("probe data directory");
    let data_dir = Path::new(&data_dir);
    let cache_dir = data_dir.join("covers");

    let backend = Backend::new(data_dir).expect("backend");
    backend
        .set_allowed_directories(&[audio_dir.to_path_buf()])
        .expect("allowed directories");
    backend
        .set_library_cover_cache_directory("covers")
        .expect("cover cache directory");

    let mut tracks: Vec<_> = std::fs::read_dir(audio_dir)
        .expect("audio directory")
        .filter_map(|entry| entry.ok().map(|entry| entry.path()))
        .filter(|path| {
            path.extension()
                .is_some_and(|extension| extension == "flac")
        })
        .collect();
    tracks.sort();

    let started = std::time::Instant::now();
    for track in &tracks {
        let path = track.to_str().expect("track path");
        let stat = std::fs::metadata(track).expect("track metadata");
        let modified = stat
            .modified()
            .ok()
            .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|time| time.as_nanos())
            .unwrap_or(0);
        // The same per-file key the native folder scan passes.
        let key = format!("{path}|{}|{modified}", stat.len());
        let metadata = backend
            .read_audio_metadata(path, "", &key, &|| Ok(()))
            .expect("scan");
        assert!(
            metadata["coverPath"]
                .as_str()
                .is_some_and(|path| !path.is_empty()),
            "missing cover for {}",
            track.display()
        );
    }
    let elapsed = started.elapsed();

    let mut files = 0_u64;
    let mut bytes = 0_u64;
    let mut pointers = 0_u64;
    for entry in std::fs::read_dir(&cache_dir).expect("cache directory") {
        let entry = entry.expect("cache entry");
        if entry.file_type().is_ok_and(|kind| kind.is_file()) {
            if entry.file_name().to_string_lossy().ends_with(".id") {
                pointers += 1;
            } else {
                files += 1;
            }
            bytes += entry.metadata().map(|metadata| metadata.len()).unwrap_or(0);
        }
    }
    println!(
        "tracks={} cover_files={} pointers={} cover_bytes={} elapsed_ms={}",
        tracks.len(),
        files,
        pointers,
        bytes,
        elapsed.as_millis()
    );
}
