# Metadata editing,CUE and logging (D3)

## Scope

code-optimization-auditor, appd5d5a02 unchanged. All144 logic-domain paths hot-marker screened:96matches,48without markers (not proof of cheapness). Focused10 paths: controllers/metadata_editor_controller.dart1–102,player_metadata_controller.dart1–246; services/ffmpeg_metadata.dart1–458,ffmpeg_probe.dart1–36,ffmpeg_replaygain.dart1–179,ffmpeg_cue.dart1–95,ffmpeg_support.dart1–187,replaygain_service.dart1–242,native_log_source.dart1–30; utils/logger.dart1–558. Combined outputs truncated; conclusions from visible hot ranges/targeted rereads,not fresh full-body certification. S1 widgets/local_song_file_actions.dart130–207,services/ffmpeg_service.dart108–128. Graph FFmpeg/metadata/logging query completed truncated.

144path triage:17D1/D2 principal,4root A1 domain,10D3 focused,29playback/analysis-adjacent with profiling deferred,2test/compat,45model/config/utility screen-only,37other retained services screen-only. Deferred category includes application/presentation work and is not blanket engine exclusion. CsvImportService/history transaction compatibility retained.

## Findings

### PERF-008 [P2] [confidence: medium] [NEEDS VERIFICATION]

- Location: lib/services/ffmpeg_cue.dart:38, splitCueToTracks.
- Scenario: long many-track lossless CUE split; later tracks start far into same input.
- Root cause: separate FFmpeg command per track uses output seeking(-ss after -i),potentially repeating prefix decoding/discarding.
- Impact: possible CPU/read amplification; actual decoder behavior/time unmeasured.
- Fix: benchmark accurate input seeking/shared decode,retain exact boundaries/format/tags/publication/failure behavior; do not blindly move -ss.
- Evidence: loop29/command74;arguments38–46 place input before seek;lossless54–56 re-encodes FLAC. Song actions156–178 prepare one local input;service111–125 forwards;execution13–15 invokes FFmpegKit.
- Cross-refs: local_song_file_actions.dart,ffmpeg_service.dart,ffmpeg_support.dart.
- Guards checked: one SAF copy/serial commands reduce other work/concurrency but not shared decoder work. Coordinator independently read complete95line splitter and execution boundary.
- Required measurement:identical60/180minute FLAC/APE/WavPack,10/40/100tracks on Android;elapsed/CPU/input bytes by track position;compare alternatives with decoded sample counts/boundary samples parity. No speedup claimed.

## Verification / limits

No tests/builds/FFmpeg runs/profiling. Logging gates non-error storage/caps buffers/batches native polls;ReplayGain suppresses frame logs;lyrics/picture fallback use workers/native. No additional candidate promoted.113paths outside prior/root/focused scopes screen-only,including some retained app services eligible for later profiling. No security/dead-code findings. Result FINDINGS,one measurement candidate.
