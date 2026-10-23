# Settings UX

## Scope

UI-03 ux-auditor, source d5d5a02 unchanged at5179dfea. Complete lib/screens/settings/ reads: about_page.dart1–342,appearance_settings_page.dart1–631,cache_management_page.dart1–636,library_settings_page.dart1–1372,log_screen.dart1–731,lyrics_settings_page.dart1–50,metadata_separator_settings_page.dart1–198,playback_settings_page.dart1–398,profile_settings_page.dart1–185,settings_search_catalog.dart1–396,settings_tab.dart1–423 (5,362 lines). Backup excluded as previously covered. Named S1 lib/widgets/app_bottom_sheet.dart141–284. Graph settings query completed, truncated navigation only. No edits; prompt-only restrictions.

## Findings

### UX-005 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/screens/settings/library_settings_page.dart:311, _showAutoScanPicker.
- Scenario: Local Library → Auto scan in short split-screen window or large text overflows bottom sheet; lower options inaccessible.
- Root cause: non-scrollable Column under default height-restricted sheet.
- Impact: cannot reliably choose all four frequencies in constrained viewports.
- Fix: constrained scrolling body and suitable sheet sizing.
- Evidence: action558–562; picker304–385 fixed heading/description/four options; option1365–1369 uses AppSheetOption vertical padding247–250; wrapper175 defaults isScrollControlled false and197–200 adds no scrolling.
- Cross-refs: lib/widgets/app_bottom_sheet.dart.
- Guards checked: SafeArea/mainAxisSize.min do not shrink nonflex content. Coordinator reread picker304–385, wrapper170–202, option242–256.

### UX-006 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/screens/settings/cache_management_page.dart:620, totalKnownDiskCacheBytes.
- Scenario: nonempty audio analysis cache is displayed individually but omitted from Estimated total.
- Root cause: total omits audioAnalysisStats.totalSizeBytes.
- Impact: understated cache storage estimate.
- Fix: include separate analysis-cache bytes.
- Evidence:82–90 scans application-support/audio_analysis_cache;100 stores stats;395–396 reads incomplete total;620–625 sum omits it.
- Cross-refs: single file.
- Guards checked: temporary/app-cache equality avoids double counting but separate support directory remains omitted; Clear all separately includes analysis. Coordinator reread70–104 and610–632.

## Verification / limits

Static source review only; no Flutter analysis/tests, builds, TalkBack, device or layout reproduction. Shared settings widgets/headers/sliders and nested playback settings outside chunk. Retained Logs/developer/tag-separator destinations inspected; no persistence or audio-engine claim. Result FINDINGS: two P2.
