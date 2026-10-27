use super::Backend;
use cap_std::fs::OpenOptions;
use sistrum_core::tags::{CoverArt, extract_cover};
use std::{cell::RefCell, io::Read, io::Write, path::Path};
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
            publish_cover(&output, permissions, &cover.data, &check, true)
        };
        write().map_err(|error| format!("failed to write cover file: {error}"))
    }

    /// Cache identity comes from the artwork bytes, not from `explicit_key`:
    /// tracks that embed the same cover share one cache file. The key stays in
    /// the call shape for the existing native callers.
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
        let format = sistrum_core::tags::library_extension(audio_path, hint);
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
        _cache_key: &str,
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
        // A warm scan must not read the embedded artwork just to rediscover a
        // file it already cached: a 70-byte key -> content pointer answers the
        // lookup before any audio is opened.
        let key = _cache_key.trim();
        let pointer = if key.is_empty() {
            None
        } else {
            let name = format!(
                "cover_{}.id",
                sistrum_core::cover::content_id(key.as_bytes())
            );
            files
                .resolve_legacy(&Path::new(cache_directory).join(name).to_string_lossy())
                .ok()
        };
        if let Some(pointer) = &pointer
            && let Some(target) = pointer_target(&files, cache_directory, pointer)
        {
            return Ok(target.display());
        }
        let mut cover = read(&input, &format, &check)?;
        if let Ok(resized) = sistrum_core::cover::library_thumbnail(&cover.data, &check) {
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
        // Hash the published thumbnail, just like the Android descriptor path,
        // so local and SAF scans share one content file too.
        let key_id = sistrum_core::cover::content_id(&cover.data);
        let path =
            |extension| Path::new(cache_directory).join(format!("cover_{key_id}.{extension}"));
        let jpg = files.resolve_legacy(&path("jpg").to_string_lossy())?;
        let png = files.resolve_legacy(&path("png").to_string_lossy())?;
        let output = if cover.mime.contains("png") { png } else { jpg };
        output.native_display()?;
        let output_name = if cover.mime.contains("png") {
            format!("cover_{key_id}.png")
        } else {
            format!("cover_{key_id}.jpg")
        };
        let _lock = files.lock(&output, &check)?;
        if output
            .metadata()
            .is_ok_and(|metadata| metadata.is_file() && metadata.len() > 0)
        {
            remember_cover(&pointer, &output_name, &check);
            return Ok(output.display());
        }
        output
            .mkdir_parent()
            .map_err(|error| format!("failed to create cache dir: {error}"))?;
        let permissions = output_permissions(&output)
            .map_err(|error| format!("failed to write cover: {error}"))?;
        // Cached artwork is regenerable: never pay a per-file and directory
        // fsync for it, unlike an exported cover the user asked to keep.
        publish_cover(&output, permissions, &cover.data, &check, false)
            .map_err(|error| format!("failed to write cover: {error}"))?;
        remember_cover(&pointer, &output_name, &check);
        Ok(output.display())
    }
}

/// Records which content-addressed file a per-track key resolved to, so the
/// next scan can skip the artwork read. Best effort: a missing pointer only
/// costs one read, never correctness.
fn remember_cover(pointer: &Option<crate::files::FilePath>, name: &str, check: &Check<'_>) {
    let Some(pointer) = pointer else { return };
    let _ = publish_cover(pointer, None, name.as_bytes(), check, false);
}

/// Resolves a `cover_<sha256>.id` pointer to its content file. The payload is a
/// bare file name and is validated, so a corrupt pointer can never escape the
/// cache directory.
fn pointer_target(
    files: &crate::files::LocalFiles,
    cache_directory: &str,
    pointer: &crate::files::FilePath,
) -> Option<crate::files::FilePath> {
    let mut file = pointer.open(OpenOptions::new().read(true)).ok()?;
    let mut buffer = [0_u8; 96];
    let mut length = 0;
    while length < buffer.len() {
        let read = file.read(&mut buffer[length..]).ok()?;
        if read == 0 {
            break;
        }
        length += read;
    }
    let name = std::str::from_utf8(&buffer[..length]).ok()?.trim();
    if !is_cover_file_name(name) {
        return None;
    }
    let target = files
        .resolve_legacy(&Path::new(cache_directory).join(name).to_string_lossy())
        .ok()?;
    target.native_display().ok()?;
    target
        .metadata()
        .ok()
        .filter(|metadata| metadata.is_file() && metadata.len() > 0)?;
    Some(target)
}

