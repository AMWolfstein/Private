use spotiflac_core::tags::{read_audio_tags, read_library_metadata, rewrite_audio_tags};
use std::collections::BTreeMap;
use std::io::Cursor;

// One second of silence, encoded with FFmpeg/libopus; only ENCODER is tagged.
const OPUS: &[u8] = include_bytes!("fixtures/encoder-only.opus");

#[test]
fn valid_opus_without_title_or_artist_is_scannable() {
    let tags = read_audio_tags(&mut Cursor::new(OPUS), "opus", &|| Ok(())).unwrap();
    assert!(tags.title.is_empty());
    assert!(tags.artist.is_empty());
    let scan = read_library_metadata(
        &mut Cursor::new(OPUS),
        "/proc/self/fd/9",
        "يوم ما تنسى.opus",
        "scan",
        0,
        &|| Ok(()),
    )
    .unwrap();
    assert_eq!(scan["trackName"], "يوم ما تنسى");
    assert_eq!(scan["sampleRate"], 48000);
    assert_eq!(scan["duration"], 1);
    assert!(scan.get("metadataFromFilename").is_none());
}

#[test]
fn album_and_lyrics_survive_without_title_or_artist() {
    let mut output = Vec::new();
    rewrite_audio_tags(
        &mut Cursor::new(OPUS),
        &mut output,
        "opus",
        &BTreeMap::from([
            ("album".into(), "ألبوم".into()),
            ("lyrics".into(), "[00:00.00]كلمات".into()),
        ]),
        None,
        &|| Ok(()),
    )
    .unwrap();
    let scan = read_library_metadata(
        &mut Cursor::new(output),
        "/music/song.opus",
        "",
        "scan",
        0,
        &|| Ok(()),
    )
    .unwrap();
    assert_eq!(scan["albumName"], "ألبوم");
    assert_eq!(scan["hasLyrics"], true);
    assert!(scan.get("metadataFromFilename").is_none());
}

#[test]
fn corrupt_opus_comments_remain_an_error_with_a_diagnostic() {
    let mut bytes = OPUS.to_vec();
    let offset = bytes.windows(8).position(|b| b == b"OpusTags").unwrap() + 8;
    bytes[offset..offset + 4].copy_from_slice(&u32::MAX.to_le_bytes());
    assert!(read_audio_tags(&mut Cursor::new(&bytes), "opus", &|| Ok(())).is_err());
    let scan = read_library_metadata(
        &mut Cursor::new(bytes),
        "/music/song.opus",
        "",
        "scan",
        0,
        &|| Ok(()),
    )
    .unwrap();
    assert_eq!(scan["metadataFromFilename"], true);
    assert_eq!(scan["metadataReadError"], "invalid Vorbis comments");
}
