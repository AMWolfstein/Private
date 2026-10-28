//! CPU and file work submitted by Flutter. Platform dispatch owns the worker
//! thread and the cancellation lease; widgets continue to own presentation.
use crate::cancellation::RequestLease;
use crate::local::LocalBackend;
use serde_json::{Value, json};
use std::sync::Arc;

#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum NativeDataJobError {
    #[error("{0}")]
    Operation(String),
}

#[uniffi::export]
pub fn run_native_data_job(
    request_json: String,
    bytes: Vec<u8>,
    lease: Option<Arc<RequestLease>>,
) -> Result<String, NativeDataJobError> {
    run(&request_json, &bytes, lease.as_deref(), None)
}

#[uniffi::export]
impl LocalBackend {
    pub fn run_native_data_job(
        &self,
        request_json: String,
        bytes: Vec<u8>,
        lease: Option<Arc<RequestLease>>,
    ) -> Result<String, NativeDataJobError> {
        run(&request_json, &bytes, lease.as_deref(), Some(self))
    }
}

fn run(
    request_json: &str,
    bytes: &[u8],
    lease: Option<&RequestLease>,
    manager: Option<&LocalBackend>,
) -> Result<String, NativeDataJobError> {
    let check = || crate::tags::check_lease(lease);
    check().map_err(NativeDataJobError::Operation)?;
    let request: Value = serde_json::from_str(request_json)
        .map_err(|error| NativeDataJobError::Operation(error.to_string()))?;
    let value = execute(&request, bytes, &check, manager).map_err(NativeDataJobError::Operation)?;
    if value.get("committed") != Some(&Value::Bool(true)) {
        check().map_err(NativeDataJobError::Operation)?;
    }
    serde_json::to_string(&value).map_err(|error| NativeDataJobError::Operation(error.to_string()))
}

fn execute(
    request: &Value,
    bytes: &[u8],
    check: &(dyn Fn() -> Result<(), String> + Sync),
    manager: Option<&LocalBackend>,
) -> Result<Value, String> {
    let operation = string(request, "operation")?;
    match operation {
        "build_m3u" => crate::native_playlists::execute(request, Some(bytes), check),
        "build_metadata_picture" => crate::native_id3::execute(request, Some(bytes), check),
        "parse_lyrics" => crate::native_lyrics::execute(request, Some(bytes), check),
        "palette" => {
            let colors = sistrum_core::native_palette::quantize_rgba(bytes, check)?;
            Ok(json!({"colors": colors}))
        }
        "automix" => {
            let grid = sistrum_core::native_audio_analysis::analyze_automix_pcm_file(
                string(request, "path")?,
                check,
            )?;
            serde_json::to_value(grid).map_err(|error| error.to_string())
        }
        "spectral_cutoff" => {
            let width = request
                .get("width")
                .and_then(Value::as_u64)
                .ok_or("Missing width")?;
            let height = request
                .get("height")
                .and_then(Value::as_u64)
                .ok_or("Missing height")?;
            let maximum = request
                .get("max_frequency")
                .and_then(Value::as_f64)
                .ok_or("Missing maximum frequency")?;
            let cutoff = sistrum_core::native_audio_analysis::estimate_spectral_cutoff_file(
                string(request, "path")?,
                usize::try_from(width).map_err(|e| e.to_string())?,
                usize::try_from(height).map_err(|e| e.to_string())?,
                maximum,
                check,
            )?;
            Ok(json!({"cutoff": cutoff}))
        }
        "library_scan_incremental" => crate::native_library::scan_incremental(
            manager.ok_or("Library scan requires the initialized backend")?,
            request,
            check,
        ),
        "collections_snapshot" => crate::native_collections::execute(request, check),
        "collections_stage_playlist_additions" => {
            crate::native_playlist_write::execute(request, check)
        }
        operation if operation.starts_with("library_") => {
            crate::native_library::execute(request, check)
        }
        operation if operation.starts_with("backup_") => {
            crate::native_backup::execute(request, check)
        }
        operation if operation.starts_with("cache_") => {
            crate::native_cache::execute(request, check)
        }
        _ => Err(format!("Unknown native data operation: {operation}")),
    }
}

pub(crate) fn string<'a>(request: &'a Value, name: &str) -> Result<&'a str, String> {
    request
        .get(name)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("Missing native data field: {name}"))
}
