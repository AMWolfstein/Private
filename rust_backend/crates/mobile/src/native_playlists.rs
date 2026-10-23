//! Local M3U export on the native data worker.
use serde_json::{Value, json};
use std::{
    io::{BufWriter, Write},
    path::Path,
};

pub(crate) fn execute(
    request: &Value,
    _bytes: Option<&[u8]>,
    check: &dyn Fn() -> Result<(), String>,
) -> Result<Value, String> {
    check()?;
    match request["operation"].as_str().unwrap_or_default() {
        "build_m3u" => {
            let entries = request["entries"]
                .as_array()
                .ok_or("Missing playlist entries")?;
            let path = request["output_path"]
                .as_str()
                .ok_or("Missing playlist output path")?;
            let parent = Path::new(path)
                .parent()
                .filter(|parent| !parent.as_os_str().is_empty())
                .unwrap_or(Path::new("."));
            let mut staging = tempfile::Builder::new()
                .prefix(".spotiflac-m3u-")
                .tempfile_in(parent)
                .map_err(|e| e.to_string())?;
            {
                let mut file = BufWriter::with_capacity(64 * 1024, staging.as_file_mut());
                file.write_all(b"#EXTM3U\n").map_err(|e| e.to_string())?;
                for entry in entries {
                    check()?;
                    let duration = entry["duration"].as_i64().filter(|n| *n > 0).unwrap_or(-1);
                    let artist = trim(entry["artist"].as_str().unwrap_or_default());
                    let title = entry["name"].as_str().unwrap_or_default();
                    let display = if artist.is_empty() {
                        title.to_owned()
                    } else {
                        format!("{artist} - {title}")
                    };
                    let source = entry["path"].as_str().ok_or("Missing M3U entry path")?;
                    writeln!(file, "#EXTINF:{duration},{display}\n{source}")
                        .map_err(|e| e.to_string())?;
                }
                file.flush().map_err(|e| e.to_string())?;
            }
            staging.as_file().sync_all().map_err(|e| e.to_string())?;
            check()?;
            staging.persist(path).map_err(|e| e.to_string())?;
            Ok(json!({"output_path": path, "committed": true}))
        }
        _ => Err("Unknown playlist operation".into()),
    }
}

fn trim(value: &str) -> &str {
    value.trim_matches(|character: char| character.is_whitespace() || character == '\u{feff}')
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn m3u_export_streams_exact_lines_to_file() {
        let path = std::env::temp_dir().join(format!("native-m3u-{}.m3u8", std::process::id()));
        let request = json!({"operation":"build_m3u", "output_path":path, "entries":[
            {"name":"Song", "artist":" Artist ", "duration":10, "path":"folder/song.flac"},
            {"name":"Unknown", "artist":"", "duration":0, "path":"x.flac"}]});
        execute(&request, None, &|| Ok(())).unwrap();
        assert_eq!(
            fs::read_to_string(&path).unwrap(),
            "#EXTM3U\n#EXTINF:10,Artist - Song\nfolder/song.flac\n#EXTINF:-1,Unknown\nx.flac\n"
        );
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn cancelled_export_keeps_existing_file_and_removes_unique_staging() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("existing.m3u8");
        fs::write(&path, "original").unwrap();
        let request = json!({"operation":"build_m3u", "output_path":path, "entries":[{"name":"Song", "artist":"Artist", "duration":1, "path":"song.flac"}]});
        let calls = std::cell::Cell::new(0);
        let check = || {
            let count = calls.get() + 1;
            calls.set(count);
            if count == 3 {
                Err("cancelled".into())
            } else {
                Ok(())
            }
        };
        assert_eq!(execute(&request, None, &check).unwrap_err(), "cancelled");
        assert_eq!(fs::read_to_string(&path).unwrap(), "original");
        assert_eq!(fs::read_dir(directory.path()).unwrap().count(), 1);
    }

    #[test]
    fn concurrent_exports_do_not_share_staging_files() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("same.m3u8");
        let workers = (0..8).map(|index| {
            let path = path.clone();
            std::thread::spawn(move || execute(&json!({"operation":"build_m3u", "output_path":path, "entries":[{"name":format!("Song{index}"), "artist":"", "duration":1, "path":format!("{index}.flac")}]}), None, &|| Ok(())))
        }).collect::<Vec<_>>();
        for worker in workers {
            assert_eq!(worker.join().unwrap().unwrap()["committed"], true);
        }
        let content = fs::read_to_string(&path).unwrap();
        assert!(content.starts_with("#EXTM3U\n#EXTINF:1,Song"));
        assert_eq!(content.lines().count(), 3);
        assert_eq!(fs::read_dir(directory.path()).unwrap().count(), 1);
    }
}
