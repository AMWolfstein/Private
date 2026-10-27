use super::{AudioMetadata, CoverArt, bytes, exact, pair, seek, truthy, utf8};
use crate::matching::{lowercase, uppercase};
use std::io::{self, Cursor, Read, Seek, SeekFrom};

// ID3v2.2/2.3 global unsynchronization also covers frame headers. Decode
// incrementally so skipping artwork never requires a tag-sized allocation.
struct Input<'a, R> {
    source: &'a mut R,
    remaining: u64,
    unsync: bool,
    after_ff: bool,
}

impl<R: Read> Read for Input<'_, R> {
    fn read(&mut self, output: &mut [u8]) -> io::Result<usize> {
        if !self.unsync {
            let length = output.len().min(self.remaining as usize);
            let count = self.source.read(&mut output[..length])?;
            self.remaining -= count as u64;
            return Ok(count);
        }
        let mut count = 0;
        while count < output.len() && self.remaining > 0 {
            let mut value = [0];
            if self.source.read(&mut value)? == 0 {
                break;
            }
            self.remaining -= 1;
            if self.after_ff && value[0] == 0 {
                self.after_ff = false;
                continue;
            }
            self.after_ff = value[0] == 0xff;
            output[count] = value[0];
            count += 1;
        }
        Ok(count)
    }
}

impl<R: Read + Seek> Input<'_, R> {
    fn skip(&mut self, length: u64) -> Result<(), String> {
        if !self.unsync {
            seek(self.source, SeekFrom::Current(length as i64))?;
            self.remaining = self.remaining.saturating_sub(length);
            return Ok(());
        }
        let mut left = length;
        let mut buffer = [0; 8192];
        while left > 0 {
            let count = left.min(buffer.len() as u64) as usize;
            exact(self, &mut buffer[..count])?;
            left -= count as u64;
        }
        Ok(())
    }
}

pub(super) fn read(reader: &mut (impl Read + Seek)) -> Result<AudioMetadata, String> {
    let mut metadata = v2(reader).unwrap_or_default();
    if (metadata.title.is_empty() || metadata.artist.is_empty())
        && let Ok(old) = v1(reader)
    {
        for (target, value) in [
            (&mut metadata.title, old.title),
            (&mut metadata.artist, old.artist),
            (&mut metadata.album, old.album),
            (&mut metadata.year, old.year),
            (&mut metadata.genre, old.genre),
        ] {
            if target.is_empty() {
                *target = value;
            }
        }
    }
    if metadata == AudioMetadata::default() {
        Err("no ID3 tags found".into())
    } else {
        Ok(metadata)
    }
}

fn v2(reader: &mut (impl Read + Seek)) -> Result<AudioMetadata, String> {
    v2_with_cover(reader, false).map(|(metadata, _)| metadata)
}

pub(super) fn cover(reader: &mut (impl Read + Seek)) -> Result<CoverArt, String> {
    v2_with_cover(reader, true)?
        .1
        .ok_or_else(|| "no cover art found".into())
}

