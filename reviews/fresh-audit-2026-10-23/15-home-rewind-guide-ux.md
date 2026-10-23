# Home, Rewind and local-guide UX

## Scope

UI-04 ux-auditor; application baseline d5d5a02 unchanged HEAD5179dfea. Complete lib/screens/ reads: favorite_artists_screen.dart1–152,local_genres_screen.dart1–158,local_guide_pages.dart1–411,listening_rewind_screen.dart1–1840,listening_statistics_screen.dart1–359,home_tab.dart1–259,home_tab_feed.dart1–423,home_tab_widgets.dart1–49 (3,651 lines). Named S1 setup_screen.dart365–472. Historical home_tab_helpers/recent/search_results.dart and home_search_logic.dart do not exist at current source; filename discovery found no matching lib paths. No phantom coverage assigned.

## Findings

### UX-007 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/screens/listening_rewind_screen.dart:525, didChangeDependencies.
- Scenario: accessible navigation enabled but reduced motion disabled; Rewind still advances every six seconds during assistive reading.
- Root cause: autoplay checks disableAnimations only, no persistent pause.
- Impact: longer content disappears before assistive navigation/reading finishes.
- Fix: disable automatic progression with accessibleNavigation, retain manual semantics.
- Evidence: slideDuration six seconds; progress539–540 calls next; semantic624–629 only previous/next; long-press637–640 pauses only until release.
- Cross-refs: single file.
- Guards checked: reduced motion independent of accessible navigation; temporary pointer hold insufficient. Coordinator reread500–555/613–655.

### UX-008 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/screens/listening_rewind_screen.dart:635, build.
- Scenario: RTL Rewind uses RTL PageView/progress order, but tapping physical right side still advances as in LTR.
- Root cause: hardcoded physical left-third previous calculation ignores direction.
- Impact: pointer navigation contradicts mirrored surrounding progression.
- Fix: compute leading coordinate from Directionality before selecting previous/next.
- Evidence:633–635 physical localPosition.dx; PageView inherits direction, progress uses directional start.
- Cross-refs: single file.
- Guards checked: semantic actions logical but do not alter pointer path; no RTL gate. Coordinator reread gesture path.

### UX-009 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/screens/local_guide_pages.dart:349, _TutorialPage.build.
- Scenario: mandatory first-run guide under reduced motion still slides icons, fades headings and animates example expansion.
- Root cause: fixed nonzero durations without disableAnimations checks.
- Impact: decorative movement despite accessibility preference.
- Fix: gate guide entrances and transitions on reduced motion.
- Evidence: icon349–355/heading369–386500ms; feature90–98 slide/fade; search218–220400ms; setup449–453 inserts guide directly.
- Cross-refs: setup_screen.dart365–472.
- Guards checked: viewport/text scaling only; caller does not suppress animations. Coordinator reread guide80–101/210–225/337–391.

## Verification / limits

Graph Home/genres/favorites/Rewind query completed, truncated navigation only. Source findings independently checked by coordinator. No app builds/tests, reduced-motion fixture, RTL or TalkBack device execution. Providers/query integrity and shared primitives outside chunk. No edits or graph changes. Result FINDINGS, three P2.
