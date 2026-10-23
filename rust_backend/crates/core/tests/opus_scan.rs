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

fn paged_packet(packet: &[u8], sequence: &mut u32, max_segments: usize) -> Vec<u8> {
    let lacing: Vec<u8> = std::iter::repeat_n(255, packet.len() / 255)
        .chain(std::iter::once((packet.len() % 255) as u8))
        .collect();
    let mut result = Vec::new();
    let mut offset = 0;
    for (index, segments) in lacing.chunks(max_segments).enumerate() {
        let mut header = [0_u8; 27];
        header[..4].copy_from_slice(b"OggS");
        header[5] = if *sequence == 0 {
            2
        } else {
            u8::from(index > 0)
        };
        header[14..18].copy_from_slice(&1_u32.to_le_bytes());
        header[18..22].copy_from_slice(&sequence.to_le_bytes());
        header[26] = segments.len() as u8;
        *sequence += 1;
        result.extend(header);
        result.extend(segments);
        let length = segments.iter().map(|n| *n as usize).sum::<usize>();
        result.extend_from_slice(&packet[offset..offset + length]);
        offset += length;
    }
    result
}

#[test]
fn continued_opus_comments_survive_page_and_old_packet_limits() {
    // Metadata may span many small pages, or carry a large artwork/padding field.
    // Both layouts used to silently discard OpusTags and report "no comments".
    for (padding, segments) in [(64 * 1024, 1), (512 * 1024, 1), (11 * 1024 * 1024, 255)] {
        let mut tags = b"OpusTags".to_vec();
        tags.extend(0_u32.to_le_bytes()); // vendor
        tags.extend(2_u32.to_le_bytes());
        tags.extend(((padding + 8) as u32).to_le_bytes());
        tags.extend(b"PADDING=");
        tags.resize(tags.len() + padding, b'x');
        let title = "TITLE=يوم ما تنسى".as_bytes();
        tags.extend((title.len() as u32).to_le_bytes());
        tags.extend(title);
        let mut sequence = 0;
        let mut data = paged_packet(
            b"OpusHead\x01\x02\0\0\x80\xbb\0\0\0\0\0",
            &mut sequence,
            255,
        );
        data.extend(paged_packet(&tags, &mut sequence, segments));
        let metadata = read_audio_tags(&mut Cursor::new(&data), "opus", &|| Ok(())).unwrap();
        assert_eq!(metadata.title, "يوم ما تنسى");
        let scan = read_library_metadata(
            &mut Cursor::new(data),
            "/proc/self/fd/9",
            "song.opus",
            "scan",
            0,
            &|| Ok(()),
        )
        .unwrap();
        assert_eq!(scan["trackName"], "يوم ما تنسى");
        assert!(scan.get("metadataFromFilename").is_none());
    }
}

#[test]
fn artwork_across_many_pages_is_read_without_consuming_audio() {
    use base64::Engine;
    use spotiflac_core::tags::extract_cover;
    for length in [512 * 1024, 8 * 1024 * 1024] {
        let artwork = vec![0x5a; length];
        let mut picture = 3_u32.to_be_bytes().to_vec();
        picture.extend(10_u32.to_be_bytes());
        picture.extend(b"image/jpeg");
        picture.extend(0_u32.to_be_bytes());
        for value in [1000_u32, 1000, 24, 0, artwork.len() as u32] {
            picture.extend(value.to_be_bytes());
        }
        picture.extend(&artwork);
        let comment = format!(
            "METADATA_BLOCK_PICTURE={}",
            base64::engine::general_purpose::STANDARD.encode(picture)
        );
        let mut tags = b"OpusTags".to_vec();
        tags.extend(0_u32.to_le_bytes());
        tags.extend(1_u32.to_le_bytes());
        tags.extend((comment.len() as u32).to_le_bytes());
        tags.extend(comment.as_bytes());
        let mut sequence = 0;
        let mut data = paged_packet(
            b"OpusHead\x01\x02\0\0\x80\xbb\0\0\0\0\0",
            &mut sequence,
            255,
        );
        data.extend(paged_packet(
            &tags,
            &mut sequence,
            if length > 1024 * 1024 { 255 } else { 1 },
        ));
        let header_end = data.len() as u64;
        // Junk after the headers must not be parsed while extracting tags/artwork.
        data.resize(data.len() + 2 * 1024 * 1024, 0x55);
        let mut source = Cursor::new(data);
        let cover = extract_cover(&mut source, "opus", &|| Ok(())).unwrap();
        assert_eq!(cover.data, artwork);
        // Buffered I/O may read ahead once; it must not scan the audio payload.
        assert!(source.position() <= header_end + 8192);
    }
}

