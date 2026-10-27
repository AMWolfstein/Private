// T16 mechanically renamed historical identifiers; this reproduction was not rerun.
use std::{collections::BTreeMap,fs,io::Cursor};
use sistrum_core::tags::rewrite_audio_tags;
fn syn(n:usize)->[u8;4]{[((n>>21)&127)as u8,((n>>14)&127)as u8,((n>>7)&127)as u8,(n&127)as u8]}
fn main(){
 let payload=b"\x03Original Artist";
 let mut body=vec![0,0,0,6,1,0];
 body.extend(b"TPE1");body.extend(syn(payload.len()));body.extend([0,0]);body.extend(payload);body.extend([0;32]);
 let mut input=b"ID3\x04\x00\x40".to_vec();input.extend(syn(body.len()));input.extend(body);input.extend(b"AUDIO_TAIL");
 let fields=BTreeMap::from([("title".to_string(),"Edited title".to_string())]);
 let mut out=vec![];let id3=rewrite_audio_tags(&mut Cursor::new(input),&mut out,"mp3",&fields,None,&||Ok(()));
 println!("ID3v2.4 rewrite={id3:?}; original_artist_preserved={}; audio_tail_preserved={}",out.windows(payload.len()).any(|w|w==payload),out.ends_with(b"AUDIO_TAIL"));
 let mut f=b"fLaC".to_vec();f.extend([0x80,0,0,34]);f.extend([0;34]);f.extend([0xff,0xf8,1,2,3]);
 let cover=fs::read("/workspace/Private-audit/test/fixtures/covers/saturated.png").unwrap();
 let mut with_cover=vec![];rewrite_audio_tags(&mut Cursor::new(f),&mut with_cover,"flac",&BTreeMap::new(),Some(&cover),&||Ok(())).unwrap();
 let huge_invalid=vec![0u8;16_000_001];let mut replaced=vec![];
 let r=rewrite_audio_tags(&mut Cursor::new(with_cover),&mut replaced,"flac",&fields,Some(&huge_invalid),&||Ok(()));
 println!("FLAC invalid large cover rewrite={r:?}; original_cover_preserved={}",replaced.windows(cover.len()).any(|w|w==cover));
}
