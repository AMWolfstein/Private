# Localization and asset dead-code review (R1)

## Scope

Baseline47039b90, application d5d5a02 unchanged. Role dead-code-hunter. Tracked asset/root-art inventory and all20 ARB files candidate-screened; pubspec.yaml,l10n.yaml,lib/l10n/{l10n,supported_locales}.dart,README.md read. Reference corpus: tracked Dart/Kotlin/Java/Rust/C++/Python/shell/JS/YAML/Gradle/XML/JSON/Markdown outside review/graph outputs and vendor source; generated untracked localization output excluded. Graph localization/assets/scripts query completed, truncated navigation only.

All893 English template localization keys have token references in the source/test/config corpus. Conservative token screen can retain false positives; no unused-key finding and no claim of semantic execution of every translation. Language lists are referenced by app253 and language_choices31. License assets registered by pubspec/main, fonts by pubspec/tests, shaders by code/pubspec and images/logo by live screens. Cupertino font assets used through Flutter CupertinoIcons and explicit test FontLoader registrations despite no package import; retained.

## Findings

### DEAD-003 [P3] [confidence: high] [VALIDATED — static]

- Location: assets/readme/2.jpg (also3.jpg,4.jpg,banner-readme-dark.png,banner-readme-light.png), root logo.svg.
- Scenario: current trimmed README, app, tests and build configs never reference these retained old documentation images/vector.
- Root cause: documentation trimming left unreferenced media.
- Impact: approximately1.13MB tracked source assets without a consumer; no APK saving claimed because these paths are not bundled.
- Fix: remove the six unused files if no external archival requirement; low build risk. Sizes:830449+106344+124573+34206+34628+488 =1,130,688 bytes.
- Evidence: full tracked source/config/doc filename/path searches yield no consumer; pubspec bundles assets/images, fonts/licenses/shaders, not assets/readme or logo.svg. README contains no image links. Migration tracker1075 explicitly already identified assets/readme as cleanup when README trimmed.
- Cross-refs: pubspec.yaml,README.md,LOCAL_OFFLINE_MIGRATION_PLAN.md1075.
- Guards checked: assets/readme/1.jpg is a playback-artwork/session test fixture and MUST remain; launcher PNGs are explicit build inputs; licenses not unused. No dynamic readme path construction found. External repositories linking these media cannot be excluded by local reference analysis.

## Verification / limits

Static token/path/reference analysis only; no generation/build/test execution. Existing translation coverage does not prove every localized value used at runtime. No deletion or security checks. Result FINDINGS.