/// `cover_` + 64 lowercase hex + `.jpg`/`.png` and nothing else.
fn is_cover_file_name(name: &str) -> bool {
    let Some(rest) = name.strip_prefix("cover_") else {
        return false;
    };
    let Some((id, extension)) = rest.split_once('.') else {
        return false;
    };
    id.len() == 64
        && id
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
        && matches!(extension, "jpg" | "png")
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
    durable: bool,
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
    if durable {
        stage.publish(check)
    } else {
        stage.publish_unsynced(check)
    }
}

#[cfg(all(test, unix))]
mod safety_tests {
    use super::*;
    #[test]
    fn colliding_legacy_keys_and_concurrent_publication_keep_the_right_cover() {
        let root = tempfile::tempdir().unwrap();
        let backend = Backend::new(&root.path().join("data")).unwrap();
        backend
            .set_allowed_directories(&[root.path().to_path_buf()])
            .unwrap();
        let audio = root.path().join("song.flac");
        std::fs::write(&audio, b"placeholder").unwrap();
        let cache = root.path().join("cache");
        let audio = audio.to_str().unwrap();
        let cache = cache.to_str().unwrap();
        let save = |key: &str, bytes: &[u8]| {
            backend
                .save_cover_to_cache_for_scan(
                    audio,
                    "",
                    cache,
                    key,
                    |_, _, _| {
                        Ok(CoverArt {
                            data: bytes.to_vec(),
                            mime: "image/jpeg".into(),
                        })
                    },
                    &|| Ok(()),
                )
                .unwrap()
        };
        let first = save("Aa", b"first cover");
        let second = save("B@", b"second cover");
        assert_ne!(first, second);
        assert_eq!(std::fs::read(first).unwrap(), b"first cover");
        assert_eq!(std::fs::read(second).unwrap(), b"second cover");
        std::thread::scope(|scope| {
            let handles: Vec<_> = (0..4)
                .map(|_| scope.spawn(|| save("shared", b"shared complete cover")))
                .collect();
            let paths: Vec<_> = handles
                .into_iter()
                .map(|handle| handle.join().unwrap())
                .collect();
            assert!(paths.iter().all(|path| path == &paths[0]));
            assert_eq!(std::fs::read(&paths[0]).unwrap(), b"shared complete cover");
        });
    }

    #[test]
    fn tracks_with_the_same_cover_write_one_cache_file() {
        let root = tempfile::tempdir().unwrap();
        let backend = Backend::new(&root.path().join("data")).unwrap();
        backend
            .set_allowed_directories(&[root.path().to_path_buf()])
            .unwrap();
        let audio = root.path().join("song.flac");
        std::fs::write(&audio, b"placeholder").unwrap();
        let cache = root.path().join("cache");
        let audio = audio.to_str().unwrap();
        let cache = cache.to_str().unwrap();
        let save = |key: &str, bytes: &[u8]| {
            backend
                .save_cover_to_cache_for_scan(
                    audio,
                    "",
                    cache,
                    key,
                    |_, _, _| {
                        Ok(CoverArt {
                            data: bytes.to_vec(),
                            mime: "image/jpeg".into(),
                        })
                    },
                    &|| Ok(()),
                )
                .unwrap()
        };
        // Two tracks (different keys, one album) with identical embedded art.
        let first = save("track-a|1", b"album cover bytes");
        let second = save("track-b|2", b"album cover bytes");
        assert_eq!(first, second);
        assert_eq!(std::fs::read(&first).unwrap(), b"album cover bytes");
        // A third track with different art still owns a file of its own.
        let third = save("track-c|3", b"other album cover");
        assert_ne!(third, first);
        let mut covers = 0;
        let mut pointers = 0;
        for entry in std::fs::read_dir(cache).unwrap() {
            let name = entry.unwrap().file_name();
            if name.to_string_lossy().ends_with(".id") {
                pointers += 1;
            } else {
                covers += 1;
            }
        }
        assert_eq!(covers, 2);
        assert_eq!(pointers, 3);
    }