fn v2_with_cover(
    reader: &mut (impl Read + Seek),
    include_cover: bool,
) -> Result<(AudioMetadata, Option<CoverArt>), String> {
    let header = bytes(reader, 10)?;
    if &header[..3] != b"ID3" {
        return Err("no ID3v2 header".into());
    }
    let version = header[3];
    let flags = header[5];
    if !(2..=4).contains(&version) || header[6..].iter().any(|value| *value >= 128) {
        return Err("invalid ID3 version or tag size".into());
    }
    let mut size = syncsafe(&header[6..]);
    let end = seek(reader, SeekFrom::End(0))?;
    if size > end.saturating_sub(10) {
        return Err("unexpected EOF".into());
    }
    seek(reader, SeekFrom::Start(10))?;
    let mut input = Input {
        source: reader,
        remaining: size,
        unsync: version < 4 && flags & 0x80 != 0,
        after_ff: false,
    };
    if flags & 0x40 != 0 {
        if version == 2 {
            return Err("compressed ID3v2.2 tag unsupported".into());
        }
        let extended = bytes(&mut input, 4)?;
        let length = if version == 4 {
            syncsafe(&extended).checked_sub(4)
        } else {
            Some(u64::from(u32::from_be_bytes(extended.try_into().unwrap())))
        }
        .ok_or("invalid ID3 extended header")?;
        if size < 4 || length > size - 4 {
            return Err("invalid ID3 extended header".into());
        }
        input.skip(length)?;
        size -= length + 4;
    }
    let mut metadata = AudioMetadata::default();
    let mut cover = None;
    // Go retains fields decoded before a malformed later frame.
    let result = frames(
        &mut input,
        size,
        version,
        version == 4 && flags & 0x80 != 0,
        &mut metadata,
        include_cover.then_some(&mut cover),
    );
    if include_cover && cover.is_none() {
        result?;
    }
    Ok((metadata, cover))
}

pub(super) fn embedded(data: &[u8]) -> Result<AudioMetadata, String> {
    if data.len() < 10 || &data[..3] != b"ID3" {
        return Err("no ID3v2 header".into());
    }
    let version = data[3];
    let flags = data[5];
    let size = syncsafe(&data[6..10]) as usize;
    let size = if size == 0 || size > data.len() - 10 {
        data.len() - 10
    } else {
        size
    };
    let mut body = &data[10..10 + size];
    if flags & 0x10 != 0 && body.len() >= 10 && body[body.len() - 10..].starts_with(b"3DI") {
        body = &body[..body.len() - 10];
    }
    if flags & 0x40 != 0 && matches!(version, 3..=4) && body.len() >= 4 {
        let declared = match version {
            3 => u32::from_be_bytes(body[..4].try_into().unwrap()) as usize,
            _ => syncsafe(&body[..4]) as usize,
        };
        let candidates = if version == 4 {
            [declared, declared + 4]
        } else {
            [declared + 4, declared]
        };
        if let Some(skip) = candidates
            .into_iter()
            .find(|skip| *skip >= 4 && *skip <= body.len() && frame_boundary(body, *skip, version))
            && skip < body.len()
        {
            body = &body[skip..];
        }
    }
    let size = body.len() as u64;
    let mut cursor = Cursor::new(body);
    let mut input = Input {
        source: &mut cursor,
        remaining: size,
        unsync: false,
        after_ff: false,
    };
    let mut metadata = AudioMetadata::default();
    let _ = frames(
        &mut input,
        size,
        version,
        flags & 0x80 != 0,
        &mut metadata,
        None,
    );
    Ok(metadata)
}