#[test]
fn malformed_or_incomplete_fragmented_comments_report_the_real_failure() {
    let mut sequence = 0;
    let first = paged_packet(
        b"OpusHead\x01\x02\0\0\x80\xbb\0\0\0\0\0",
        &mut sequence,
        255,
    );
    let mut tags = b"OpusTags".to_vec();
    tags.resize(300 * 1024, b'x');
    let mut data = first;
    data.extend(paged_packet(&tags, &mut sequence, 1));
    assert_eq!(
        read_audio_tags(&mut Cursor::new(&data), "opus", &|| Ok(())).unwrap_err(),
        "invalid Vorbis comments"
    );
    // A partial continued header must never degrade into "no comments".
    data.truncate(1000);
    let error = read_audio_tags(&mut Cursor::new(data), "opus", &|| Ok(())).unwrap_err();
    assert!(error.contains("EOF"), "{error}");
}

#[test]
fn editing_fragmented_headers_preserves_audio_and_new_tags() {
    let mut tags = b"OpusTags".to_vec();
    tags.extend(0_u32.to_le_bytes());
    tags.extend(1_u32.to_le_bytes());
    let comment = format!("PADDING={}", "x".repeat(512 * 1024));
    tags.extend((comment.len() as u32).to_le_bytes());
    tags.extend(comment.as_bytes());
    let mut sequence = 0;
    let mut input = paged_packet(
        b"OpusHead\x01\x02\0\0\x80\xbb\0\0\0\0\0",
        &mut sequence,
        255,
    );
    input.extend(paged_packet(&tags, &mut sequence, 1));
    assert!(sequence > 1024);
    let audio = b"audio payload retained during header repagination";
    input.extend(paged_packet(audio, &mut sequence, 255));
    let mut output = Vec::new();
    rewrite_audio_tags(
        &mut Cursor::new(input),
        &mut output,
        "opus",
        &BTreeMap::from([("title".into(), "الميدان".into())]),
        None,
        &|| Ok(()),
    )
    .unwrap();
    assert!(output.ends_with(audio));
    let metadata = read_audio_tags(&mut Cursor::new(output), "opus", &|| Ok(())).unwrap();
    assert_eq!(metadata.title, "الميدان");
}

#[test]
fn endless_continuation_is_stopped_by_the_byte_budget() {
    let mut sequence = 0;
    let first = paged_packet(
        b"OpusHead\x01\x02\0\0\x80\xbb\0\0\0\0\0",
        &mut sequence,
        255,
    );
    let mut page = vec![0_u8; 27];
    page[..4].copy_from_slice(b"OggS");
    page[5] = 1;
    page[14..18].copy_from_slice(&1_u32.to_le_bytes());
    page[26] = 255;
    page.extend([255; 255]);
    page.extend(vec![b'x'; 255 * 255]);
    let page_len = page.len();
    // The first continuation page starts a packet rather than continuing one.
    let mut start = page.clone();
    start[5] = 0;
    let mut bytes = Vec::with_capacity(64 * 1024 * 1024 + 2 * page_len);
    bytes.extend(first);
    bytes.extend(start);
    while bytes.len() <= 64 * 1024 * 1024 {
        bytes.extend(&page);
    }
    let mut input = Cursor::new(bytes);
    let error = read_audio_tags(&mut input, "opus", &|| Ok(())).unwrap_err();
    assert_eq!(error, "Ogg headers exceed 64 MiB");
    assert!(input.position() <= (64 * 1024 * 1024 + page_len + 8192) as u64);
}
