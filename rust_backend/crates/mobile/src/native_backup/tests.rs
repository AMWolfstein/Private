use super::*;
use serde_json::json;

#[test]
fn accepts_only_the_current_backup_magic() {
    assert!(is_accepted_backup_magic(&json!("sistrum-backup")));
    assert!(!is_accepted_backup_magic(&json!("wrong")));
    assert!(!is_accepted_backup_magic(&json!(null)));
}
