//! Matching compatibility uses Go's simple case mapping and UTF-8 byte distance.

/// Unlike String::to_lowercase, Go's unicode.ToLower maps one rune to one rune.
pub fn lowercase(value: &str) -> String {
    value
        .chars()
        .map(|ch| match ch {
            // Go 1.26 uses Unicode 15.0; these lowercase mappings were added
            // in Unicode 16/17, used by the pinned Rust toolchain.
            '\u{1c89}'
            | '\u{a7cb}'
            | '\u{a7cc}'
            | '\u{a7ce}'
            | '\u{a7d2}'
            | '\u{a7d4}'
            | '\u{a7da}'
            | '\u{a7dc}'
            | '\u{10d50}'..='\u{10d65}'
            | '\u{16ea0}'..='\u{16eb8}' => ch,
            _ => ch.to_lowercase().next().expect("lowercase character"),
        })
        .collect()
}

/// Go's Unicode 15 simple uppercase does not expand characters such as ß.
pub fn uppercase(value: &str) -> String {
    value
        .chars()
        .map(|ch| match ch {
            '\u{019b}'
            | '\u{0264}'
            | '\u{1c8a}'
            | '\u{a7cd}'
            | '\u{a7cf}'
            | '\u{a7d3}'
            | '\u{a7d5}'
            | '\u{a7db}'
            | '\u{10d70}'..='\u{10d85}'
            | '\u{16ebb}'..='\u{16ed3}' => ch,
            // Full uppercase expands these Greek letters; simple uppercase uses
            // the corresponding single precomposed capital instead.
            '\u{1f80}'..='\u{1f87}' | '\u{1f90}'..='\u{1f97}' | '\u{1fa0}'..='\u{1fa7}' => {
                char::from_u32(ch as u32 + 8).expect("Greek capital")
            }
            '\u{1fb3}' => '\u{1fbc}',
            '\u{1fc3}' => '\u{1fcc}',
            '\u{1ff3}' => '\u{1ffc}',
            _ => {
                let mut mapped = ch.to_uppercase();
                let first = mapped.next().expect("uppercase character");
                if mapped.next().is_none() { first } else { ch }
            }
        })
        .collect()
}
