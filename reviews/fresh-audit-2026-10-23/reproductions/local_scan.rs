use std::{fs,time::UNIX_EPOCH};
use spotiflac_local::backend::Backend;
fn main(){
 let root=std::env::temp_dir().join(format!("fresh-scan-audit-{}",std::process::id()));fs::create_dir_all(&root).unwrap();
 let song=root.join("song#track2.wav");
 let mut wav=b"RIFF".to_vec();wav.extend(38u32.to_le_bytes());wav.extend(b"WAVEfmt ");wav.extend(16u32.to_le_bytes());wav.extend(1u16.to_le_bytes());wav.extend(1u16.to_le_bytes());wav.extend(44100u32.to_le_bytes());wav.extend(88200u32.to_le_bytes());wav.extend(2u16.to_le_bytes());wav.extend(16u16.to_le_bytes());wav.extend(b"data");wav.extend(2u32.to_le_bytes());wav.extend([0,0]);fs::write(&song,wav).unwrap();
 let backend=Backend::new(&root.join("data")).unwrap();backend.set_allowed_directories(std::slice::from_ref(&root)).unwrap();
 let modified=fs::metadata(&song).unwrap().modified().unwrap().duration_since(UNIX_EPOCH).unwrap().as_millis() as i64;
 let key=song.to_string_lossy().to_string();let snapshot=serde_json::json!({key:modified}).to_string();
 let result=backend.scan_library_folder_incremental(root.to_str().unwrap(),&snapshot,&||Ok(())).unwrap();
 println!("existing_song={}; deletedPaths={}; scanned={}; skipped={}",song.exists(),result["deletedPaths"],result["scanned"],result["skippedCount"]);
 drop(backend);fs::remove_dir_all(root).unwrap();
}
