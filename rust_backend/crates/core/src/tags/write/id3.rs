use super::{Fields, MAX_TAG_BYTES, bytes, cover_mime, edit_index, pair, seek};
use crate::matching::uppercase;
use crate::tags::id3::{decode, frame_boundary, separator, user_text};
use std::collections::BTreeSet;
use std::io::{Cursor, Read, Seek, SeekFrom};

struct Frame {
    id: Vec<u8>,
    data: Vec<u8>,
}

pub(super) fn header(
    source: &mut (impl Read + Seek),
    fields: &Fields,
    cover: Option<&[u8]>,
    check: &dyn Fn() -> Result<(), String>,
) -> Result<(Vec<u8>, u64), String> {
    edit_header(source, fields, cover, None, 512, check)
}

pub(super) fn fresh(
    fields: &Fields,
    cover: Option<&[u8]>,
    check: &dyn Fn() -> Result<(), String>,
) -> Result<Vec<u8>, String> {
    edit_header(
        &mut Cursor::new(Vec::<u8>::new()),
        fields,
        cover,
        None,
        0,
        check,
    )
    .map(|result| result.0)
}

fn edit_header(
    source: &mut (impl Read + Seek),
    fields: &Fields,
    cover: Option<&[u8]>,
    mime_override: Option<&str>,
    padding: usize,
    check: &dyn Fn() -> Result<(), String>,
) -> Result<(Vec<u8>, u64), String> {
    let (frames, audio_start) = read_frames(source, check)?;
    let mut drop = BTreeSet::<Vec<u8>>::new();
    let mut added = Vec::new();
    for (field, id, aliases) in [
        ("title", "TIT2", &[][..]),
        ("artist", "TPE1", &[][..]),
        ("album", "TALB", &[][..]),
        ("album_artist", "TPE2", &[][..]),
        ("date", "TDRC", &["TYER", "TDAT", "TIME"][..]),
        ("genre", "TCON", &[][..]),
        ("label", "TPUB", &[][..]),
        ("copyright", "TCOP", &[][..]),
        ("composer", "TCOM", &[][..]),
        ("isrc", "TSRC", &[][..]),
        ("compilation", "TCMP", &[][..]),
    ] {
        if let Some(value) = fields.get(field) {
            drop.insert(id.as_bytes().to_vec());
            for alias in aliases {
                drop.insert(alias.as_bytes().to_vec());
            }
            if !value.trim().is_empty() {
                added.push(frame(id, text(value)));
            }
        }
    }
    for (field, id) in [("comment", "COMM"), ("lyrics", "USLT")] {
        if let Some(value) = fields.get(field) {
            // Only the editor-owned language/description is replaced below;
            // iTunes gapless (iTunSMPB), normalization (iTunNORM) and
            // other-language lyrics live in separate COMM/USLT frames.
            if !value.trim().is_empty() {
                let mut data = b"\x03eng\0".to_vec();
                data.extend(value.as_bytes());
                added.push(frame(id, data));
            }
        }
    }
    for (field, total, id) in [
        ("track_number", "track_total", "TRCK"),
        ("disc_number", "disc_total", "TPOS"),
    ] {
        if fields.contains_key(field) || fields.contains_key(total) {
            let current = frames
                .iter()
                .find(|frame| frame.id == id.as_bytes())
                .map(|frame| {
                    let value = frame
                        .data
                        .split_first()
                        .map(|(encoding, data)| decode(*encoding, data))
                        .unwrap_or_default();
                    pair(value.split('\0').next().unwrap_or_default())
                })
                .unwrap_or_default();
            drop.insert(id.as_bytes().to_vec());
            let value = edit_index(current, fields, field, total);
            if !value.is_empty() {
                added.push(frame(id, text(&value)));
            }
        }
    }
    let mut drop_descriptions = BTreeSet::new();
    for (field, description) in [
        ("replaygain_track_gain", "REPLAYGAIN_TRACK_GAIN"),
        ("replaygain_track_peak", "REPLAYGAIN_TRACK_PEAK"),
        ("replaygain_album_gain", "REPLAYGAIN_ALBUM_GAIN"),
        ("replaygain_album_peak", "REPLAYGAIN_ALBUM_PEAK"),
        ("explicit", "ITUNESADVISORY"),
        ("album_type", "RELEASETYPE"),
        ("upc", "BARCODE"),
    ] {
        if let Some(value) = fields.get(field) {
            drop_descriptions.insert(description.to_owned());
            if !value.trim().is_empty() {
                let mut data = text(description);
                data.push(0);
                data.extend(value.as_bytes());
                added.push(frame("TXXX", data));
            }
        }
    }
    if let Some(cover) = cover {
        drop.insert(b"APIC".to_vec());
        let mime = if let Some(mime) = mime_override {
            mime
        } else if cover_mime(cover) != "image/jpeg" || cover.starts_with(b"\xff\xd8\xff") {
            cover_mime(cover)
        } else if cover.starts_with(b"BM") {
            "image/bmp"
        } else if cover.starts_with(b"%PDF-") {
            "application/pdf"
        } else if cover
            .iter()
            .take(512)
            .all(|b| !matches!(b, 0..=8 | 11 | 14..=26 | 28..=31))
        {
            "text/plain; charset=utf-8"
        } else {
            "application/octet-stream"
        };
        let mut data = text(mime);
        data.extend([0, 3, 0]);
        data.extend(cover);
        added.push(frame("APIC", data));
    }
    let edit_comment = fields.contains_key("comment");
    let edit_lyrics = fields.contains_key("lyrics");
    let kept = frames.into_iter().filter(|frame| {
        !drop.contains(&frame.id)
            && !(frame.id == b"TXXX"
                && drop_descriptions.contains(&uppercase(user_text(&frame.data).0.trim())))
            && !((frame.id == b"COMM" && edit_comment || frame.id == b"USLT" && edit_lyrics)
                && editor_owned_text_frame(&frame.data))
    });
    let mut body = Vec::new();
    for frame in kept.chain(added) {
        check()?;
        if body.len() + frame.data.len() + 10 + padding > MAX_TAG_BYTES {
            return Err("ID3 metadata exceeds 64 MiB".into());
        }
        body.extend(frame.id);
        body.extend(syncsafe(frame.data.len()));
        body.extend([0, 0]);
        body.extend(frame.data);
    }
    body.resize(body.len() + padding, 0);
    let mut result = b"ID3\x04\0\0".to_vec();
    result.extend(syncsafe(body.len()));
    result.extend(body);
    Ok((result, audio_start))
}

