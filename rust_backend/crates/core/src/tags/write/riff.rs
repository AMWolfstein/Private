use super::{Fields, Section, bytes, id3, seek};
use std::io::{Cursor, Read, Seek, SeekFrom};

pub(super) fn edit(
    source: &mut (impl Read + Seek),
    aiff: bool,
    fields: &Fields,
    cover: Option<&[u8]>,
    check: &dyn Fn() -> Result<(), String>,
) -> Result<Vec<Section>, String> {
    let length = seek(source, SeekFrom::End(0))?;
    seek(source, SeekFrom::Start(0))?;
    let header = bytes(source, 12)?;
    if &header[..4] != if aiff { b"FORM" } else { b"RIFF" } {
        return Err("unexpected container magic".into());
    }
    let mut sections = Vec::new();
    let mut start = 12_u64;
    let mut body_size = 4_u64;
    let mut found_id3 = false;
    for _ in 0..65536 {
        check()?;
        if start + 8 > length {
            break;
        }
        seek(source, SeekFrom::Start(start))?;
        let header = bytes(source, 8)?;
        let size = if aiff {
            u32::from_be_bytes(header[4..].try_into().unwrap())
        } else {
            u32::from_le_bytes(header[4..].try_into().unwrap())
        };
        let padded = start + 8 + u64::from(size) + u64::from(size & 1);
        // Some writers omit the final alignment byte of the last odd chunk.
        let end = if padded == length + 1 && size & 1 == 1 {
            length
        } else {
            padded
        };
        if end > length {
            return Err("unexpected EOF while copying audio".into());
        }
        if header[..4].eq_ignore_ascii_case(b"id3 ") {
            if size as usize > super::MAX_TAG_BYTES {
                return Err("invalid RIFF ID3 chunk size".into());
            }
            // Edit the existing frames instead of rebuilding from parsed
            // metadata: unknown TXXX frames, gapless fields, multiple pictures
            // and any tag we do not model must survive a field edit.
            let (tag, _) = id3::header(
                &mut Cursor::new(bytes(source, size as usize)?),
                fields,
                cover,
                check,
            )?;
            let tag_size = tag.len() as u32;
            let mut chunk = header[..4].to_vec();
            chunk.extend(if aiff {
                tag_size.to_be_bytes()
            } else {
                tag_size.to_le_bytes()
            });
            chunk.extend(tag);
            if tag_size & 1 == 1 {
                chunk.push(0);
            }
            body_size += chunk.len() as u64;
            sections.push(Section {
                start,
                end,
                data: chunk,
            });
            found_id3 = true;
        } else {
            body_size += end - start;
        }
        start = end;
    }
    if start + 8 <= length {
        return Err("RIFF chunk count exceeds 65536".into());
    }
    if !found_id3 {
        let cover_path = fields.get("cover_path").map(|p| p.trim()).unwrap_or("");
        if !cover_path.is_empty() && cover.is_none() {
            return Err("read cover art: file not found".into());
        }
        if cover.is_some_and(|cover| cover.is_empty()) {
            return Err("cover art is empty".into());
        }
        let tag = id3::fresh(fields, cover, check)?;
        let tag_size = tag.len() as u32;
        let mut chunk = if aiff {
            b"ID3 ".to_vec()
        } else {
            b"id3 ".to_vec()
        };
        chunk.extend(if aiff {
            tag_size.to_be_bytes()
        } else {
            tag_size.to_le_bytes()
        });
        chunk.extend(tag);
        if tag_size & 1 == 1 {
            chunk.push(0);
        }
        body_size += chunk.len() as u64;
        // Go drops an incomplete trailing chunk header, then appends the new ID3.
        sections.push(Section {
            start: start.min(length),
            end: length,
            data: chunk,
        });
    }
    let size = u32::try_from(body_size).map_err(|_| "RIFF container exceeds 32-bit size")?;
    sections.push(Section {
        start: 4,
        end: 8,
        data: if aiff {
            size.to_be_bytes()
        } else {
            size.to_le_bytes()
        }
        .to_vec(),
    });
    Ok(sections)
}