fn frames<R: Read + Seek>(
    input: &mut Input<'_, R>,
    mut remaining: u64,
    version: u8,
    unsync: bool,
    metadata: &mut AudioMetadata,
    mut cover: Option<&mut Option<CoverArt>>,
) -> Result<(), String> {
    let (header_size, id_size) = if version == 2 { (6, 3) } else { (10, 4) };
    while remaining >= header_size as u64 {
        let header = bytes(input, header_size)?;
        remaining -= header_size as u64;
        if header[0] == 0 || header.starts_with(b"3DI") {
            break;
        }
        let size = match version {
            2 => u64::from(u32::from_be_bytes([0, header[3], header[4], header[5]])),
            4 => {
                if header[4..8].iter().any(|value| *value >= 128) {
                    return Err("invalid ID3 frame size".into());
                }
                syncsafe(&header[4..8])
            }
            _ => u64::from(u32::from_be_bytes(header[4..8].try_into().unwrap())),
        };
        if size == 0 || size > remaining {
            return Err("invalid ID3 frame bounds".into());
        }
        remaining -= size;
        let id = &header[..id_size];
        let flags = if version == 2 { 0 } else { header[9] };
        let picture = matches!(id, b"APIC" | b"PIC");
        let wanted = if picture {
            cover.as_ref().is_some_and(|cover| cover.is_none())
        } else {
            id[0] == b'T' || matches!(id, b"COMM" | b"USLT" | b"ULT")
        };
        let unsupported =
            (version == 3 && flags & 0xc0 != 0) || (version == 4 && flags & 0x0c != 0);
        if !wanted || unsupported || size > 32 * 1024 * 1024 {
            input.skip(size)?;
            continue;
        }
        let mut data = bytes(input, size as usize)?;
        let mut offset =
            usize::from((version == 3 && flags & 0x20 != 0) || (version == 4 && flags & 0x40 != 0));
        if version == 4 && flags & 1 != 0 {
            offset += 4;
        }
        if offset > data.len() {
            continue;
        }
        if unsync || version == 4 && flags & 2 != 0 {
            let mut after_ff = false;
            let mut write = offset;
            for read in offset..data.len() {
                let value = data[read];
                if after_ff && value == 0 {
                    after_ff = false;
                    continue;
                }
                after_ff = value == 0xff;
                data[write] = value;
                write += 1;
            }
            data.truncate(write);
        }
        if picture {
            if let Some(cover) = cover.as_deref_mut() {
                *cover = picture_frame(&data[offset..], version);
            }
        } else {
            apply(metadata, version, id, &data[offset..]);
        }
    }
    Ok(())
}

pub(in crate::tags) fn picture_frame(data: &[u8], version: u8) -> Option<CoverArt> {
    let encoding = *data.first()?;
    let (mime, start) = if version == 2 {
        let format = data.get(1..4)?;
        (
            if format == b"PNG" {
                "image/png"
            } else {
                "image/jpeg"
            }
            .into(),
            5,
        )
    } else {
        let end = data.get(1..)?.iter().position(|byte| *byte == 0)? + 1;
        (utf8(&data[1..end]), end + 2)
    };
    let description = data.get(start..)?;
    let (end, terminator) = separator(description, encoding)?;
    let mut image = description.get(end + terminator..)?;
    // Some taggers add redundant NULs after the description. Only remove
    // them when the remaining bytes have a recognized image signature.
    if image.first() == Some(&0)
        && let Some(start) = image.iter().position(|byte| *byte != 0)
        && image::guess_format(&image[start..]).is_ok()
    {
        image = &image[start..];
    }
    (!image.is_empty()).then(|| CoverArt {
        data: image.to_vec(),
        mime,
    })
}

