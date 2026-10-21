/// Go replaces every malformed UTF-8 byte separately when serializing JSON.
/// Rust's lossy decoder can combine a truncated sequence into one replacement.
pub(crate) fn utf8(mut bytes: &[u8]) -> String {
    let mut text = String::new();
    while !bytes.is_empty() {
        match std::str::from_utf8(bytes) {
            Ok(valid) => {
                text.push_str(valid);
                break;
            }
            Err(error) => {
                let valid = error.valid_up_to();
                text.push_str(std::str::from_utf8(&bytes[..valid]).expect("valid UTF-8 prefix"));
                text.push(char::REPLACEMENT_CHARACTER);
                bytes = &bytes[valid + 1..];
            }
        }
    }
    text
}