    #[test]
    fn cache_identity_hashes_the_published_thumbnail_not_the_original() {
        // A valid 1000x1 RGB PNG: small fixture, but wide enough to resize.
        let original = [
            137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 3, 232, 0, 0, 0, 1,
            8, 2, 0, 0, 0, 194, 98, 19, 100, 0, 0, 0, 31, 73, 68, 65, 84, 120, 156, 237, 194, 65,
            17, 0, 0, 8, 3, 32, 147, 44, 152, 193, 204, 107, 141, 61, 224, 152, 236, 169, 170, 170,
            229, 31, 127, 188, 30, 237, 168, 46, 25, 87, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96,
            130,
        ];
        let root = tempfile::tempdir().unwrap();
        let backend = Backend::new(&root.path().join("data")).unwrap();
        backend
            .set_allowed_directories(&[root.path().to_path_buf()])
            .unwrap();
        let audio = root.path().join("song.flac");
        std::fs::write(&audio, b"placeholder").unwrap();
        let cached = backend
            .save_cover_to_cache_for_scan(
                audio.to_str().unwrap(),
                "",
                root.path().join("cache").to_str().unwrap(),
                "track|1",
                |_, _, _| {
                    Ok(CoverArt {
                        data: original.to_vec(),
                        mime: "image/png".into(),
                    })
                },
                &|| Ok(()),
            )
            .unwrap();
        let published = std::fs::read(&cached).unwrap();
        assert_ne!(published, original);
        let expected = format!("cover_{}.png", sistrum_core::cover::content_id(&published));
        assert_eq!(
            Path::new(&cached).file_name().unwrap().to_str().unwrap(),
            expected
        );
    }

    #[test]
    fn a_pointer_payload_can_never_escape_the_cache() {
        let valid = format!("cover_{}.jpg", "a".repeat(64));
        assert!(is_cover_file_name(&valid));
        assert!(is_cover_file_name(&format!("cover_{}.png", "0".repeat(64))));
        assert!(!is_cover_file_name("../../../etc/passwd"));
        assert!(!is_cover_file_name(&format!("{valid}/../escape")));
        assert!(!is_cover_file_name(&format!(
            "cover_{}.gif",
            "a".repeat(64)
        )));
        assert!(!is_cover_file_name(&format!(
            "cover_{}.JPG",
            "a".repeat(64)
        )));
        assert!(!is_cover_file_name(&format!(
            "cover_{}.jpg",
            "A".repeat(64)
        )));
        assert!(!is_cover_file_name("cover_abc.jpg"));
    }

    #[test]
    fn a_warm_key_reuses_the_cover_without_reading_the_artwork() {
        let root = tempfile::tempdir().unwrap();
        let backend = Backend::new(&root.path().join("data")).unwrap();
        backend
            .set_allowed_directories(&[root.path().to_path_buf()])
            .unwrap();
        let audio = root.path().join("song.flac");
        std::fs::write(&audio, b"placeholder").unwrap();
        let cache = root.path().join("cache");
        let audio = audio.to_str().unwrap();
        let cache = cache.to_str().unwrap();
        let first = backend
            .save_cover_to_cache_for_scan(
                audio,
                "",
                cache,
                "track-a|1",
                |_, _, _| {
                    Ok(CoverArt {
                        data: b"album cover bytes".to_vec(),
                        mime: "image/jpeg".into(),
                    })
                },
                &|| Ok(()),
            )
            .unwrap();
        // Nothing readable is left to extract, so a second call can only
        // succeed through the key -> content pointer.
        std::fs::write(audio, b"").unwrap();
        let reads = std::cell::Cell::new(0);
        let second = backend
            .save_cover_to_cache_for_scan(
                audio,
                "",
                cache,
                "track-a|1",
                |_, _, _| -> Result<CoverArt, String> {
                    reads.set(reads.get() + 1);
                    Err("a warm cache must not read the artwork".into())
                },
                &|| Ok(()),
            )
            .unwrap();
        assert_eq!(reads.get(), 0);
        assert_eq!(first, second);
        assert_eq!(std::fs::read(&second).unwrap(), b"album cover bytes");
    }
}