pub(in crate::tags) fn cover(tag: &[u8]) -> Option<(Vec<u8>, String)> {
    let (frames, _) = read_frames(&mut Cursor::new(tag), &|| Ok(())).ok()?;
    let data = &frames.iter().find(|frame| frame.id == b"APIC")?.data;
    // read_frames also normalizes ID3v2.2 PIC frames to APIC.
    let picture = super::super::id3::picture_frame(data, 4)?;
    Some((picture.data, picture.mime))
}

fn frame(id: &str, data: Vec<u8>) -> Frame {
    Frame {
        id: id.as_bytes().to_vec(),
        data,
    }
}
fn text(value: &str) -> Vec<u8> {
    let mut data = vec![3];
    data.extend(value.as_bytes());
    data
}

fn syncsafe(size: usize) -> [u8; 4] {
    [
        (size >> 21 & 127) as u8,
        (size >> 14 & 127) as u8,
        (size >> 7 & 127) as u8,
        (size & 127) as u8,
    ]
}

fn size(data: &[u8], syncsafe: bool) -> usize {
    if syncsafe {
        ((data[0] as usize) << 21)
            | ((data[1] as usize) << 14)
            | ((data[2] as usize) << 7)
            | data[3] as usize
    } else {
        u32::from_be_bytes(data.try_into().unwrap()) as usize
    }
}