fn apply(metadata: &mut AudioMetadata, version: u8, id: &[u8], data: &[u8]) {
    let text = data
        .split_first()
        .map(|(encoding, body)| decode(*encoding, body))
        .unwrap_or_default();
    let value = text.split('\0').next().unwrap_or_default();
    let id = if version == 2 {
        match id {
            b"TT2" => b"TIT2".as_slice(),
            b"TP1" => b"TPE1",
            b"TP2" => b"TPE2",
            b"TAL" => b"TALB",
            b"TYE" => {
                metadata.year = value.into();
                return;
            }
            b"TCO" => b"TCON",
            b"TRK" => b"TRCK",
            b"TPA" => b"TPOS",
            b"TCM" => b"TCOM",
            b"TPB" => b"TPUB",
            b"TCR" => b"TCOP",
            b"ULT" => b"USLT",
            b"TXX" => b"TXXX",
            _ => return,
        }
    } else {
        id
    };
    match id {
        b"TIT2" => metadata.title = value.into(),
        b"TPE1" => metadata.artist = value.into(),
        b"TPE2" => metadata.album_artist = value.into(),
        b"TALB" => metadata.album = value.into(),
        b"TYER" | b"TDRC" => {
            metadata.year = value.into();
            if value.len() >= 4 {
                metadata.date = value.into();
            }
        }
        b"TCON" => metadata.genre = genre(value),
        b"TRCK" => (metadata.track_number, metadata.total_tracks) = pair(value),
        b"TPOS" => (metadata.disc_number, metadata.total_discs) = pair(value),
        b"TSRC" => metadata.isrc = value.into(),
        b"TCOM" => metadata.composer = value.into(),
        b"TPUB" => metadata.label = value.into(),
        b"TCOP" => metadata.copyright = value.into(),
        b"TCMP" if truthy(value) && metadata.album_type.is_empty() => {
            metadata.album_type = "compilation".into()
        }
        b"COMM" | b"USLT" => {
            let value = language(data);
            if !value.is_empty() {
                if id == b"COMM" {
                    metadata.comment = value;
                } else if metadata.lyrics.is_empty() {
                    metadata.lyrics = value;
                }
            }
        }
        b"TXXX" => {
            let (description, value) = user_text(data);
            if matches!(
                lowercase(description.trim()).as_str(),
                "lyrics"
                    | "lyric"
                    | "unsyncedlyrics"
                    | "unsynced lyrics"
                    | "syncedlyrics"
                    | "synced lyrics"
                    | "uslt"
                    | "sylt"
                    | "lrc"
            ) && metadata.lyrics.is_empty()
                && !value.is_empty()
            {
                metadata.lyrics = value.clone();
            }
            match uppercase(&description).as_str() {
                "ITUNESADVISORY" => metadata.explicit = truthy(&value),
                "RELEASETYPE" => metadata.album_type = value,
                "BARCODE" | "UPC" => metadata.upc = value,
                "REPLAYGAIN_TRACK_GAIN" if version != 2 => metadata.replay_gain_track_gain = value,
                "REPLAYGAIN_TRACK_PEAK" if version != 2 => metadata.replay_gain_track_peak = value,
                "REPLAYGAIN_ALBUM_GAIN" if version != 2 => metadata.replay_gain_album_gain = value,
                "REPLAYGAIN_ALBUM_PEAK" if version != 2 => metadata.replay_gain_album_peak = value,
                _ => {}
            }
        }
        _ => {}
    }
}

pub(crate) fn decode(encoding: u8, mut data: &[u8]) -> String {
    if encoding == 0 {
        return latin1(data).trim_end_matches('\0').into();
    }
    if !matches!(encoding, 1 | 2) {
        return utf8(data).trim_end_matches('\0').into();
    }
    let mut little = false;
    if encoding == 1 {
        if data.starts_with(&[0xff, 0xfe]) {
            little = true;
            data = &data[2..];
        } else if data.starts_with(&[0xfe, 0xff]) {
            data = &data[2..];
        }
    }
    let units = data.as_chunks::<2>().0.iter().map(|pair| {
        if little {
            u16::from_le_bytes([pair[0], pair[1]])
        } else {
            u16::from_be_bytes([pair[0], pair[1]])
        }
    });
    let mut text = String::new();
    for value in char::decode_utf16(units) {
        match value {
            Ok('\0') => break,
            Ok(value) => text.push(value),
            Err(_) => text.push(char::REPLACEMENT_CHARACTER),
        }
    }
    text
}

/// ID3 encoding 0 is ISO-8859-1, but many taggers write UTF-8 without
/// changing the encoding byte. Accept valid UTF-8, otherwise map every byte
/// to its Latin-1 code point instead of producing replacement characters.
fn latin1(data: &[u8]) -> String {
    match std::str::from_utf8(data) {
        Ok(value) => value.into(),
        Err(_) => data.iter().map(|value| char::from(*value)).collect(),
    }
}

pub(super) fn separator(data: &[u8], encoding: u8) -> Option<(usize, usize)> {
    if matches!(encoding, 1 | 2) {
        data.as_chunks::<2>()
            .0
            .iter()
            .position(|pair| *pair == [0, 0])
            .map(|index| (index * 2, 2))
    } else {
        data.iter()
            .position(|value| *value == 0)
            .map(|index| (index, 1))
    }
}

