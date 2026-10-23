//! One scan owner, bounded worker results and shared full/incremental traversal.

use super::{Backend, library_extension, modified_time, scan_time};
use cap_std::fs::OpenOptions;
use serde::Serialize;
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};
use std::io::{BufRead, BufReader, BufWriter, Read, Write};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Condvar, Mutex, TryLockError, mpsc};
use std::thread;
use std::time::Duration;

type Check<'a> = &'a (dyn Fn() -> Result<(), String> + Sync);

/// How often a paused scan re-checks backend shutdown and its request lease.
const PAUSE_POLL: Duration = Duration::from_millis(250);

#[derive(Default)]
pub(in crate::backend) struct ScanState {
    current: Mutex<Option<Arc<Run>>>,
    owner: Mutex<()>,
    // Pausing is scan-wide rather than per run so a pause requested just
    // before the native scan starts still holds it at its first checkpoint.
    paused: Mutex<bool>,
    resumed: Condvar,
}

#[derive(Default)]
struct Run {
    cancelled: AtomicBool,
    failure: Mutex<Option<String>>,
    progress: Mutex<Progress>,
}

#[derive(Default, Serialize)]
struct Progress {
    total_files: usize,
    scanned_files: usize,
    current_file: String,
    error_count: usize,
    progress_pct: f64,
    is_complete: bool,
}

struct AudioFile {
    path: String,
    modified: i64,
    size: u64,
}

struct ScanSummary {
    deleted: Vec<String>,
    skipped: usize,
    total: usize,
    run: Arc<Run>,
}

impl Backend {
    pub fn get_library_scan_progress(&self) -> Result<Value, String> {
        let _operation = self.enter()?;
        let current = self.library_scan.current.lock().expect("library scan lock");
        let value = match current.as_ref() {
            Some(run) => serde_json::to_value(&*run.progress.lock().expect("scan progress lock")),
            None => serde_json::to_value(Progress::default()),
        };
        value.map_err(|error| error.to_string())
    }

    pub fn cancel_library_scan(&self) -> Result<(), String> {
        let _operation = self.enter()?;
        if let Some(run) = self
            .library_scan
            .current
            .lock()
            .expect("library scan lock")
            .as_ref()
        {
            run.cancelled.store(true, Ordering::Release);
        }
        // Wake paused workers so they observe the cancellation.
        self.set_library_scan_paused(false);
        Ok(())
    }

    /// Holds the scan at its next checkpoint. Workers keep their position in
    /// memory, so [`Self::resume_library_scan`] continues with the next file.
    pub fn pause_library_scan(&self) -> Result<(), String> {
        let _operation = self.enter()?;
        self.set_library_scan_paused(true);
        Ok(())
    }

    pub fn resume_library_scan(&self) -> Result<(), String> {
        let _operation = self.enter()?;
        self.set_library_scan_paused(false);
        Ok(())
    }

    fn set_library_scan_paused(&self, paused: bool) {
        *self
            .library_scan
            .paused
            .lock()
            .expect("library scan pause lock") = paused;
        self.library_scan.resumed.notify_all();
    }

    fn wait_while_library_scan_paused(&self, run: &Run, check: Check<'_>) -> Result<(), String> {
        let state = &self.library_scan;
        let mut paused = state.paused.lock().expect("library scan pause lock");
        while *paused && !run.cancelled.load(Ordering::Acquire) {
            paused = state
                .resumed
                .wait_timeout(paused, PAUSE_POLL)
                .expect("library scan pause lock")
                .0;
            if *paused {
                drop(paused);
                // Shutdown and released request leases still end a paused scan.
                self.check()?;
                check()?;
                paused = state.paused.lock().expect("library scan pause lock");
            }
        }
        Ok(())
    }

    pub fn scan_library_folder_incremental(
        &self,
        folder: &str,
        existing_json: &str,
        check: Check<'_>,
    ) -> Result<Value, String> {
        // Go tolerates invalid snapshot JSON. A bad value does not discard other
        // valid paths from an otherwise well-formed object.
        let value: Value = serde_json::from_str(existing_json).unwrap_or(Value::Null);
        let existing = value
            .as_object()
            .map(|object| {
                object
                    .iter()
                    .filter_map(|(path, value)| {
                        value
                            .as_i64()
                            .or_else(|| value.is_null().then_some(0))
                            .map(|value| (path.clone(), value))
                    })
                    .collect()
            })
            .unwrap_or_default();
        self.incremental(folder, existing, check)
    }