fn read_frames(
    source: &mut (impl Read + Seek),
    check: &dyn Fn() -> Result<(), String>,
) -> Result<(Vec<Frame>, u64), String> {
    let mut header = [0; 10];
    let mut received = 0;
    while received < header.len() {
        let n = source
            .read(&mut header[received..])
            .map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        received += n;
    }
    if received < 10 || &header[..3] != b"ID3" {
        return Ok((Vec::new(), 0));
    }
    let version = header[3];
    let flags = header[5];
    if !matches!(version, 2..=4) {
        return Err("unsupported ID3 version".into());
    }
    if version == 2 && flags & 0x40 != 0 {
        return Err("compressed ID3v2.2 tag is unsupported".into());
    }
    let length = size(&header[6..], true);
    if length == 0 {
        // A zero-size tag is unusual but harmless; treat it as no frames so
        // editing can continue instead of falling back to a remux.
        return Ok((Vec::new(), 10));
    }
    if length > MAX_TAG_BYTES {
        return Err("ID3 metadata exceeds 64 MiB".into());
    }
    let end = seek(source, SeekFrom::End(0))?;
    if 10 + length as u64 > end {
        return Err("truncated ID3v2 tag".into());
    }
    seek(source, SeekFrom::Start(10))?;
    let mut data = bytes(source, length)?;
    let audio_start = 10 + length as u64 + if flags & 0x10 != 0 { 10 } else { 0 };
    if flags & 0x10 != 0 && data.len() >= 10 && &data[data.len() - 10..data.len() - 7] == b"3DI" {
        data.truncate(data.len() - 10);
    }
    // Before v2.4 unsynchronization covers the entire tag body. v2.4
    // sizes describe encoded frame payloads, so decode after slicing instead.
    if version < 4 && flags & 0x80 != 0 {
        let mut decoded = Vec::with_capacity(data.len());
        let mut index = 0;
        while index < data.len() {
            decoded.push(data[index]);
            index += if data[index] == 0xff && data.get(index + 1) == Some(&0) {
                2
            } else {
                1
            };
        }
        data = decoded;
    }
    let mut offset = 0;
    if flags & 0x40 != 0 && matches!(version, 3..=4) {
        offset = extended_header_skip(&data, version)?;
    }
    let mut frames = Vec::new();
    let header_length = if version == 2 { 6 } else { 10 };
    let id_length = if version == 2 { 3 } else { 4 };
    while offset + header_length <= data.len() {
        check()?;
        if frames.len() >= 65536 {
            return Err("ID3 frame count exceeds 65536".into());
        }
        let id = &data[offset..offset + id_length];
        if id[0] == 0 {
            if data[offset..].iter().any(|value| *value != 0) {
                return Err("invalid ID3 padding".into());
            }
            break;
        }
        if !id
            .iter()
            .all(|value| value.is_ascii_uppercase() || value.is_ascii_digit())
        {
            return Err("invalid ID3 frame id".into());
        }
        let length = if version == 2 {
            ((data[offset + 3] as usize) << 16)
                | ((data[offset + 4] as usize) << 8)
                | data[offset + 5] as usize
        } else {
            size(&data[offset + 4..offset + 8], version == 4)
        };
        if length == 0 {
            // Skip a malformed empty frame only when the next position is
            // still a frame or padding. Otherwise refuse the rewrite.
            offset += header_length;
            if offset < data.len() && !frame_boundary(&data, offset, version) {
                return Err("invalid zero-length ID3 frame".into());
            }
            continue;
        }
        if length > data.len() - offset - header_length {
            return Err("truncated ID3 frame".into());
        }
        let frame_flags = if version == 2 { 0 } else { data[offset + 9] };
        let mut payload = &data[offset + header_length..offset + header_length + length];
        offset += header_length + length;
        if version == 3 {
            if frame_flags & 0xc0 != 0 {
                return Err("compressed or encrypted ID3 frame is unsupported".into());
            }
            if frame_flags & 0x20 != 0 {
                payload = payload.get(1..).ok_or("invalid ID3 grouping byte")?;
            }
        } else if version != 2 {
            if frame_flags & 0x0c != 0 {
                return Err("compressed or encrypted ID3 frame is unsupported".into());
            }
            if frame_flags & 0x40 != 0 {
                payload = payload.get(1..).ok_or("invalid ID3 grouping byte")?;
            }
            if frame_flags & 1 != 0 {
                if payload.len() < 4 {
                    return Err("invalid ID3 data length indicator".into());
                }
                payload = &payload[4..];
            }
        }
        let mut payload = if version == 4 && (frame_flags & 2 != 0 || flags & 0x80 != 0) {
            let mut result = Vec::new();
            let mut offset = 0;
            while offset < payload.len() {
                result.push(payload[offset]);
                offset += if payload[offset] == 0xff && payload.get(offset + 1) == Some(&0) {
                    2
                } else {
                    1
                };
            }
            result
        } else {
            payload.to_vec()
        };
        let id = if version == 2 {
            match id {
                b"TT2" => b"TIT2".as_slice(),
                b"TP1" => b"TPE1",
                b"TP2" => b"TPE2",
                b"TAL" => b"TALB",
                b"TYE" => b"TDRC",
                b"TCO" => b"TCON",
                b"TRK" => b"TRCK",
                b"TPA" => b"TPOS",
                b"TCM" => b"TCOM",
                b"TPB" => b"TPUB",
                b"TCR" => b"TCOP",
                b"TXX" => b"TXXX",
                b"ULT" => b"USLT",
                b"COM" => b"COMM",
                b"PIC" => {
                    if payload.len() < 5 {
                        return Err("invalid ID3v2.2 picture frame".into());
                    }
                    let mime = if payload[1..4].eq_ignore_ascii_case(b"PNG") {
                        "image/png"
                    } else {
                        "image/jpeg"
                    };
                    let mut converted = vec![payload[0]];
                    converted.extend(mime.as_bytes());
                    converted.push(0);
                    converted.extend(&payload[4..]);
                    payload = converted;
                    b"APIC"
                }
                _ => return Err("unsupported ID3v2.2 frame".into()),
            }
        } else {
            id
        };
        frames.push(Frame {
            id: id.to_vec(),
            data: payload,
        });
    }
    if offset < data.len() && data[offset..].iter().any(|value| *value != 0) {
        return Err("trailing ID3 data is not a frame".into());
    }
    Ok((frames, audio_start))
}

