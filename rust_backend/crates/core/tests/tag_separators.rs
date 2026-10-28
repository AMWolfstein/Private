use sistrum_core::tags::{read_audio_tags, rewrite_audio_tags};
use std::collections::BTreeMap;
use std::io::Cursor;

const PAYLOAD: &[u8] = b"\xff\xf8\x12\x34unchanged audio payload";

#[test]
fn custom_separators_round_trip_all_tag_writers_without_touching_audio() {
    for format in ["flac", "mp3", "m4a", "opus", "ape", "wav", "aiff"] {
        let fields = BTreeMap::from([
            ("title".into(), "Title, unchanged".into()),
            ("artist".into(), "A, B".into()),
            ("album_artist".into(), "C; D".into()),
            ("composer".into(), "E, F".into()),
            ("genre".into(), "Rock, Pop".into()),
            ("artist_separator".into(), " / ".into()),
            ("album_artist_separator".into(), "; ".into()),
            ("composer_separator".into(), " | ".into()),
            ("genre_separator".into(), "; ".into()),
        ]);
        let mut output = Vec::new();
        rewrite_audio_tags(
            &mut Cursor::new(source(format)),
            &mut output,
            format,
            &fields,
            None,
            &|| Ok(()),
        )
        .unwrap();
        let metadata = read_audio_tags(&mut Cursor::new(&output), format, &|| Ok(())).unwrap();
        assert_eq!(metadata.artist, "A / B", "{format}");
        assert_eq!(metadata.album_artist, "C; D", "{format}");
        assert_eq!(metadata.composer, "E | F", "{format}");
        assert_eq!(metadata.genre, "Rock; Pop", "{format}");
        assert_eq!(metadata.title, "Title, unchanged", "{format}");
        assert!(
            output.windows(PAYLOAD.len()).any(|chunk| chunk == PAYLOAD),
            "{format}"
        );
        assert!(
            !output
                .windows(b"_separator".len())
                .any(|chunk| chunk == b"_separator")
        );
    }
}

fn atom(kind: &[u8; 4], body: &[u8]) -> Vec<u8> {
    [
        ((body.len() + 8) as u32).to_be_bytes().as_slice(),
        kind,
        body,
    ]
    .concat()
}

fn ogg_page(packet: &[u8], sequence: u32, flags: u8) -> Vec<u8> {
    let mut header = vec![0; 27];
    header[..4].copy_from_slice(b"OggS");
    header[5] = flags;
    header[14..18].copy_from_slice(&1_u32.to_le_bytes());
    header[18..22].copy_from_slice(&sequence.to_le_bytes());
    header[26] = 1;
    header.push(packet.len() as u8);
    header.extend(packet);
    header
}

fn source(format: &str) -> Vec<u8> {
    match format {
        "flac" => [b"fLaC\x80\0\0\x22".as_slice(), &[0; 34], PAYLOAD].concat(),
        "mp3" | "ape" => PAYLOAD.to_vec(),
        "m4a" => [
            atom(b"ftyp", b"M4A \0\0\0\0"),
            atom(b"moov", &[]),
            atom(b"mdat", PAYLOAD),
        ]
        .concat(),
        "opus" => [
            ogg_page(b"OpusHead\x01\x02\0\0\x80\xbb\0\0\0\0\0", 0, 2),
            ogg_page(b"OpusTags\0\0\0\0\0\0\0\0", 1, 0),
            ogg_page(PAYLOAD, 2, 4),
        ]
        .concat(),
        "wav" | "aiff" => {
            let aiff = format == "aiff";
            let mut body = if aiff { b"AIFFSSND" } else { b"WAVEdata" }.to_vec();
            let length = PAYLOAD.len() as u32;
            body.extend(if aiff {
                length.to_be_bytes()
            } else {
                length.to_le_bytes()
            });
            body.extend(PAYLOAD);
            if length % 2 == 1 {
                body.push(0);
            }
            let length = body.len() as u32;
            [
                if aiff { b"FORM" } else { b"RIFF" }.as_slice(),
                &if aiff {
                    length.to_be_bytes()
                } else {
                    length.to_le_bytes()
                },
                &body,
            ]
            .concat()
        }
        _ => unreachable!(),
    }
}
