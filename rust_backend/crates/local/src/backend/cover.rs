use super::Backend;
use cap_std::fs::OpenOptions;
use spotiflac_core::tags::{CoverArt, extract_cover};
use std::{cell::RefCell, io::Write, path::Path, time::UNIX_EPOCH};
type Check<'a> = dyn Fn() -> Result<(), String> + 'a;

impl Backend {
    pub fn extract_cover_to_file(
        &self,
        audio_path: &str,
        output_path: &str,
        check: &Check<'_>,
    ) -> Result<(), String> {
        let _operation = self.enter()?;
        let check = || self.check().and_then(|()| check());
        check()?;
        let format = extension(audio_path);
        if !matches!(
            format.as_str(),
            "flac" | "m4a" | "aac" | "mp3" | "ogg" | "opus" | "wav" | "aiff" | "aif" | "aifc"
        ) {
            return Err("unsupported audio format for cover extraction".into());
        }
        let files = self.files()?;
        let input = files.resolve_legacy(audio_path)?;
        let cover = read_cover(&input, &format, &check)
            .map_err(|error| format!("failed to extract cover: {error}"))?;
        let write = || {
            let output = files.resolve_legacy(output_path)?;
            if input.absolute == output.absolute {
                return Err("cover output must differ from the audio source".into());
            }
            let _lock = files.lock(&output, &check)?;
            let permissions = output_permissions(&output)?;
            publish_cover(&output, permissions, &cover.data, &check)
        };
        write().map_err(|error| format!("failed to write cover file: {error}"))
    }