/// Whether `offset` starts an ID3 frame id (or padding) for this version.
pub(super) fn frame_boundary(data: &[u8], offset: usize, version: u8) -> bool {
    if offset == data.len() {
        return true;
    }
    let id_length = if version == 2 { 3 } else { 4 };
    let Some(id) = data.get(offset..offset + id_length) else {
        return false;
    };
    id[0] == 0
        || id
            .iter()
            .all(|value| value.is_ascii_uppercase() || value.is_ascii_digit())
}

fn language(data: &[u8]) -> String {
    if data.len() < 5 {
        return String::new();
    }
    let encoding = data[0];
    let rest = &data[4..];
    let text = match separator(rest, encoding) {
        Some((index, size)) if matches!(encoding, 1 | 2) || index + size < rest.len() => {
            &rest[index + size..]
        }
        _ if matches!(encoding, 1 | 2) => &[],
        _ => rest,
    };
    decode(encoding, text)
}

pub(crate) fn user_text(data: &[u8]) -> (String, String) {
    let Some((&encoding, body)) = data.split_first() else {
        return Default::default();
    };
    let Some((index, size)) = separator(body, encoding) else {
        return Default::default();
    };
    if index + size >= body.len() {
        return Default::default();
    }
    (
        decode(encoding, &body[..index]).trim().into(),
        decode(encoding, &body[index + size..]).trim().into(),
    )
}

fn v1(reader: &mut (impl Read + Seek)) -> Result<AudioMetadata, String> {
    let end = seek(reader, SeekFrom::End(0))?;
    if end < 128 {
        return Err("no ID3v1 tag found".into());
    }
    seek(reader, SeekFrom::Start(end - 128))?;
    let data = bytes(reader, 128)?;
    if !data.starts_with(b"TAG") {
        return Err("no ID3v1 tag".into());
    }
    let text = |start, end| {
        latin1(&data[start..end])
            .trim_end_matches([' ', '\0'])
            .to_owned()
    };
    Ok(AudioMetadata {
        title: text(3, 33),
        artist: text(33, 63),
        album: text(63, 93),
        year: text(93, 97),
        genre: GENRES.get(data[127] as usize).unwrap_or(&"").to_string(),
        ..AudioMetadata::default()
    })
}

/// The length of a whole ID3v2 tag, footer included, from its 10-byte header,
/// or None when the header is not ID3v2. Some taggers put one in front of a
/// FLAC or ADTS stream, and players skip it.
pub(crate) fn v2_tag_length(header: &[u8]) -> Option<u64> {
    if header.len() < 10
        || &header[..3] != b"ID3"
        || header[6..10].iter().any(|value| *value >= 128)
    {
        return None;
    }
    let footer = if header[5] & 0x10 != 0 { 10 } else { 0 };
    Some(10 + syncsafe(&header[6..10]) + footer)
}

fn syncsafe(data: &[u8]) -> u64 {
    u64::from(data[0]) << 21
        | u64::from(data[1]) << 14
        | u64::from(data[2]) << 7
        | u64::from(data[3])
}

pub(super) fn genre(value: &str) -> String {
    if value.starts_with('(')
        && let Some(end) = value.find(')')
        && let Ok(index) = value[1..end].parse::<usize>()
        && let Some(genre) = GENRES.get(index)
    {
        return if end + 1 < value.len() {
            value[end + 1..].into()
        } else {
            (*genre).into()
        };
    }
    value.into()
}