    pub fn scan_library_folder_incremental_from_snapshot(
        &self,
        folder: &str,
        snapshot: &str,
        check: Check<'_>,
    ) -> Result<Value, String> {
        let _operation = self.enter()?;
        let mut existing = BTreeMap::new();
        if !snapshot.is_empty() {
            self.check()?;
            check()?;
            let input = self.files()?.resolve_legacy(snapshot)?;
            input.native_display()?;
            let file = input
                .open(OpenOptions::new().read(true))
                .map_err(|error| format!("failed to load incremental snapshot: {error}"))?;
            let mut reader = BufReader::new(file);
            let mut line = Vec::new();
            loop {
                self.check()?;
                check()?;
                line.clear();
                let read = (&mut reader)
                    .take(64 * 1024)
                    .read_until(b'\n', &mut line)
                    .map_err(|error| format!("failed to load incremental snapshot: {error}"))?;
                if read == 0 {
                    break;
                }
                if read == 64 * 1024 && line.last() != Some(&b'\n') {
                    return Err(
                        "failed to load incremental snapshot: bufio.Scanner: token too long".into(),
                    );
                }
                if line.last() == Some(&b'\n') {
                    line.pop();
                }
                if line.last() == Some(&b'\r') {
                    line.pop();
                }
                let line = String::from_utf8_lossy(&line);
                if let Some((time, path)) = line.split_once('\t')
                    && let Ok(time) = time.parse::<i64>()
                {
                    existing.insert(path.into(), time);
                }
            }
        }
        self.incremental(folder, existing, check)
    }

    fn incremental(
        &self,
        folder: &str,
        existing: BTreeMap<String, i64>,
        check: Check<'_>,
    ) -> Result<Value, String> {
        let mut tracks = Vec::new();
        let summary = self.scan_library(
            folder,
            Some(&existing),
            true,
            &mut |value| {
                tracks.push(value);
                Ok(())
            },
            check,
        )?;
        Ok(
            json!({"scanned":tracks,"deletedPaths":if summary.deleted.is_empty() { Value::Null } else { json!(summary.deleted) },"skippedCount":summary.skipped,"totalFiles":summary.total}),
        )
    }

    pub fn scan_library_folder_to_ndjson_file(
        &self,
        folder: &str,
        output: &str,
        check: Check<'_>,
    ) -> Result<u64, String> {
        let _operation = self.enter()?;
        let check = || self.check().and_then(|()| check());
        check()?;
        if output.is_empty() {
            return Err("output path is empty".into());
        }
        if supported(output) {
            return Err("scan output must not overwrite an audio or CUE file".into());
        }
        let files = self.files()?;
        let output = files.resolve_legacy(output)?;
        output.native_display()?;
        let _lock = files.lock(&output, &check)?;
        let mut stage = output
            .stage_existing_parent()
            .map_err(|error| format!("create scan output: {error}"))?;
        let mut count = 0;
        let summary;
        {
            let mut writer = BufWriter::with_capacity(64 * 1024, &mut stage.file);
            summary = self.scan_library(
                folder,
                None,
                false,
                &mut |value| {
                    serde_json::to_writer(&mut writer, &value)
                        .map_err(|error| error.to_string())?;
                    writer.write_all(b"\n").map_err(|error| error.to_string())?;
                    count += 1;
                    Ok(())
                },
                &check,
            )?;
            writer
                .flush()
                .map_err(|error| format!("flush scan output: {error}"))?;
        }
        stage.publish(&|| {
            check()?;
            if summary.run.cancelled.load(Ordering::Acquire) {
                Err("scan cancelled".into())
            } else {
                Ok(())
            }
        })?;
        Ok(count)
    }

