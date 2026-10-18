use std::path::Path;
use std::sync::{Arc, Mutex};

#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum LocalBackendError {
    #[error("{0}")]
    Operation(String),
}

/// Owns local scanning and atomic tag edits; no credentials or network runtime.
#[derive(uniffi::Object)]
pub struct LocalBackend {
    pub(crate) inner: spotiflac_local::backend::Backend,
}

#[derive(uniffi::Object)]
pub struct LocalDirectoryScope {
    grants: Mutex<Option<Vec<spotiflac_local::files::TemporaryGrant>>>,
}

#[uniffi::export]
impl LocalDirectoryScope {
    pub fn release(&self) {
        self.grants
            .lock()
            .expect("local directory scope lock")
            .take();
    }
}

#[uniffi::export]
impl LocalBackend {
    #[uniffi::constructor]
    pub fn new(data_directory: String) -> Result<Self, LocalBackendError> {
        Ok(Self {
            inner: spotiflac_local::backend::Backend::new(Path::new(&data_directory))
                .map_err(LocalBackendError::Operation)?,
        })
    }

    pub fn set_allowed_directories(
        &self,
        directories: Vec<String>,
    ) -> Result<(), LocalBackendError> {
        self.inner
            .set_allowed_directories(&directories.into_iter().map(Into::into).collect::<Vec<_>>())
            .map_err(LocalBackendError::Operation)
    }

    pub fn grant_directories(
        &self,
        directories: Vec<String>,
    ) -> Result<Arc<LocalDirectoryScope>, LocalBackendError> {
        let grants = directories
            .iter()
            .map(|path| self.inner.grant_directory(Path::new(path)))
            .collect::<Result<Vec<_>, _>>()
            .map_err(LocalBackendError::Operation)?;
        Ok(Arc::new(LocalDirectoryScope {
            grants: Mutex::new(Some(grants)),
        }))
    }

    pub fn shutdown(&self) {
        self.inner.shutdown();
    }
}
