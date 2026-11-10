# Rust JSON managed online providers

Status: Accepted
Input: "غير كله و ارفع علي github" after choosing Rust execution and updateable JSON configuration.
Binding decisions: retain Jellyfin exclusion; retain native lyrics implementations; no playback/UI changes.

## User scenarios

### Story 1: Keep lyrics working (P1)
Acceptance: Given existing built-in provider preferences, when lyrics are requested, then native implementations and existing timing/translation/cancellation behavior remain active.
### Story 2: Update provider settings independently (P1)
Acceptance: Given a compatible authenticated configuration, when it is installed, then requests after backend restart use its settings; invalid, unsupported or incomplete configurations leave the previous configuration usable.
### Story 3: Native artwork (P2)
Acceptance: Given a supported provider identity and required credentials, when artist or album artwork is requested, then Rust returns identity, still/motion URLs and editorial information without executing downloaded code.

## Requirements
- FR-001: Preserve all 14 native lyric provider implementations, provider IDs and preferences.
- FR-002: Move changeable service endpoints into bounded versioned JSON under extensions/; downloaded JSON cannot grant arbitrary executable behavior or network permissions.
- FR-003: Validate complete configurations before publication, retain bundled defaults, and preserve old data after failed writes.
- FR-004: Support selected artwork capabilities natively; preserve authentication requirements and exclude Jellyfin.
- FR-005: Preserve attribution and upstream references; prepare review PRs, never automatically merge upstream changes.
- FR-006: Document exact supported update fields and remaining changes requiring an APK; never claim activation or parity without tests.

## Edge cases
Offline startup, invalid/oversized JSON, schema/runtime mismatch, cancellation, failed persistence, missing credentials, and unavailable services must not erase existing metadata or usable configuration. UI and local library identities remain unchanged.

## Success criteria
- SC-001: Existing native lyrics tests pass against bundled settings.
- SC-002: Malformed configurations fail before any publication; successful installations survive restart.
- SC-003: No downloaded JS is required for native configured services.

## Assumptions
The owner authorized implementation and push on extension-system. JSON is bounded data, not a general scripting language. New trust keys or credentials must never be invented as production secrets.