    fn collect_library_files(
        &self,
        folder: &str,
        check: Check<'_>,
    ) -> Result<Vec<AudioFile>, String> {
        let files = self.files()?;
        // Each entry records whether its parent directory was already
        // validated. Children then need one lstat of their own name instead of
        // re-checking every ancestor plus two more stats per file; on FUSE SD
        // cards, USB drives and network mounts each of those is a round trip.
        let mut pending = vec![(folder.to_owned(), false)];
        let mut collected = Vec::new();
        while let Some((path, parent_validated)) = pending.pop() {
            check()?;
            let input = files.resolve_legacy(&path)?;
            let metadata = if parent_validated {
                input.native_child_metadata().map_err(|error| {
                    if error.kind() == std::io::ErrorKind::NotFound {
                        format!("walk library path {path}: {error}")
                    } else {
                        error.to_string()
                    }
                })?
            } else {
                input.native_display()?;
                input
                    .metadata()
                    .map_err(|error| format!("walk library path {path}: {error}"))?
            };
            if metadata.is_dir() {
                let entries = input
                    .entries()
                    .map_err(|error| format!("walk library path {path}: {error}"))?;
                for (name, directory) in entries.into_iter().rev() {
                    if !directory && (!supported(&name) || staging(&name)) {
                        continue;
                    }
                    pending.push((
                        crate::files::clean(&Path::new(&path).join(name))
                            .to_string_lossy()
                            .into_owned(),
                        true,
                    ));
                }
            } else if supported(&path) && !staging(&path) {
                collected.push(AudioFile {
                    path,
                    modified: modified_time(&metadata),
                    size: metadata.len(),
                });
            }
        }
        Ok(collected)
    }

