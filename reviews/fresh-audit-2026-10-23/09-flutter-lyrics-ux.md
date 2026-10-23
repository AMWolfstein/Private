# Flutter lifecycle and lyrics UX audit

## Scope

Application source d5d5a02; reviewers inspected HEAD5dcf7241, unchanged application source at coordinator checkpoint d3a25128. Roles: flutter-dart-auditor and ux-auditor. Fresh independent review; engine excluded; no application edits. Read-only enforcement prompt-only.

Principal Flutter chunk, complete reads: lib/app.dart1–258; lib/routes/now_playing_route.dart1–270; lib/screens/main_shell.dart1–819,mornye_library_screen.dart1–586,local_artist_screen.dart1–752,local_album_screen.dart1–662,library_tracks_folder_screen.dart1–923,setup_screen.dart1–892.

Named supplemental UI-01-S1: lib/utils/adaptive_layout.dart, lib/screens/selection_mode_mixin.dart, lib/widgets/collection_scaffold.dart complete; lib/providers/library_collections_provider.dart1–65,180–260,330–390,470–610.

Principal UX chunk, complete reads: lib/screens/now_playing_screen.dart1–1000,queue_tab.dart1–1247,lyrics_share_screen.dart1–863; lib/widgets/player_lyrics.dart1–2249. QueueTab is the Library tab; its eight part files remain a separate chunk, not implicit coverage of the player's Up Next list.

## Findings

### UI-001 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/screens/setup_screen.dart:578, _buildLanguageStep.
- Scenario: a short split-screen viewport (e.g.800×280 logical pixels), or sufficiently large text, makes the language header overflow and leaves little/no space for language choices.
- Root cause: fixed non-scrollable heading above an Expanded list; only the list scrolls.
- Impact: language choices become inaccessible in constrained windows.
- Fix: scroll the heading with the choices or collapse it based on available height.
- Evidence: setup384–443 reserves80dp above PageView;580–622 fixes header padding/icon/gaps;623–631 assigns only remaining height to list. At280dp overall height the fixed elements consume most of the200dp page height even before headings.
- Cross-refs: adaptive_layout26 keeps small windows at scale1; app installs scaler.
- Guards checked: LayoutBuilder does not use available height; horizontal inset does not solve height. Portrait manifest preference limits ordinary rotation but does not guarantee adequate split-screen height or text-scaled layout. Coordinator reread setup375–450/570–640 and adaptive layout.

### UI-002 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/screens/library_tracks_folder_screen.dart:177, _removeSelected.
- Scenario: removal waits behind collection persistence; Back exits selection, another Back leaves screen; completed mutation calls setState on disposed State.
- Root cause: exitSelectionMode precedes the post-await mounted guard.
- Impact: uncaught asynchronous lifecycle error after successful removal.
- Fix: move mounted guard before exitSelectionMode.
- Evidence: awaits165/169–172; call177; guard179. SelectionModeMixin20–25 unconditionally calls setState. CollectionScaffold90–96 permits exit-selection then pop. Provider32–44 queues writes;351/570 await DB.
- Cross-refs: lib/screens/selection_mode_mixin.dart; lib/widgets/collection_scaffold.dart; lib/providers/library_collections_provider.dart.
- Guards checked: provider mounted checks protect provider only; page check comes too late. Coordinator independently reread complete method, mixin and PopScope plus provider mutation/removal ranges.

### UX-001 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/widgets/player_lyrics.dart:2198, _TimedLyricSweepPainter.paint.
- Scenario: word-timed Arabic/Hebrew lyrics partially highlight words left-to-right instead of their run direction.
- Root cause: segment geometry discards TextBox.direction; partial reveal always starts from box.left.
- Impact: backwards highlight inside RTL words, including mixed-direction runs.
- Fix: preserve run direction and use directional clipping/feather/glow geometry.
- Evidence: active timed lines1010–1020; geometry1988–1998 maps boxes to Rect and sorts left-first; glow2141–2147 and partial reveal2198–2217 clip from left.
- Cross-refs: single file.
- Guards checked: TextPainter ambient direction1954–1962/2018–2023 shapes text but does not reverse separate painter clips; reduced motion leaves sweep direction unchanged. Coordinator reread geometry1935–2005 and painter2180–2230.

### UX-002 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/widgets/player_lyrics.dart:1062, _SyncedLyricsViewState._buildLyrics.
- Scenario: reduced motion enabled; active word-timed line changes, but plain/timed rendering still crossfades for320/260ms.
- Root cause: AnimatedSwitcher durations ignore reduced-motion decision already used by neighboring transitions.
- Impact: recurring decorative transitions despite disabled animations.
- Fix: gate both switcher durations on existing reduced-motion decision.
- Evidence: timed depends on isActive1010–1012; ValueKey(timed)1068 switches child; fixed durations1062–1070; reduced-motion duration calculated797.
- Cross-refs: single file.
- Guards checked: adjacent effects use motion; separately gated word lift does not prevent switcher animation. Coordinator reread980–1080 and located disableAnimations guards.

## Verification

Both reviewers ran graphify queries for their scoped symbols (broad queries truncated; navigation only), and explain SetupScreen/_TimedLyricSweepPainter. Source guards independently reread by coordinator as recorded above. Python helper suite previously PASS28 at d3a25128 predecessor; unrelated to these UI triggers. Flutter widget/semantics tests, TalkBack, split-screen/large-text reproduction and physical devices NOT RUN. No runtime reproduction claim.

## Limitations / result

FINDINGS: four P2. Principal chunks complete within named boundaries; broader UI coverage incomplete. Player layout/transport/gestures/shared primitives and QueueTab parts remain separate chunks. No fixes or APKs.