const GENRES: &[&str] = &[
    "Blues",
    "Classic Rock",
    "Country",
    "Dance",
    "Disco",
    "Funk",
    "Grunge",
    "Hip-Hop",
    "Jazz",
    "Metal",
    "New Age",
    "Oldies",
    "Other",
    "Pop",
    "R&B",
    "Rap",
    "Reggae",
    "Rock",
    "Techno",
    "Industrial",
    "Alternative",
    "Ska",
    "Death Metal",
    "Pranks",
    "Soundtrack",
    "Euro-Techno",
    "Ambient",
    "Trip-Hop",
    "Vocal",
    "Jazz+Funk",
    "Fusion",
    "Trance",
    "Classical",
    "Instrumental",
    "Acid",
    "House",
    "Game",
    "Sound Clip",
    "Gospel",
    "Noise",
    "AlternRock",
    "Bass",
    "Soul",
    "Punk",
    "Space",
    "Meditative",
    "Instrumental Pop",
    "Instrumental Rock",
    "Ethnic",
    "Gothic",
    "Darkwave",
    "Techno-Industrial",
    "Electronic",
    "Pop-Folk",
    "Eurodance",
    "Dream",
    "Southern Rock",
    "Comedy",
    "Cult",
    "Gangsta",
    "Top 40",
    "Christian Rap",
    "Pop/Funk",
    "Jungle",
    "Native American",
    "Cabaret",
    "New Wave",
    "Psychedelic",
    "Rave",
    "Showtunes",
    "Trailer",
    "Lo-Fi",
    "Tribal",
    "Acid Punk",
    "Acid Jazz",
    "Polka",
    "Retro",
    "Musical",
    "Rock & Roll",
    "Hard Rock",
    "Folk",
    "Folk-Rock",
    "National Folk",
    "Swing",
    "Fast Fusion",
    "Bebop",
    "Latin",
    "Revival",
    "Celtic",
    "Bluegrass",
    "Avantgarde",
    "Gothic Rock",
    "Progressive Rock",
    "Psychedelic Rock",
    "Symphonic Rock",
    "Slow Rock",
    "Big Band",
    "Chorus",
    "Easy Listening",
    "Acoustic",
    "Humour",
    "Speech",
    "Chanson",
    "Opera",
    "Chamber Music",
    "Sonata",
    "Symphony",
    "Booty Bass",
    "Primus",
    "Porn Groove",
    "Satire",
    "Slow Jam",
    "Club",
    "Tango",
    "Samba",
    "Folklore",
    "Ballad",
    "Power Ballad",
    "Rhythmic Soul",
    "Freestyle",
    "Duet",
    "Punk Rock",
    "Drum Solo",
    "A capella",
    "Euro-House",
    "Dance Hall",
    "Goa",
    "Drum & Bass",
    "Club-House",
    "Hardcore",
    "Terror",
    "Indie",
    "BritPop",
    "Negerpunk",
    "Polsk Punk",
    "Beat",
    "Christian Gangsta Rap",
    "Heavy Metal",
    "Black Metal",
    "Crossover",
    "Contemporary Christian",
    "Christian Rock",
    "Merengue",
    "Salsa",
    "Thrash Metal",
    "Anime",
    "J-Pop",
    "Synthpop",
];

#[cfg(test)]
mod decoding_tests {
    use super::*;

    #[test]
    fn latin1_and_utf16_surrogates_decode_without_replacement() {
        assert_eq!(decode(0, b"Beyonc\xe9"), "Beyoncé");
        assert_eq!(decode(0, "Beyoncé".as_bytes()), "Beyoncé");
        assert_eq!(decode(1, &[0xff, 0xfe, 0x3d, 0xd8, 0x00, 0xde]), "😀");
        assert_eq!(decode(2, &[0xd8, 0x3d, 0xde, 0x00]), "😀");
    }

    #[test]
    fn utf16_picture_description_terminator_is_aligned() {
        let payload = b"\x01image/jpeg\0\x03\xff\xfeA\0\0\0\xff\xd8\xff\xd9";
        let picture = picture_frame(payload, 4).unwrap();
        assert_eq!(picture.data, b"\xff\xd8\xff\xd9");
    }
}