    fn scan_library(
        &self,
        folder: &str,
        existing: Option<&BTreeMap<String, i64>>,
        ordered: bool,
        sink: &mut dyn FnMut(Value) -> Result<(), String>,
        check: Check<'_>,
    ) -> Result<ScanSummary, String> {
        let _operation = self.enter()?;
        check()?;
        if folder.is_empty() {
            return Err("folder path is empty".into());
        }
        // Retain the app data capability for this scan instead of reopening its
        // directory for every track. Path resolution still checks live grants.
        let files = self.files()?;
        let input = files.resolve_legacy(folder)?;
        input.native_display()?;
        let metadata = input
            .metadata()
            .map_err(|error| format!("folder not found: {error}"))?;
        if !metadata.is_dir() {
            return Err(format!("path is not a folder: {folder}"));
        }
        let run = Arc::new(Run::default());
        if let Some(previous) = self
            .library_scan
            .current
            .lock()
            .expect("library scan lock")
            .as_ref()
        {
            previous.cancelled.store(true, Ordering::Release);
        }
        let request_check = check;
        let check = || {
            // Wait before taking the failure lock so paused workers do not
            // serialize on it.
            self.wait_while_library_scan_paused(&run, check)?;
            let mut failure = run.failure.lock().expect("scan failure lock");
            if let Some(error) = failure.as_ref() {
                return Err(error.clone());
            }
            let result = self.check().and_then(|()| {
                if run.cancelled.load(Ordering::Acquire) {
                    Err("scan cancelled".into())
                } else {
                    check()
                }
            });
            if let Err(error) = &result {
                *failure = Some(error.clone());
            }
            result
        };
        let _owner = loop {
            // Acquire ownership and publish the run before honoring pause;
            // otherwise a pre-paused first scan has no visible cancel target.
            self.check().and_then(|()| request_check())?;
            if run.cancelled.load(Ordering::Acquire) {
                return Err("scan cancelled".into());
            }
            match self.library_scan.owner.try_lock() {
                Ok(owner) => break owner,
                Err(TryLockError::WouldBlock) => thread::sleep(Duration::from_millis(5)),
                Err(TryLockError::Poisoned(_)) => return Err("library scan owner poisoned".into()),
            }
        };
        // Publish progress only once this run owns traversal. A queued run
        // must not reset the active run's progress or cancellation target.
        self.library_scan
            .current
            .lock()
            .expect("library scan lock")
            .replace(run.clone());
        let current = self.collect_library_files(folder, &check)?;
        let total = current.len();
        run.progress.lock().expect("scan progress lock").total_files = total;
        let paths: BTreeSet<_> = current.iter().map(|file| file.path.as_str()).collect();
        let mut cue_times = BTreeMap::new();
        let mut deleted = Vec::new();
        if let Some(existing) = existing {
            for (path, time) in existing {
                let base = cue_base(path);
                if let Some(base) = base {
                    cue_times.entry(base).or_insert(*time);
                }
                if !paths.contains(base.unwrap_or(path)) {
                    deleted.push(path.clone());
                }
            }
        }
        let mut skipped = 0;
        let tasks: Vec<_> = current
            .iter()
            .filter(|file| {
                let old = existing
                    .and_then(|existing| existing.get(&file.path))
                    .copied()
                    .or_else(|| {
                        (library_extension(&file.path, "") == "cue")
                            .then(|| cue_times.get(file.path.as_str()).copied())
                            .flatten()
                    });
                // Snapshots contain only sheet timestamps, not audio versions.
                // Re-read CUE dependencies rather than trust a stale sheet.
                if old == Some(file.modified) && library_extension(&file.path, "") != "cue" {
                    skipped += 1;
                    false
                } else {
                    true
                }
            })
            .collect();
        let time = scan_time();
        let mut referenced = BTreeSet::new();
        let mut parsed = BTreeMap::new();
        // An unchanged CUE still owns its backing audio. Inspect all current
        // sheets so incremental scans never re-add that audio as a full album.
        for file in &current {
            check()?;
            if library_extension(&file.path, "") == "cue"
                && let Ok(sheet) = self.parse_cue_file(&file.path, &check)
                && !sheet.file_name.is_empty()
                && let Ok(audio) = self.resolve_cue_audio(&file.path, &sheet.file_name, "", &check)
            {
                referenced.insert(audio.clone());
                parsed.insert(file.path.as_str(), (sheet, audio));
            }
        }
        check()?;
        let mut results: BTreeMap<usize, Vec<Value>> = BTreeMap::new();
        let mut audio = Vec::new();
        let mut completed = skipped;
        for (index, file) in tasks.iter().enumerate() {
            check()?;
            if library_extension(&file.path, "") == "cue" {
                let result = match parsed.get(file.path.as_str()) {
                    Some((sheet, audio)) => self.scan_cue_sheet(
                        &file.path,
                        sheet,
                        audio,
                        "",
                        file.modified,
                        "",
                        &time,
                        &check,
                    ),
                    None => self.scan_cue_file_for_library(
                        &file.path,
                        "",
                        "",
                        file.modified,
                        "",
                        &time,
                        &check,
                    ),
                }
                .map(|value| value.as_array().expect("cue track array").clone());
                check()?;
                completed += 1;
                update(&run, completed, &file.path, result.is_err());
                if let Ok(tracks) = result {
                    if ordered {
                        results.insert(index, tracks);
                    } else {
                        for value in tracks {
                            sink(value)?;
                        }
                    }
                }
            } else if referenced.contains(&file.path) {
                completed += 1;
                update(&run, completed, &file.path, false);
            } else {
                audio.push((index, *file));
            }
        }
        // Allow short bursts without parking workers after each result. At most
        // 96 completed tracks wait; NDJSON still uses bounded memory. Tag reads
        // mostly wait on storage, so slow media benefits from more files in
        // flight than the core count; artwork decoding stays serialized.
        let workers = if audio.len() < 16 {
            1
        } else {
            thread::available_parallelism()
                .map_or(2, usize::from)
                .clamp(2, 6)
        };
        let next = AtomicUsize::new(0);
        let stop = AtomicBool::new(false);
        thread::scope(|scope| -> Result<(), String> {
            let (sender, receiver) = mpsc::sync_channel(workers * 16);
            for _ in 0..workers {
                let sender = sender.clone();
                let (audio, next, stop, check, time, files) =
                    (&audio, &next, &stop, &check, &time, &files);
                scope.spawn(move || {
                    while !stop.load(Ordering::Acquire) {
                        let Some((index, file)) = audio.get(next.fetch_add(1, Ordering::AcqRel))
                        else {
                            break;
                        };
                        let result = check().and_then(|()| {
                            self.scan_audio_file(
                                files,
                                &file.path,
                                "",
                                &format!("{}|{}|{}", file.path, file.size, file.modified),
                                time,
                                file.modified,
                                check,
                            )
                        });
                        if sender.send((*index, file.path.as_str(), result)).is_err() {
                            break;
                        }
                    }
                });
            }
            drop(sender);
            let mut failure = None;
            for (index, path, result) in receiver {
                completed += 1;
                update(&run, completed, path, result.is_err());
                if failure.is_none() {
                    let emit = check().and_then(|()| {
                        if let Ok(value) = result {
                            if ordered {
                                results.insert(index, vec![value]);
                            } else {
                                sink(value)?;
                            }
                        }
                        Ok(())
                    });
                    if let Err(error) = emit {
                        failure = Some(error);
                        stop.store(true, Ordering::Release);
                    }
                }
            }
            failure.map_or(Ok(()), Err)
        })?;
        check()?;
        for (_, values) in results {
            for value in values {
                check()?;
                sink(value)?;
            }
        }
        check()?;
        let mut progress = run.progress.lock().expect("scan progress lock");
        progress.scanned_files = total;
        progress.is_complete = true;
        progress.progress_pct = 100.0;
        drop(progress);
        Ok(ScanSummary {
            deleted,
            skipped,
            total,
            run,
        })
    }
}

