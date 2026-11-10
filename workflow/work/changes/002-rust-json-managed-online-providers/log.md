# Implementation log

- 2026-11-10: Owner selected Rust + JSON and explicitly authorized implementation and push. Existing staged JS providers are inactive; native lyrics remain active. Changes must preserve this working path until replacements pass.

## Close
- Drift: implementation in progress.
- Not verified: Android device and live provider availability.
- Lessons: none.

- 2026-11-10: Native provider baseline: cargo +1.99.1 test -p mornye-providers --locked, 75 passed / 4 ignored. Targeted new configuration tests, Backend restart/rejection tests and operator CLI test passed. Rust source implementations listed in extensions/lyrics/origin-lock.json remain byte-identical.
- 2026-11-10: Owner clarified upload destination is their own repository, not mornyeapp/Mornye-Extension. GitHub API reports no upstream write permission; upstream was not modified. AMWolfstein/Private remains the code/configuration destination. No app token is embedded.
- 2026-11-10: First batch is bounded origin settings only, not full artwork migration. Production signer and app-readable distribution are not provisioned. No automatic downloader or cross-language installer is claimed. T004/T005 remain open; record must not be marked done/ship on this evidence.

- 2026-11-10: Final tested native batch: workspace Rust tests 568 passed / 0 failed / 8 ignored with cargo +1.99.1 --locked; Clippy --all-targets -D warnings passed. Existing JS source/reference tests 101 passed; upstream watcher tests 17 passed. Android :app:testDebugUnitTest passed (176 passed / 2 skipped / 0 failed); flutter build apk --debug passed. Physical device not tested.
- 2026-11-10: work.py check auto remains INCOMPLETE because its unqualified Android testDebugUnitTest also runs flutter_local_notifications tests: initial cache lock denied at /home/agent; after writable home, Robolectric 4.14.1 cannot instrument Java major 69. Temporary JDK21 plugin test-launcher attempts instead encounter compiled major69 vs supported65. Five bounded attempts made; no workflow selectors, assertions or application dependency versions changed to hide failures. Temporary Gradle/JVM configuration lived outside the repo. No full unmodified-branch baseline was run for root plugin tests in this task.
- 2026-11-10: Both independent code reviewers returned CLEAN for the final typed native configuration API. Full migration remains phase build, T004/T005/T006 open; production trust keys, automatic downloading/caller integration, richer setting fields and native artwork ports remain unfinished. This is a validated first batch, not a finished Rust+JSON migration or release.

- 2026-11-10: Validated native batch committed as 0363d733aec85ea12e251ba1b4b18e8b219b149f. Documentation records are separate. Full migration remains unfinished; no production signer or automatic downloader is enabled.
