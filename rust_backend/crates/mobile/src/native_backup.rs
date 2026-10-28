//! ZIP payloads and collection staging stay on the native worker. Backup
//! category selection, archive layout and presentation remain owned by Flutter.
mod archive;
mod collections;

use serde_json::Value;
use std::path::Path;

type Check<'a> = &'a dyn Fn() -> Result<(), String>;
// Upper bound for a staged collections payload.
const MAX_PAYLOAD_BYTES: u64 = 512 << 20;
// Restore decodes metadata.json in memory; keep in sync with BackupService.
const MAX_METADATA_BYTES: u64 = 32 << 20;
const MAX_ROW_BYTES: u64 = 16 << 20;
const BACKUP_MAGIC: &str = "sistrum-backup";
fn is_accepted_backup_magic(magic: &Value) -> bool {
    magic.as_str().is_some_and(|m| m == BACKUP_MAGIC)
}

fn err(context: &str, error: impl std::fmt::Display) -> String {
    format!("{context}: {error}")
}
fn required<'a>(request: &'a Value, field: &str) -> Result<&'a str, String> {
    request[field]
        .as_str()
        .filter(|v| !v.is_empty())
        .ok_or_else(|| format!("Backup requires {field}"))
}
fn output_path<'a>(request: &'a Value, field: &str) -> Result<&'a str, String> {
    let path = required(request, field)?;
    if !Path::new(path).is_absolute() {
        return Err("Backup output path must be absolute".into());
    }
    Ok(path)
}

pub(crate) fn execute(request: &Value, check: Check<'_>) -> Result<Value, String> {
    check()?;
    match required(request, "operation")? {
        "backup_collections_import" => collections::import(request, check),
        "backup_archive_write" => archive::write(request, check),
        "backup_archive_read" => archive::read(request, check),
        _ => Err("Unknown native backup operation".into()),
    }
}

#[cfg(test)]
mod tests;