fn cue_base(path: &str) -> Option<&str> {
    let (base, number) = path.rsplit_once("#track")?;
    (!number.is_empty()
        && number.bytes().all(|b| b.is_ascii_digit())
        && library_extension(base, "") == "cue")
        .then_some(base)
}

fn supported(path: &str) -> bool {
    matches!(
        library_extension(path, "").as_str(),
        "flac"
            | "m4a"
            | "mp4"
            | "aac"
            | "mp3"
            | "opus"
            | "ogg"
            | "ape"
            | "wv"
            | "mpc"
            | "wav"
            | "aiff"
            | "aif"
            | "dsf"
            | "dff"
            | "cue"
    )
}

fn staging(path: &str) -> bool {
    let name = Path::new(path)
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_lowercase();
    name.ends_with(".partial")
        || name
            .rsplit_once('.')
            .is_some_and(|(stem, _)| stem.ends_with(".partial"))
}

fn update(run: &Run, completed: usize, path: &str, error: bool) {
    let mut progress = run.progress.lock().expect("scan progress lock");
    progress.scanned_files = completed;
    progress.current_file = Path::new(path)
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .into_owned();
    progress.error_count += usize::from(error);
    if progress.total_files > 0 {
        progress.progress_pct = completed as f64 / progress.total_files as f64 * 100.0;
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::fs;

    fn backend(root: &Path, library: &Path) -> Backend {
        let backend = Backend::new(&root.join("data")).unwrap();
        backend
            .set_allowed_directories(&[library.to_path_buf()])
            .unwrap();
        backend
    }

    fn walk(backend: &Backend, folder: &Path) -> Result<Vec<AudioFile>, String> {
        backend.collect_library_files(&folder.to_string_lossy(), &|| Ok(()))
    }

    #[test]
    fn walk_keeps_order_size_and_time_with_one_stat_per_child() {
        let root = tempfile::tempdir().unwrap();
        let library = fs::canonicalize(root.path()).unwrap().join("library");
        fs::create_dir_all(library.join("A/B")).unwrap();
        fs::write(library.join("A/B/song.flac"), b"flac bytes").unwrap();
        fs::write(library.join("A/c.mp3"), b"mp3").unwrap();
        fs::write(library.join("notes.txt"), b"ignored").unwrap();
        fs::write(library.join("x.partial.flac"), b"staging").unwrap();
        let backend = backend(root.path(), &library);

        let files = walk(&backend, &library).unwrap();

        let expected = [library.join("A/B/song.flac"), library.join("A/c.mp3")];
        assert_eq!(
            files
                .iter()
                .map(|file| file.path.clone())
                .collect::<Vec<_>>(),
            expected
                .iter()
                .map(|path| path.to_string_lossy().into_owned())
                .collect::<Vec<_>>(),
        );
        for (file, path) in files.iter().zip(&expected) {
            let metadata = fs::metadata(path).unwrap();
            let modified = metadata
                .modified()
                .unwrap()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_millis() as i64;
            assert_eq!(file.size, metadata.len());
            assert_eq!(file.modified, modified);
        }
    }

    #[test]
    fn walk_still_rejects_nested_symlinks() {
        let root = tempfile::tempdir().unwrap();
        let library = fs::canonicalize(root.path()).unwrap().join("library");
        fs::create_dir_all(library.join("A")).unwrap();
        fs::write(library.join("A/song.flac"), b"flac").unwrap();
        std::os::unix::fs::symlink(library.join("A/song.flac"), library.join("A/link.flac"))
            .unwrap();
        let backend = backend(root.path(), &library);

        let error = walk(&backend, &library).err().expect("linked file");
        assert_eq!(
            error,
            "native media path must not contain symlinks or special files"
        );

        fs::remove_file(library.join("A/link.flac")).unwrap();
        // A linked directory with an audio-like name reaches the stat check.
        std::os::unix::fs::symlink(library.join("A"), library.join("B.flac")).unwrap();
        let error = walk(&backend, &library).err().expect("linked directory");
        assert_eq!(
            error,
            "native media path must not contain symlinks or special files"
        );
    }

    fn paused_library(root: &Path) -> (Backend, String) {
        let library = fs::canonicalize(root).unwrap().join("library");
        fs::create_dir_all(&library).unwrap();
        for index in 0..3 {
            fs::write(library.join(format!("{index}.mp3")), b"not audio").unwrap();
        }
        let backend = backend(root, &library);
        backend.pause_library_scan().unwrap();
        (backend, library.to_string_lossy().into_owned())
    }

    fn wait_for_run(backend: &Backend) {
        while backend
            .library_scan
            .current
            .lock()
            .expect("library scan lock")
            .is_none()
        {
            thread::sleep(Duration::from_millis(5));
        }
    }

    #[test]
    fn paused_scan_holds_its_position_until_resumed() {
        let root = tempfile::tempdir().unwrap();
        let (backend, folder) = paused_library(root.path());

        thread::scope(|scope| {
            let scan =
                scope.spawn(|| backend.scan_library_folder_incremental(&folder, "{}", &|| Ok(())));
            wait_for_run(&backend);
            thread::sleep(Duration::from_millis(300));
            assert!(!scan.is_finished());
            let progress = backend.get_library_scan_progress().unwrap();
            assert_eq!(progress["scanned_files"], 0);
            assert_eq!(progress["is_complete"], false);

            backend.resume_library_scan().unwrap();
            let result = scan.join().unwrap().unwrap();
            assert_eq!(result["totalFiles"], 3);
        });
        let progress = backend.get_library_scan_progress().unwrap();
        assert_eq!(progress["scanned_files"], 3);
        assert_eq!(progress["is_complete"], true);
    }

    #[test]
    fn cancel_releases_a_paused_scan() {
        let root = tempfile::tempdir().unwrap();
        let (backend, folder) = paused_library(root.path());

        thread::scope(|scope| {
            let scan =
                scope.spawn(|| backend.scan_library_folder_incremental(&folder, "{}", &|| Ok(())));
            wait_for_run(&backend);
            backend.cancel_library_scan().unwrap();
            assert_eq!(scan.join().unwrap().unwrap_err(), "scan cancelled");
        });
        // Cancelling also clears the pause, so the next scan is not held.
        let result = backend
            .scan_library_folder_incremental(&folder, "{}", &|| Ok(()))
            .unwrap();
        assert_eq!(result["totalFiles"], 3);
    }

    #[test]
    fn shutdown_releases_a_paused_scan_and_rejects_new_work() {
        let root = tempfile::tempdir().unwrap();
        let (backend, folder) = paused_library(root.path());
        thread::scope(|scope| {
            let scan =
                scope.spawn(|| backend.scan_library_folder_incremental(&folder, "{}", &|| Ok(())));
            wait_for_run(&backend);
            backend.shutdown();
            assert_eq!(scan.join().unwrap().unwrap_err(), "local backend is closed");
        });
        assert!(
            backend
                .scan_library_folder_incremental(&folder, "{}", &|| Ok(()))
                .is_err()
        );
    }
}

#[cfg(all(test, unix))]
mod t4_tests {
    use super::*;
    use std::fs;
    fn wav(seconds: u32) -> Vec<u8> {
        let size = 44_100 * 2 * seconds;
        let mut output = b"RIFF".to_vec();
        output.extend((36 + size).to_le_bytes());
        output.extend(b"WAVEfmt ");
        output.extend(16u32.to_le_bytes());
        output.extend(1u16.to_le_bytes());
        output.extend(1u16.to_le_bytes());
        output.extend(44_100u32.to_le_bytes());
        output.extend(88_200u32.to_le_bytes());
        output.extend(2u16.to_le_bytes());
        output.extend(16u16.to_le_bytes());
        output.extend(b"data");
        output.extend(size.to_le_bytes());
        output.resize(44 + size as usize, 0);
        output
    }
    fn flac(seconds: u64) -> Vec<u8> {
        let mut output = b"fLaC\x80\0\0\x22".to_vec();
        let mut info = [0u8; 34];
        info[0..2].copy_from_slice(&4096u16.to_be_bytes());
        info[2..4].copy_from_slice(&4096u16.to_be_bytes());
        let packed = (44_100u64 << 44) | (15u64 << 36) | (44_100 * seconds);
        info[10..18].copy_from_slice(&packed.to_be_bytes());
        output.extend(info);
        output.extend([0xff, 0xf8]);
        output
    }

    #[test]
    fn incremental_cue_refreshes_changed_audio_and_keeps_real_hash_track_files() {
        for declared in ["ALBUM.FLAC", "album.İ"] {
            let root = tempfile::tempdir().unwrap();
            let library = root.path().join("library");
            fs::create_dir(&library).unwrap();
            let audio = library.join("album.flac");
            fs::write(&audio, flac(1)).unwrap();
            let physical = library.join("song#track2.wav");
            fs::write(&physical, wav(1)).unwrap();
            fs::write(library.join("album.cue"), format!("FILE \"{declared}\" WAVE\nTRACK 01 AUDIO\nTITLE \"Virtual\"\nINDEX 01 00:00:00\n")).unwrap();
            let backend = Backend::new(&root.path().join("data")).unwrap();
            backend
                .set_allowed_directories(std::slice::from_ref(&library))
                .unwrap();
            let first = backend
                .scan_library_folder_incremental(library.to_str().unwrap(), "{}", &|| Ok(()))
                .unwrap();
            let rows = first["scanned"].as_array().unwrap();
            let virtual_row = rows
                .iter()
                .find(|row| row["trackName"] == "Virtual")
                .unwrap();
            assert_eq!(virtual_row["duration"], 1);
            let existing: serde_json::Map<String, Value> = rows
                .iter()
                .map(|row| {
                    (
                        row["filePath"].as_str().unwrap().into(),
                        row["fileModTime"].clone(),
                    )
                })
                .collect();
            fs::write(&audio, flac(2)).unwrap();
            let second = backend
                .scan_library_folder_incremental(
                    library.to_str().unwrap(),
                    &Value::Object(existing).to_string(),
                    &|| Ok(()),
                )
                .unwrap();
            assert!(second["deletedPaths"].is_null());
            let rows = second["scanned"].as_array().unwrap();
            assert_eq!(
                rows.iter()
                    .find(|row| row["trackName"] == "Virtual")
                    .unwrap()["duration"],
                2
            );
            assert!(physical.exists());
        }
        assert_eq!(
            cue_base("/music/album.cue#track02"),
            Some("/music/album.cue")
        );
        for path in [
            "/music/song#track2.wav",
            "/music/song#track2",
            "/music/a.cue#trackno",
            "/music/a.cue#track2.wav",
        ] {
            assert_eq!(cue_base(path), None);
        }
    }

    #[test]
    fn waiting_scan_keeps_active_progress_until_owner_is_released() {
        let root = tempfile::tempdir().unwrap();
        let library = root.path().join("library");
        fs::create_dir(&library).unwrap();
        let backend = Backend::new(&root.path().join("data")).unwrap();
        backend
            .set_allowed_directories(std::slice::from_ref(&library))
            .unwrap();
        let active = Arc::new(Run::default());
        active.progress.lock().unwrap().scanned_files = 7;
        *backend.library_scan.current.lock().unwrap() = Some(active.clone());
        let owner = backend.library_scan.owner.lock().unwrap();
        thread::scope(|scope| {
            let waiting = scope.spawn(|| {
                backend.scan_library_folder_incremental(library.to_str().unwrap(), "{}", &|| Ok(()))
            });
            let deadline = std::time::Instant::now() + Duration::from_secs(5);
            while !active.cancelled.load(Ordering::Acquire) {
                assert!(std::time::Instant::now() < deadline);
                thread::yield_now();
            }
            assert_eq!(
                backend.get_library_scan_progress().unwrap()["scanned_files"],
                7
            );
            drop(owner);
            waiting.join().unwrap().unwrap();
        });
    }
}
