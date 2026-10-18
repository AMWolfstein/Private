use spotiflac_core::cancellation as core;
use std::sync::Arc;

#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum CancellationError {
    #[error("local request cancelled")]
    LocalRequestCancelled,
    #[error("cancellation registry closed")]
    RegistryClosed,
    #[error("request lease released")]
    LeaseReleased,
}

impl From<core::CancellationError> for CancellationError {
    fn from(error: core::CancellationError) -> Self {
        match error {
            core::CancellationError::DownloadCancelled => Self::LocalRequestCancelled,
            core::CancellationError::ExtensionRequestCancelled => Self::LocalRequestCancelled,
            core::CancellationError::RegistryClosed => Self::RegistryClosed,
            core::CancellationError::LeaseReleased => Self::LeaseReleased,
        }
    }
}

#[derive(uniffi::Object)]
pub struct CancellationRegistry {
    inner: core::CancellationRegistry,
}

#[uniffi::export]
impl CancellationRegistry {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self {
            inner: core::CancellationRegistry::new(core::CancellationDomain::ExtensionRequest),
        }
    }

    pub fn acquire(&self, id: String) -> Result<Arc<RequestLease>, CancellationError> {
        Ok(Arc::new(RequestLease {
            inner: Arc::new(self.inner.acquire(&id)?),
        }))
    }

    pub fn cancel(&self, id: String) -> Result<(), CancellationError> {
        self.inner.cancel(&id).map_err(Into::into)
    }

    pub fn is_cancelled(&self, id: String) -> Result<bool, CancellationError> {
        self.inner.is_cancelled(&id).map_err(Into::into)
    }

    pub fn shutdown(&self) {
        self.inner.shutdown();
    }
}

#[derive(uniffi::Object)]
pub struct RequestLease {
    pub(crate) inner: Arc<core::RequestLease>,
}

#[uniffi::export]
impl RequestLease {
    pub fn is_cancelled(&self) -> Result<bool, CancellationError> {
        self.inner.is_cancelled().map_err(Into::into)
    }

    pub fn release(&self) {
        self.inner.release();
    }
}

impl Default for CancellationRegistry {
    fn default() -> Self {
        Self::new()
    }
}