    pub fn save_cover_to_cache_with_hint_and_key(
        &self,
        audio_path: &str,
        hint: &str,
        cache_directory: &str,
        explicit_key: &str,
        check: &Check<'_>,
    ) -> Result<String, String> {
        self.cache_cover(
            audio_path,
            hint,
            cache_directory,
            explicit_key,
            None,
            read_cover,
            check,
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) fn save_cover_to_cache_for_scan(
        &self,
        audio_path: &str,
        hint: &str,
        cache_directory: &str,
        explicit_key: &str,
        read: impl FnOnce(&crate::files::FilePath, &str, &Check<'_>) -> Result<CoverArt, String>,
        check: &Check<'_>,
    ) -> Result<String, String> {
        let format = spotiflac_core::tags::library_extension(audio_path, hint);
        // The scan's MP4-family reader also accepts .mp4/.aac. The standalone
        // cover export deliberately keeps its narrower legacy suffix policy.
        let format = matches!(format.as_str(), "mp4" | "aac").then_some("m4a");
        self.cache_cover(
            audio_path,
            hint,
            cache_directory,
            explicit_key,
            format,
            read,
            check,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn cache_cover(
        &self,
        audio_path: &str,
        hint: &str,
        cache_directory: &str,
        explicit_key: &str,
        format_override: Option<&str>,
        read: impl FnOnce(&crate::files::FilePath, &str, &Check<'_>) -> Result<CoverArt, String>,
        check: &Check<'_>,
    ) -> Result<String, String> {
        let _operation = self.enter()?;
        let failure = RefCell::new(None::<String>);
        let check = || {
            if let Some(error) = failure.borrow().as_ref() {
                return Err(error.clone());
            }
            self.check().and_then(|()| check()).inspect_err(|error| {
                *failure.borrow_mut() = Some(error.clone());
            })
        };
        check()?;
        let files = self.files()?;
        let input = files.resolve_legacy(audio_path)?;
        input.native_display()?;
        let key = if !explicit_key.trim().is_empty() {
            explicit_key.trim().to_owned()
        } else if let Ok(metadata) = input.metadata() {
            let modified = metadata
                .modified()
                .map_err(|error| error.to_string())?
                .into_std();
            let nanos = match modified.duration_since(UNIX_EPOCH) {
                Ok(duration) => duration.as_nanos() as i128,
                Err(error) => -(error.duration().as_nanos() as i128),
            };
            format!("{audio_path}|{}|{nanos}", metadata.len())
        } else {
            audio_path.into()
        };
        let hash = key.chars().fold(5381_u32, |hash, value| {
            hash.wrapping_mul(33).wrapping_add(value as u32)
        });
        let path =
            |extension| Path::new(cache_directory).join(format!("cover_{hash:x}.{extension}"));
        let jpg = files.resolve_legacy(&path("jpg").to_string_lossy())?;
        let png = files.resolve_legacy(&path("png").to_string_lossy())?;
        for cached in [&jpg, &png] {
            cached.native_display()?;
            if cached.metadata().is_ok_and(|metadata| metadata.is_file()) {
                return Ok(cached.display());
            }
        }
        let mut format = extension(audio_path);
        if format.is_empty() {
            format = extension(hint);
        }
        if let Some(value) = format_override {
            format = value.into();
        }
        if !matches!(
            format.as_str(),
            "flac" | "m4a" | "mp3" | "ogg" | "opus" | "wav" | "aiff" | "aif" | "aifc"
        ) {
            return Err(format!(
                "unsupported format: {}",
                if format.is_empty() {
                    String::new()
                } else {
                    format!(".{format}")
                }
            ));
        }
        let mut cover = read(&input, &format, &check)?;
        if let Ok(resized) = spotiflac_core::cover::library_thumbnail(&cover.data, &check) {
            cover.mime = if resized.starts_with(b"\x89PNG") {
                "image/png"
            } else if resized.starts_with(b"\xff\xd8") {
                "image/jpeg"
            } else {
                &cover.mime
            }
            .into();
            cover.data = resized.to_vec();
        }
        // Library caching may retain unsupported image bytes, but must never
        // swallow cancellation while attempting the optional resize.
        check()?;
        let output = if cover.mime.contains("png") { png } else { jpg };
        let _lock = files.lock(&output, &check)?;
        if output.metadata().is_ok_and(|metadata| metadata.is_file()) {
            return Ok(output.display());
        }
        output
            .mkdir_parent()
            .map_err(|error| format!("failed to create cache dir: {error}"))?;
        let permissions = output_permissions(&output)
            .map_err(|error| format!("failed to write cover: {error}"))?;
        publish_cover(&output, permissions, &cover.data, &check)
            .map_err(|error| format!("failed to write cover: {error}"))?;
        Ok(output.display())
    }
}

fn extension(path: &str) -> String {
    Path::new(path)
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or("")
        .to_lowercase()
}

fn read_cover(
    input: &crate::files::FilePath,
    format: &str,
    check: &Check<'_>,
) -> Result<CoverArt, String> {
    input.native_display()?;
    let mut file = input
        .open(OpenOptions::new().read(true))
        .map_err(|error| error.to_string())?;
    extract_cover(&mut file, format, check)
}

fn output_permissions(
    output: &crate::files::FilePath,
) -> Result<Option<cap_std::fs::Permissions>, String> {
    output.native_display()?;
    output.require_parent()?;
    match output.open(OpenOptions::new().write(true)) {
        Ok(file) => Ok(Some(
            file.metadata()
                .map_err(|error| error.to_string())?
                .permissions(),
        )),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.to_string()),
    }
}

fn publish_cover(
    output: &crate::files::FilePath,
    permissions: Option<cap_std::fs::Permissions>,
    data: &[u8],
    check: &Check<'_>,
) -> Result<(), String> {
    check()?;
    let mut stage = output
        .stage_existing_parent()
        .map_err(|error| error.to_string())?;
    if let Some(permissions) = permissions {
        stage
            .file
            .set_permissions(permissions)
            .map_err(|error| error.to_string())?;
    }
    for chunk in data.chunks(16 * 1024) {
        check()?;
        stage
            .file
            .write_all(chunk)
            .map_err(|error| error.to_string())?;
    }
    stage.publish(check)
}
