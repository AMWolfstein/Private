//! Owner of local file capabilities and in-flight scan/tag operations.
mod cover;
mod library;
mod tags;

use crate::files::{FileRegistry, LocalFiles, TemporaryGrant};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};

pub struct Backend {
    files: Arc<LocalFiles>,
    registry: Arc<FileRegistry>,
    library_cover_directory: Mutex<String>,
    library_scan: library::ScanState,
    closed: AtomicBool,
    operations: Mutex<usize>,
    idle: Condvar,
    shutdown: Mutex<()>,
}

impl Backend {
    pub fn new(data_directory: &Path) -> Result<Self, String> {
        if data_directory.as_os_str().is_empty() {
            return Err("local data directory must not be empty".into());
        }
        let registry = Arc::new(FileRegistry::default());
        let files = registry.scoped(data_directory).map_err(|e| e.to_string())?;
        Ok(Self {
            files,
            registry,
            library_cover_directory: Mutex::default(),
            library_scan: library::ScanState::default(),
            closed: AtomicBool::new(false),
            operations: Mutex::new(0),
            idle: Condvar::new(),
            shutdown: Mutex::new(()),
        })
    }

    pub fn set_allowed_directories(&self, directories: &[PathBuf]) -> Result<(), String> {
        let _operation = self.enter()?;
        self.registry
            .set_allowed_directories(directories)
            .map_err(|e| e.to_string())
    }

    pub fn grant_directory(&self, directory: &Path) -> Result<TemporaryGrant, String> {
        let _operation = self.enter()?;
        self.registry
            .grant_temporary_directory(directory)
            .map_err(|e| e.to_string())
    }

    fn files(&self) -> Result<Arc<LocalFiles>, String> {
        self.check()?;
        Ok(Arc::clone(&self.files))
    }

    pub fn shutdown(&self) {
        let _shutdown = self.shutdown.lock().expect("local shutdown lock");
        self.closed.store(true, Ordering::Release);
        let mut operations = self.operations.lock().expect("local operations lock");
        while *operations != 0 {
            operations = self.idle.wait(operations).expect("local operations wait");
        }
    }

    fn check(&self) -> Result<(), String> {
        if self.closed.load(Ordering::Acquire) {
            Err("local backend is closed".into())
        } else {
            Ok(())
        }
    }

    fn enter(&self) -> Result<Operation<'_>, String> {
        let mut operations = self.operations.lock().expect("local operations lock");
        self.check()?;
        *operations += 1;
        Ok(Operation(self))
    }
}

struct Operation<'a>(&'a Backend);
impl Drop for Operation<'_> {
    fn drop(&mut self) {
        *self.0.operations.lock().expect("local operations lock") -= 1;
        self.0.idle.notify_all();
    }
}
impl Drop for Backend {
    fn drop(&mut self) {
        self.shutdown();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::{cell::Cell, fs};

    fn wav() -> Vec<u8> {
        let mut data = b"RIFF".to_vec();
        data.extend(38_u32.to_le_bytes());
        data.extend(b"WAVEfmt ");
        data.extend(16_u32.to_le_bytes());
        data.extend(1_u16.to_le_bytes());
        data.extend(1_u16.to_le_bytes());
        data.extend(44100_u32.to_le_bytes());
        data.extend(88200_u32.to_le_bytes());
        data.extend(2_u16.to_le_bytes());
        data.extend(16_u16.to_le_bytes());
        data.extend(b"data");
        data.extend(2_u32.to_le_bytes());
        data.extend([0, 0]);
        data
    }

    #[test]
    fn local_tag_edits_preserve_audio_and_cancel_without_publishing() {
        let directory = tempfile::tempdir().unwrap();
        let backend = Backend::new(directory.path()).unwrap();
        let path = directory.path().join("track.wav");
        let original = wav();
        fs::write(&path, &original).unwrap();
        let path = path.to_str().unwrap();
        let fields = json!({"title": "Offline title", "artist": "Local artist"}).to_string();
        let count = Cell::new(0);
        assert!(
            backend
                .edit_file_metadata(path, &fields, &|| {
                    count.set(count.get() + 1);
                    if count.get() >= 8 {
                        Err("cancelled".into())
                    } else {
                        Ok(())
                    }
                })
                .is_err()
        );
        assert_eq!(fs::read(path).unwrap(), original);
        assert_eq!(fs::read_dir(directory.path()).unwrap().count(), 1);
        assert_eq!(
            backend
                .edit_file_metadata(path, &fields, &|| Ok(()))
                .unwrap()["method"],
            "native_wav"
        );
        let mut file = std::fs::File::open(path).unwrap();
        let metadata =
            sistrum_core::tags::read_file_metadata(&mut file, path, "", &|| Ok(())).unwrap();
        assert_eq!(metadata["title"], "Offline title");
        assert!(
            fs::read(path)
                .unwrap()
                .windows(10)
                .any(|chunk| chunk == b"data\x02\0\0\0\0\0")
        );
    }

    #[test]
    fn directory_grant_release_and_shutdown_block_future_local_operations() {
        let directory = tempfile::tempdir().unwrap();
        let media = tempfile::tempdir().unwrap();
        let backend = Backend::new(directory.path()).unwrap();
        let path = media.path().join("track.wav");
        fs::write(&path, wav()).unwrap();
        let path = path.to_str().unwrap();
        assert!(
            backend
                .read_audio_metadata(path, "", "", &|| Ok(()))
                .is_err()
        );
        let grant = backend.grant_directory(media.path()).unwrap();
        assert!(
            backend
                .read_audio_metadata(path, "", "", &|| Ok(()))
                .is_ok()
        );
        drop(grant);
        assert!(
            backend
                .read_audio_metadata(path, "", "", &|| Ok(()))
                .is_err()
        );
        backend.shutdown();
        backend.shutdown();
        assert!(backend.grant_directory(media.path()).is_err());
        assert!(
            backend
                .set_allowed_directories(&[media.path().into()])
                .is_err()
        );
    }
}
