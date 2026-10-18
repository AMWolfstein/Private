use super::Backend;
use crate::files::LocalFiles;
use cap_std::fs::OpenOptions;
use serde::{Deserialize, Serialize};
use spotiflac_core::lyrics::{file, lrc};
type Check<'a> = dyn Fn() -> Result<(), String> + 'a;
use std::collections::BTreeMap;
use std::io::Write;

/// Native export arguments. Unlike the private JS SDK, file_path is not trimmed.
#[derive(Clone, Debug, Default, Deserialize)]
#[serde(default)]
pub struct LyricsRequest {
    pub spotify_id: String,
    pub track: String,
    pub artist: String,
    pub file_path: String,
    pub duration_ms: i64,
}

#[derive(Default, Serialize)]
struct LrcResult {
    lyrics: String,
    source: String,
    sync_type: String,
    instrumental: bool,
}

impl Backend {
    pub fn embed_lyrics_to_file(
        &self,
        path: &str,
        lyrics: &str,
        check: &Check<'_>,
    ) -> Result<String, String> {
        let fields = BTreeMap::from([
            ("LYRICS".into(), lyrics.into()),
            ("UNSYNCEDLYRICS".into(), lyrics.into()),
        ]);
        self.embed_flac_fields_response(
            path,
            &fields,
            "",
            ("Failed to embed lyrics", "Lyrics embedded successfully"),
            check,
        )
    }

    pub fn get_lyrics_lrc(
        &self,
        request: &LyricsRequest,
        check: &Check<'_>,
    ) -> Result<String, String> {
        let _operation = self.enter()?;
        let check = || self.check().and_then(|()| check());
        Ok(self.lrc_result(request, &check)?.lyrics)
    }

    pub fn get_lyrics_lrc_with_source(
        &self,
        request: &LyricsRequest,
        check: &Check<'_>,
    ) -> Result<String, String> {
        let _operation = self.enter()?;
        let check = || self.check().and_then(|()| check());
        serde_json::to_string(&self.lrc_result(request, &check)?).map_err(|error| error.to_string())
    }

    pub fn save_local_lyrics(
        &self,
        request: &LyricsRequest,
        output_path: &str,
        check: &Check<'_>,
    ) -> Result<(), String> {
        let _operation = self.enter()?;
        let check = || self.check().and_then(|()| check());
        check()?;
        let files = self.files()?;
        if request.file_path.is_empty() {
            return Err("no local audio file supplied".into());
        }
        let input = files.resolve_legacy(&request.file_path)?;
        let output = files.resolve_legacy(output_path)?;
        if input.absolute == output.absolute {
            return Err("lyrics output must differ from the audio source".into());
        }
        let content = existing(&files, &request.file_path, &check)?
            .ok_or("no embedded or sidecar lyrics available")?;
        let write = || -> Result<(), String> {
            let output = files.resolve_legacy(output_path)?;
            let _output = files.lock(&output, &check)?;
            check()?;
            // Go WriteFile does not create missing parents. Reject symlinks and
            // non-regular destinations before an atomic replacement as well.
            output.native_display()?;
            output.require_parent()?;
            let permissions = match output.open(OpenOptions::new().write(true)) {
                Ok(file) => Some(
                    file.metadata()
                        .map_err(|error| error.to_string())?
                        .permissions(),
                ),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
                Err(error) => return Err(error.to_string()),
            };
            let mut stage = output
                .stage_existing_parent()
                .map_err(|error| error.to_string())?;
            if let Some(permissions) = permissions {
                stage
                    .file
                    .set_permissions(permissions)
                    .map_err(|error| error.to_string())?;
            }
            for chunk in content.as_bytes().chunks(16 * 1024) {
                check()?;
                stage
                    .file
                    .write_all(chunk)
                    .map_err(|error| error.to_string())?;
            }
            stage.publish(&check)
        };
        write().map_err(|error| format!("failed to write LRC file: {error}"))?;
        Ok(())
    }

    fn lrc_result(&self, request: &LyricsRequest, check: &Check<'_>) -> Result<LrcResult, String> {
        check()?;
        if !request.file_path.is_empty() {
            let files = self.files()?;
            return Ok(match existing(&files, &request.file_path, check)? {
                Some(lyrics) => {
                    let source = lrc::extract_source(&lyrics);
                    LrcResult {
                        source: if source.is_empty() {
                            "Embedded".into()
                        } else {
                            source
                        },
                        sync_type: "EMBEDDED".into(),
                        instrumental: lrc::is_instrumental_marker(&lyrics),
                        lyrics,
                    }
                }
                None => LrcResult::default(),
            });
        }
        Ok(LrcResult::default())
    }
}

fn existing(
    files: &LocalFiles,
    path: &str,
    check: &dyn Fn() -> Result<(), String>,
) -> Result<Option<String>, String> {
    let result = file::extract(
        path,
        &|path| {
            files
                .resolve_legacy(path)?
                .open(OpenOptions::new().read(true))
                .map_err(|error| error.to_string())
        },
        check,
    );
    check()?;
    Ok(result.ok().filter(|text| lrc::has_usable_content(text)))
}
