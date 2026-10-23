# Shared list,selection,header and animation surfaces (U3)

## Scope

code-optimization-auditor, source d5d5a02 unchanged. All142 remaining UI paths after U1a/b/U2 filename/hot-marker screened. Ten principal whole reads4,133lines under lib/widgets/: library_section_list.dart1–118,library_fast_scroller.dart1–432,selection_bottom_bar.dart1–603,playlist_picker_sheet.dart1–577,mini_player.dart1–242,animation_utils.dart1–547,album_detail_header.dart1–961,mornye_floating_header.dart1–359,collection_scaffold.dart1–120,overflow_marquee.dart1–174. Graph shared UI query completed truncated, navigation only. Root cache bodies not duplicated.

## Findings

No new independent finding. Additional PERF-001 evidence: library_section_list52–73 invalidates grouping by incoming items identity; newly combined QueueTab lists rerun _group and labelOf for all loaded rows. Include grouping/date-label time in existing300/3000/15000row allocation/frame profile; not a separate ID or measured regression.

## Verification / limits

Checked lazy playlist rows,selection-overlay ownership,grouping cache,scroller child retention,mini-player selective subscriptions,marquee lifecycle/cycle bounds,shimmer gates and cached header contrast/theme decisions. No benchmarks/profiles/builds/tests/devices or changes.142path screen not full-body certification; remaining shared/player hot candidates assigned U4. Low-frequency settings/editing/setup/statistics/support files remain screen-only. Result PASS for bounded scope; PERF-001 evidence extended.
