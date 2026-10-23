# Repository dead-code inventory reconciliation (R4)

## Scope

Baseline47039b90, applicationd5d5a02. Inventory from git ls-tree -r --name-only47039b90, counts recorded in inventory.json. All328 lib paths assigned:144 logic +162 UI +20 ARB +2 localization support. Native roots:131 Android +87 crate files +86 third_party =304 paths (initial N1 reviewer count303 superseded by exact inventory).78 crate files are Rust; other9 are manifests/config/fixtures/docs. Vendor430 upstream paths separately identified, including321 Rust/24 C/25 headers/4 C++ files. They are not all application entrypoints or removal candidates merely because target features omit them.

Root vendor-package check: workspace Cargo patches and vendor README inspected. rustix is required directly and transitively through cap-std; libusb vendored C is an Android dependency. Platform branches, exported APIs, licenses,build inputs and host-tool compatibility retained. No claim of exhaustive vendor private-method necessity; stripping unused upstream bodies requires a separate compatibility/patch policy decision.

Tooling configs/agents/skills and docs are independently loaded/manual resources, not app imports. Benchmarks/examples/test runners are roots. Generated localization/UniFFI/plugin registrants are products of declared inputs and are not automatically dead from absent lexical caller. Graph outputs/review reports/historical docs excluded from production caller proof.

## Findings

No additional finding. All15 IDs DEAD-001..015 have entries in reports01–08 and summary index. No removals; recommendations are candidates for separate implementation batches with required analyzer/full tests/native checks.

## Verification / limits

Conservative source/import/export/part/declaration and reference screening completed across application roots. No compiler/AST whole-project proof: shared-name collisions, mutually unreachable islands,feature branches and test-local private symbols may escape. Android private fun census100 found only singleton writer already DEAD-001. Rust non-public census593 found168 automatic test roots and8 Visitor callbacks among176 singleton names. Vendor/agent/docs inventories retained rather than reported dead from imports alone. This completes the requested repository-wide static dead-code pass, not a certification every remaining line executes.

No analyzer/full tests/build/device or security checks executed in this review. No graph update (review-only). Application-source diff from baseline empty; reports only. Each preceding chunk has its own commit and successful immediate push; ledger in README. Result FINDINGS (15 P3), static-screen limitations retained.