/// Returns the number of bytes occupied by an ID3v2.3/v2.4 extended header.
/// ID3v2.4 includes its own four-byte size in the value; some writers still
/// store the ID3v2.3 form, so accept either when it lands on a frame boundary.
fn extended_header_skip(data: &[u8], version: u8) -> Result<usize, String> {
    if data.len() < 4 {
        return Err("invalid ID3 extended header".into());
    }
    let declared = size(&data[..4], version == 4);
    let candidates = if version == 4 {
        [declared, declared + 4]
    } else {
        [declared + 4, declared]
    };
    candidates
        .into_iter()
        .find(|skip| *skip >= 4 && *skip <= data.len() && frame_boundary(data, *skip, version))
        .ok_or_else(|| "invalid ID3 extended header".into())
}

/// True for the COMM/USLT frame shape this editor writes (English, empty
/// description). Other descriptions and languages must survive an edit.
fn editor_owned_text_frame(data: &[u8]) -> bool {
    let Some((&encoding, body)) = data.split_first() else {
        return false;
    };
    if body.len() < 3 || !body[..3].eq_ignore_ascii_case(b"eng") {
        return false;
    }
    let Some((end, _)) = separator(body.get(3..).unwrap_or_default(), encoding) else {
        return false;
    };
    decode(encoding, &body[3..3 + end]).is_empty()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn encoded_frame(id: &str, data: Vec<u8>) -> Vec<u8> {
        [id.as_bytes(), &syncsafe(data.len()), &[0, 0], &data].concat()
    }

    fn tag(version: u8, flags: u8, body: &[u8]) -> Vec<u8> {
        let mut result = vec![b'I', b'D', b'3', version, 0, flags];
        result.extend(syncsafe(body.len()));
        result.extend(body);
        result.extend(b"audio bytes");
        result
    }

    #[test]
    fn v24_unsync_is_decoded_once_after_frame_slicing() {
        for frame_flags in [0, 2] {
            // The original private payload includes FF 00. Escaping adds one
            // zero; decoding twice would incorrectly remove the original zero.
            let mut body = b"PRIV".to_vec();
            body.extend(syncsafe(4));
            body.extend([0, frame_flags, 0xff, 0, 0, 0xe0]);
            body.extend(encoded_frame("TIT2", b"\x03title".to_vec()));
            let input = tag(4, 0x80, &body);
            let (frames, end) = read_frames(&mut Cursor::new(&input), &|| Ok(())).unwrap();
            assert_eq!(frames[0].data, [0xff, 0, 0xe0]);
            assert_eq!(frames[1].data, b"\x03title");
            assert_eq!(&input[end as usize..], b"audio bytes");
        }
    }

    #[test]
    fn utf16_bom_empty_description_is_replaced_or_cleared() {
        for id in ["USLT", "COMM"] {
            for value in ["", "replacement"] {
                let body = encoded_frame(id, b"\x01eng\xff\xfe\0\0\xff\xfeo\0l\0d\0".to_vec());
                let fields = [(
                    if id == "USLT" { "lyrics" } else { "comment" }.into(),
                    value.into(),
                )]
                .into();
                let (output, _) = header(
                    &mut Cursor::new(tag(4, 0, &body)),
                    &fields,
                    None,
                    &|| Ok(()),
                )
                .unwrap();
                let (frames, _) = read_frames(&mut Cursor::new(output), &|| Ok(())).unwrap();
                let owned: Vec<_> = frames.iter().filter(|f| f.id == id.as_bytes()).collect();
                assert_eq!(owned.len(), usize::from(!value.is_empty()));
                if let Some(frame) = owned.first() {
                    assert_eq!(&frame.data[5..], value.as_bytes());
                }
            }
        }
        assert!(!editor_owned_text_frame(
            b"\x01eng\xff\xfeD\0e\0s\0c\0\0\0text"
        ));
    }

    #[test]
    fn malformed_frame_refuses_rewrite_instead_of_dropping_tail() {
        for body in [
            b"TIT2\0\0\0\x7f\0\0short".as_slice(),
            b"TIT2\0\0\0\0\0\0bad tail",
        ] {
            assert!(
                header(
                    &mut Cursor::new(tag(4, 0, body)),
                    &Fields::new(),
                    None,
                    &|| Ok(())
                )
                .is_err()
            );
        }
    }

    #[test]
    fn v24_extended_header_preserves_private_frames() {
        let mut body = vec![0, 0, 0, 6, 1, 0];
        body.extend(encoded_frame("PRIV", b"owner\0untouched".to_vec()));
        let (output, _) = header(
            &mut Cursor::new(tag(4, 0x40, &body)),
            &Fields::new(),
            None,
            &|| Ok(()),
        )
        .unwrap();
        let (frames, _) = read_frames(&mut Cursor::new(output), &|| Ok(())).unwrap();
        assert_eq!(frames.len(), 1);
        assert_eq!(frames[0].data, b"owner\0untouched");
    }

    #[test]
    fn empty_tag_can_be_edited_without_remuxing() {
        let fields = [("title".into(), "new".into())].into();
        let (output, end) =
            header(&mut Cursor::new(tag(4, 0, &[])), &fields, None, &|| Ok(())).unwrap();
        assert_eq!(end, 10);
        let (frames, _) = read_frames(&mut Cursor::new(output), &|| Ok(())).unwrap();
        assert_eq!(frames[0].data, b"\x03new");
    }
}
