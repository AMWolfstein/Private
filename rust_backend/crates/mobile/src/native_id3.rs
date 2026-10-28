//! Artwork picture blocks for the native metadata writers.
use base64::Engine;
use serde_json::{Value, json};
use std::fs;

pub(crate) fn execute(
    request: &Value,
    _bytes: Option<&[u8]>,
    check: &dyn Fn() -> Result<(), String>,
) -> Result<Value, String> {
    check()?;
    let path = request["file_path"]
        .as_str()
        .ok_or("Missing byte-operation file path")?;
    match request["operation"].as_str().unwrap_or_default() {
        "build_metadata_picture" => {
            let data = fs::read(path).map_err(|e| e.to_string())?;
            let lower_path = path.to_lowercase();
            let png = data.len() >= 8 && data.starts_with(&[0x89, 0x50, 0x4e, 0x47]);
            let mime = if lower_path.ends_with(".png")
                || (!lower_path.ends_with(".jpg") && !lower_path.ends_with(".jpeg") && png)
            {
                "image/png"
            } else {
                "image/jpeg"
            };
            let length = u32::try_from(data.len()).map_err(|_| "Artwork is too large")?;
            let mut picture = Vec::with_capacity(32 + mime.len() + data.len());
            picture.extend_from_slice(&3_u32.to_be_bytes());
            picture.extend_from_slice(&(mime.len() as u32).to_be_bytes());
            picture.extend_from_slice(mime.as_bytes());
            picture.extend_from_slice(&[0; 20]);
            picture.extend_from_slice(&length.to_be_bytes());
            picture.extend_from_slice(&data);
            check()?;
            Ok(json!({"picture": base64::engine::general_purpose::STANDARD.encode(picture)}))
        }
        _ => Err("Unknown byte-operation".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn artwork_block_has_exact_mime_header_and_preserves_large_payloads() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("cover.bin");
        let image = [0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0, 0x42];
        fs::write(&path, image).unwrap();
        let request = json!({"operation":"build_metadata_picture", "file_path": path});
        let result = execute(&request, None, &|| Ok(())).unwrap();
        let block = base64::engine::general_purpose::STANDARD
            .decode(result["picture"].as_str().unwrap())
            .unwrap();
        assert_eq!(&block[..8], &[0, 0, 0, 3, 0, 0, 0, 9]);
        assert_eq!(&block[8..17], b"image/png");
        assert_eq!(&block[17..37], &[0; 20]);
        assert_eq!(&block[37..41], &[0, 0, 0, 9]);
        assert_eq!(&block[41..], &image);
        fs::File::create(&path)
            .unwrap()
            .set_len((4 << 20) + 1)
            .unwrap();
        let result = execute(&request, None, &|| Ok(())).unwrap();
        let block = base64::engine::general_purpose::STANDARD
            .decode(result["picture"].as_str().unwrap())
            .unwrap();
        assert_eq!(&block[8..18], b"image/jpeg");
        assert_eq!(
            u32::from_be_bytes(block[38..42].try_into().unwrap()),
            (4 << 20) + 1
        );
        assert_eq!(block.len() - 42, (4 << 20) + 1);
    }
}
