# Audio engine migration: Media3/ExoPlayer, no FFmpeg

Status: plan only. Nothing in this file has been implemented or tested.

**Sources read for this plan:**

| Repo | Branch | Commit | Date |
|---|---|---|---|
| This repo (`AMWolfstein/Private`) | `ccr-2fb644cd-nmesyt` | `05cbce5` | 2026-10-24 |
| Reference (`AMWolfstein/Sistrum`) | `feature/media3-migration` | `88e5987` | 2026-10-16 |

**Goal:**
1. Replace the current playback engine with Android Media3 (ExoPlayer) and Kotlin decoders taken from Sistrum.
   Today's engine is audioplayers/MediaPlayer, plus the Oboe/libFLAC/WavPack C++ library and the USB decks.
2. Remove FFmpeg (`ffmpeg_kit_flutter_new_audio`) completely.
3. Keep every feature, or record an owner decision for each one that changes.

---

## 1. Decisions the owner must make first

Each item blocks part of the work. The recommendation is given, but none of these is decided.

| # | Decision | Why it matters | Recommendation |
|---|---|---|---|
| D1 | **Licence.** This app is **MIT**. Every Sistrum file is **GPL-3.0** (`codecs` 146, `metadata` 48, `dsp` 9 and `analysis` 15 files, `player/` and `analysis/` app code). Some files are ports of other GPL projects: Rhythm, Choir, aubio and Airmedy (`PcmAnalyzer.kt` is GPL-3.0-only). | Shipping Sistrum code makes the whole APK a GPL-3.0 work. You may relicense only code you wrote yourself. The Rhythm, Choir, aubio and Airmedy ports stay GPL. | Either relicense this app to GPL-3.0-or-later (simplest, and allowed for MIT code), or copy only files whose every line you wrote from MIT sources such as WaxFlow and relicense those. Decide before the first copy. This is not legal advice. |
| D2 | **Minimum SDK.** Sistrum requires API 31. This app uses `flutter.minSdkVersion` = 24. | Sistrum code assumes API 31 or newer. It uses `DynamicsProcessing` (API 28) and the newer `AudioTrack` and `MediaCodec` encodings without version checks. | Raise minSdk to 31, or audit every ported file for API levels with `lint` `NewApi` and add version checks. |
| D3 | **Direct USB (libusb in Rust).** Media3 cannot do this. The Java USB API (`UsbRequest`) has no isochronous transfers. | The libusb direct USB driver must stay native, so the NDK stays. | Keep the Rust USB worker as a separate output path. Feed it from the Kotlin decoders (section 4.3). |
| D4 | **AAudio exact-rate output (`HiResPlayback.kt`, Oboe).** AAudio has no Java API. | Removing it removes the last C++ code in `cpp/`. | Drop it. On Android 14 and newer, the bit-perfect mixer route (`setPreferredMixerAttributes`, already in `UsbBitPerfectPlugin.kt`) covers USB DACs. Android below 14 falls back to normal mixed output. |
| D5 | **CUE "Split into Tracks".** FFmpeg cuts the file today: it stream-copies, or re-encodes to FLAC. Android has no FLAC muxer, and Sistrum has no splitter. | Media3 can **play** CUE tracks directly with `MediaItem.ClippingConfiguration`. Today CUE tracks **must** be split before they play (`cueVirtualTrackRequiresSplitMessage`, `lib/utils/file_access.dart:26`). | Play CUE tracks directly first, as in Sistrum's planned task T037. Then decide whether Split stays (section 5.6) or is removed under `AGENTS.md`'s feature-removal workflow. |
| D6 | **The bridge between Flutter and Media3** (section 6). | This decides how much Dart playback code changes. | Phase 1: keep `audio_service` for the session, notification and Android Auto. Replace only `audioplayers` and the native decks with one Kotlin engine plugin. A Media3 `MediaSessionService` comes later as its own step, as Sistrum also decided (ADR-006). |
| D7 | **Formats with no decoder after FFmpeg.** Sistrum lists `tta` with no provider (`DecoderRegistry.kt`). TAK and anything else FFmpeg plays are also uncovered. | Removing FFmpeg does not change playback: playback never used FFmpeg here. But analysis, ReplayGain scan, haptics and AutoMix lose FFmpeg's decoders. | Accept those as unsupported. Show them in a skipped or failed list (Sistrum FR-064a, the decode-failure log). |

---

## 2. What the audio engine is today

| Layer | Code | Notes |
|---|---|---|
| Dart player service | `lib/services/music_player_service.dart` (2263 lines), `music_player_runtime.dart`, `music_player_automix.dart`, `music_player_autoplay.dart`, `playback_*.dart` | Owns the queue, session restore, history, normalization, sleep timer, AutoMix and headphone handling. |
| Dart deck | `lib/services/music_playback_deck.dart` | Wraps one `audioplayers` `AudioPlayer` plus the native USB/hi-res route (`com.zarz.spotiflac/usb_pcm`). There are two decks for AutoMix. |
| Ordinary engine | `audioplayers` 6.8.1 with a vendored `third_party/audioplayers_android` | Android **MediaPlayer**. Local patches: `/proc/self/fd` SAF leases, output-error handling and a `DynamicsProcessing` EQ (`PlaybackEqualizer.kt`). **No gapless playback.** |
| Session | vendored `third_party/audio_service` 0.18.19, `audio_session` 0.2.4 | Framework MediaSession, notification, Android Auto browse, focus and noisy events. |
| Hi-res / bit-perfect | `UsbBitPerfectPlugin.kt` (AudioTrack and Android 14 preferred mixer), `HiResPlayback.kt` (Oboe AAudio), `UsbDirectPlayback.kt` and Rust `mobile/src/usb_audio/*` (libusb), `UsbPcmSource.kt`, `BitPerfectPcm.kt`, `DsdFile.kt`, `DsdSource.kt` | The USB route decodes with MediaExtractor/MediaCodec, **libFLAC** (`flac_pcm_source.cpp`) and **WavPack** (C). DSD goes through DoP or native USB only. |
| C++ library | `android/app/src/main/cpp/` (CMake, `libspotiflac_audio.so`): Oboe 1.11, libFLAC 1.5.0, WavPack 5.9.0 | Exports 18 JNI functions (`native_audio.map`). |
| Rust | `rust_backend` (UniFFI and JNA, `libspotiflac_mobile.so`) | Tags (read and write), CUE parsing, scan, covers, palette, backup, collections DB (`rusqlite` bundled), USB driver, and analysis maths for AutoMix and spectral cutoff on PCM that FFmpeg decoded. |
| FFmpeg | `ffmpeg_kit_flutter_new_audio` 2.5.7, wrappers `lib/services/ffmpeg_*.dart` (1190 lines) | Decodes for analysis, measures loudness, renders effects, splits CUE and resizes covers. It is a tag-writing **fallback only**. It is never used for playback. |

---

## 3. Every feature that depends on the audio engine and its replacement

Sistrum paths are relative to `androidApp/src/main/kotlin/com/amwolfstein/sistrum/` unless they start with a module name (`codecs/`, `dsp/`, `analysis/`, `metadata/`).

### 3.1 Core playback

| Feature (today) | Current code | Replacement | Sistrum source | Gap / note |
|---|---|---|---|---|
| Play, pause, seek, stop, position and duration streams | `music_playback_deck.dart`, `audioplayers` | Media3 `ExoPlayer` | `player/media3/Media3Engine.kt`, `Media3PlayerFactory.kt`, `player/engine/PlayerEngine.kt`, `EngineEvent.kt` | Sistrum's engine sits under a Kotlin `PlaybackCoordinator`. Here the coordinator is Dart, so keep the `PlayerEngine` interface and expose it on a channel (section 6). |
| Gapless album playback | **missing** (MediaPlayer) | ExoPlayer two-item playlist | `Media3Engine.kt`, `PlatformMp3Trim.kt`, `PlatformTrimAudioRenderer.kt` (MP3 encoder delay and padding) | **New feature.** It comes for free with Media3. |
| SAF `content://` playback with leases and the cache copy | `content_uri_playback_cache.dart`, `safOpenPlaybackLease`, patched `UrlSource` | Media3 `ContentDataSource` and `DefaultDataSource` read `content://` directly | none needed | The 256 MB copy cache (`ContentUriPlaybackCache`) and the `/proc/self/fd` patch become unnecessary for playback. Keep them only until every caller has moved. |
| Playback errors keep the song for retry; same-ID duration and artwork updates reach open players (`AGENTS.md` rule) | `music_player_service.dart` `_reportPlaybackError` | Same Dart logic, fed by `EngineEvent.Error` | `EngineEvent.kt`, `DecodeFailureLog.kt` | It is an engine-agnostic contract, so keep its tests. |
| Speed | `deck.setPlaybackRate` | `ExoPlayer.setPlaybackParameters(PlaybackParameters(speed, pitch))` (Sonic) | — | Media3 can change pitch separately from speed (used by AutoMix, 3.4). |
| Volume, focus ducking, noisy and headphone events | `audio_session`, `_configureAudioSession`, `_pauseForFocusLoss`, `_startHeadphoneMonitoring` | Keep `audio_session`. Media3 runs with `handleAudioFocus = false`, as Sistrum does. | `player/media3/FocusVolumeRamp.kt` | Sistrum ramps the duck to 0.2. Optional. |
| Sleep timer, repeat, shuffle, queue, session restore, autoplay | Dart | unchanged | — | Engine-agnostic. |
| Notification, lock screen, Android Auto, media buttons | `audio_service` | Phase 1: unchanged. Phase 2: Media3 `MediaSessionService` or `MediaLibraryService` (decision D6). | ADR-006 (Sistrum also kept the framework session in 001) | — |
| Home-screen widget | `player_widget_service.dart`, `PlayerWidgetProvider.kt` | unchanged (driven by Dart state) | — | — |

### 3.2 Sound processing (the EQ and the chain)

| Feature | Current code | Replacement | Sistrum source | Gap / note |
|---|---|---|---|---|
| EQ (5, 10, 15 or 31 bands, preamp) | `PlaybackEqualizer.kt` (DynamicsProcessing pre-EQ on MediaPlayer's session), `playback_equalizer.dart`, `equalizer_settings.dart` | In-app `AudioProcessor` biquads in a float chain | `player/dsp/BiquadEqualizer.kt`, `EqualizerProcessor.kt`, `PreampProcessor.kt`, `player/media3/FloatChainAudioSink.kt` | Sistrum's EQ has **10 fixed bands**, Q = 1. Our settings allow 5, 10, 15 or 31 bands with our own frequencies. Generalise `BiquadEqualizer` to N bands, or keep the DynamicsProcessing EQ on the Media3 session id (it works unchanged, `audioSessionId` comes from ExoPlayer). Keep the presets file format (`equalizer_preset_io.dart`). |
| Bass and treble | `equalizer_settings.dart` (folded into the band gains) | same Dart maths | — | — |
| Balance | DynamicsProcessing input gain per channel | A channel-gain processor, or `StereoWidthProcessor.kt` with a balance term | `player/dsp/StereoWidthProcessor.kt` | Small new code. |
| Compressor | DynamicsProcessing MBC band | `dsp/gain/Compressor.kt` (Sistrum's "Night mode" stage) | `dsp/.../gain/Compressor.kt`, `FloatChainAudioSink.kt` | Map our threshold, ratio, attack and release onto it. |
| Limiter, auto headroom | DynamicsProcessing limiter (-0.5 dB) | A limiter-only `DynamicsProcessing` on the **shared** session (it sees both crossfade players), or the in-app `dsp/gain/Limiter.kt` | `player/media3/LimiterSession.kt`, `LimiterStatus.kt`, ADR-004 | Sistrum found that control loss can mute output and added a hedge (ADR-004). Port that too. |
| Stereo width | none today | `StereoWidthProcessor.kt` | — | Optional new feature. |

### 3.3 Loudness normalization (ReplayGain at playback)

| Feature | Current code | Replacement | Sistrum source | Gap / note |
|---|---|---|---|---|
| ReplayGain tag normalization: track or album mode, pre-amp | `playback_normalization.dart`, `_normalizationVolumeFor` → `setVolume` | Pass gain in dB to a per-player `GainProcessor` | `player/dsp/GainProcessor.kt`, `player/normalization/ItemGainMath.kt`, `GainResolver.kt`, `TagGainSource.kt` | Today's volume cannot exceed 1.0, so **positive gain is lost**. The processor plus the limiter fixes that. Keep reading tags through Rust, which already reads `replaygain_*`, `R128_*` and Sound Check. Port only the gain maths and its tests: R128 +5 dB, `REPLAYGAIN_REFERENCE_LOUDNESS`, clip cap from peaks. |
| Opus header output gain | MediaPlayer applies it | The platform decoder applies it once (Sistrum S5, measured on CPH2307) | ADR-005 | Do not add it again. |
| Measured loudness (when no tags) | none | WorkManager job: offline decode, BS.1770 meter, store, album planner | `analysis/LoudnessAnalysisWorker.kt`, `LoudnessStore.kt`, `AlbumLoudnessPlanner.kt`, `TrackAnalyzer.kt`, `analysis/.../Loudness.kt` | Optional new feature. Needs a place to store results: our library DB or the Rust collections DB. |

### 3.4 AutoMix (crossfade and beat-matched mixing)

| Feature | Current code | Replacement | Sistrum source | Gap / note |
|---|---|---|---|---|
| Two players and timing | `music_player_automix.dart` (2 decks, 40 ms volume timer) | Two ExoPlayers on **one shared audio session**, with a per-sample equal-power fade in `GainProcessor` | `player/media3/TransitionController.kt`, ADR-003, `MixerBlockEstimator.kt`, `MixerBlockStore.kt` | The 40 ms Dart volume steps become per-sample curves. Keep the Dart *decision* (when, how long, beat-matched or not) and send it to native. |
| Beat-grid analysis (head and tail windows) | `automix_analyzer.dart`: FFmpeg decodes to mono s16le, then Rust `automix` analyses it | `OfflineDecoder` (ExoPlayer and `CaptureAudioSink`) → downmix and resample (`dsp/resample/Resampler.kt`, `dsp/mix/Matrix.kt`) → the same Rust `automix` job, or Sistrum's `analysis/.../Aubio.kt` (tempo, onsets) | `analysis/OfflineDecoder.kt`, `CaptureAudioSink.kt`, `PcmDecoder.kt` | Section 5.1. |
| Mix effects: speed, pitch, low-pass, echo, wet/dry ramp, limiter | `automix_effect_renderer.dart`: FFmpeg renders a WAV tail with `asetrate`, `atempo`, `lowpass`, `aecho`, `amix` and `alimiter`, which deck B then plays | **Live** on the incoming player: `PlaybackParameters` (speed and pitch), a low-pass biquad (from `BiquadEqualizer.kt`), a new small echo or delay `AudioProcessor`, the wet/dry curve in `GainProcessor`, and the limiter | `player/dsp/*`, `dsp/gain/Limiter.kt` | No temporary WAV and no 30 s FFmpeg job. The echo processor is new code, about 60 lines. |
| Silence-aware crossfade start | none | silence profiles from analysis | `dsp/silence/Detector.kt`, `TransitionController.kt` (Sistrum 002 M2) | Optional. |

### 3.5 Hi-res, bit-perfect, USB and DSD

| Feature | Current code | Replacement | Sistrum source | Gap / note |
|---|---|---|---|---|
| Android 14+ bit-perfect mixer to USB DAC (`usbBitPerfect`, `usbAllowFixedVolume`, `dapExclusive`) | `UsbBitPerfectPlugin.kt` (own AudioTrack) | Keep the plugin. Change its **source** to the Kotlin decoders. | `player/decoders/kotlin/CodecStream.kt`, `codecs/*` | Media3 bypasses no processors on this path, so keep it separate from the Media3 chain. ReplayGain, AutoMix and EQ stay bypassed here, as today. |
| Exact FLAC PCM (`AGENTS.md`: "never trust vendor raw FLAC decoding") | `flac_pcm_source.cpp` (libFLAC) | A Kotlin FLAC decoder, or Rust `claxon` (already a `spotiflac-core` dependency) | **Sistrum has no Kotlin FLAC decoder.** It uses the platform decoder. WaxFlow has `codec/flac` that could be ported. | **Gap.** Choose claxon in Rust (no JNI hop for the USB worker) or port WaxFlow's FLAC. The platform decoder's float output is lossless only up to 24-bit. |
| WavPack PCM for the USB path | WavPack C (`openWavPack`…) | `codecs/.../codec/wavpack/*`, `container/wv/*` | `KotlinWavPackProvider.kt` | Oracle-tested against WaxFlow in Sistrum. Sistrum's notes say WaxFlow refuses hybrid, float and >2-channel WavPack, so check the Kotlin port's own refusals. |
| WavPack DSD | `WavPackDsdSource` (C) | `codecs/.../container/wv/WavPackDsd.kt`, `codec/wavpack/Dsd.kt` | — | — |
| DSF and DFF over DoP or native USB (`usbDsdOverPcm`) | `DsdFile.kt`, `DsdSource.kt`, Rust USB | Keep `DsdFile.kt` or use `codecs/.../container/dsf`, `container/dff`, plus `codec/dsd/DopPacker.kt` | `KotlinDsdProvider.kt` | — |
| DSD on ordinary output | **not supported** (`dsd_unsupported`) | DSD→PCM decimation | `codecs/.../codec/dsd/DsdDecimationPipeline.kt`, `DsdRateConverter.kt` | **New feature:** DSD plays on any output. |
| AAudio exact-rate output | `HiResPlayback.kt` and Oboe | none (decision D4) | — | — |
| Direct USB driver (libusb, isochronous) | Rust `usb_audio/*`, `UsbDirectPlayback.kt` | **Stays native** (decision D3) | — | Feed its PCM from the Kotlin decoders or claxon instead of libFLAC and WavPack C. |
| Output picker | `audio_output` channel (`MediaRouter2`) | unchanged | — | — |

### 3.6 Formats (playback)

Today, ordinary playback uses MediaPlayer, so it plays only what the phone's codecs play. APE, WavPack, Musepack, WMA and DSD do not play on ordinary output. WavPack and DSD play only on the native USB/hi-res route.

After the migration, the Media3 engine plus Sistrum's `DecoderRegistry` play these:

| Formats | Decoder | Sistrum code |
|---|---|---|
| MP3, AAC/M4A, FLAC, Opus, Vorbis, WAV, AMR, WebM/MKA, AC-3/E-AC-3 when the phone has them | Platform | `PlatformProvider.kt` |
| ALAC | Kotlin, used when the phone has no ALAC decoder (CPH2307 has none) | `KotlinAlacProvider.kt` |
| AIFF and AIFF-C | Kotlin | `decoders/aiff/KotlinAiffProvider.kt` |
| APE | Kotlin | `KotlinApeProvider.kt` |
| WavPack | Kotlin | `KotlinWavPackProvider.kt` |
| Musepack | Kotlin | `KotlinMusepackProvider.kt` |
| WMA 1/2, Pro, Lossless and Voice | Kotlin | `KotlinWmaProvider.kt` |
| DSF and DFF | Kotlin | `KotlinDsdProvider.kt` |
| MS/IMA ADPCM and G.711 | Kotlin | `KotlinPcmVariantsProvider.kt` |
| Multichannel downmix | Kotlin | `ChannelMapper.kt` |
| TTA, TAK | none | — |

Also bring over `player/decoders/DecoderRegistry.kt`, `DecoderProvider.kt`, `CodecProbe.kt`, `kotlin/KotlinDecodingExtractor.kt`, `ExtractorRandomAccessSource.kt` and `media3/ProviderExtractorsFactory.kt`.

`DecoderRegistry` probes the phone at runtime (`CodecProbe.kt`). Never hard-code one device's codec list.

---

## 4. Every feature that depends on FFmpeg and its replacement

Call sites, from `grep FFmpegKit|FFprobeKit|FFmpegService`:

| # | Feature | FFmpeg call site | What FFmpeg does | Replacement |
|---|---|---|---|---|
| F1 | **ReplayGain scan** (Edit / song menu: ReplayGain apply) | `replaygain_service.dart:71` → `FFmpegService.scanReplayGain` → `ffmpeg_replaygain.dart` (`ebur128=peak=true`) | Decodes the whole file. Measures integrated LUFS and the true peak. | `OfflineDecoder` → `analysis/.../PcmAnalyzer` (groups = LOUDNESS: `Loudness.kt` BS.1770 plus `AnalysisResampler` 192 kHz true peak). Gain = −18 − LUFS. Album: Sistrum's `AlbumLoudnessPlanner.kt` gates over the whole album. Tests: Sistrum validates against an FFmpeg oracle (`docs/analysis/ORACLE.md`). Port the oracle JSON as fixtures. |
| F2 | **ReplayGain write fallback** | `replaygain_service.dart:166-167` → `writeAlbum/TrackReplayGainTags` (stream-copy remux) | Used only when the native Rust writer fails. Never for Opus, Ogg or M4A. | **Delete the fallback.** Rust `tags/write/*` writes FLAC, MP3 (ID3), Ogg/Opus, M4A, APE/WV/MPC, WAV and AIFF. On failure, keep the original and report it, as Opus and M4A already do. |
| F3 | **Tag edit fallback** (Edit Metadata for MP3, M4A and Opus) | `metadata_persistence_service.dart:242-254` → `embedMetadataTo{Mp3,M4a,Opus}`; Rust returns `"method":"ffmpeg"` (`rust_backend/crates/local/src/backend/tags.rs:115`) when its native write fails | Remuxes with new metadata and cover. | **Delete the fallback.** Make Rust return an error instead of `method: ffmpeg`. Remove `MetadataSaveCodec`, `_embed`, `_fallbackTags` and `ffmpeg_metadata.dart`'s embed code. Rename `MetadataSaveFailure.ffmpeg` and the `metadataSaveFailedFfmpeg` string to a generic "the file could not be written". Keep `id3v23_lyrics.dart` only if a native path still calls it. |
| F4 | **Cover resize** (save cover with max dimension; collection/playlist covers) | `metadata_cover_resources.dart:149`, `library_collections_provider.dart:36` → `resizeCoverArt` (`scale … lanczos`, JPEG q 2) | Decodes the image, scales it and encodes JPEG. | Rust `image` crate (already in `spotiflac-core`, used by `native_palette`), as a new `data_jobs` job, or Android `ImageDecoder` with a target size and `Bitmap.compress(JPEG, 95)`. Prefer Rust: it needs no channel per platform and gives the same output everywhere. |
| F5 | **Image dimensions probe** | `metadata_cover_resources.dart:71`, `library_collections_provider.dart:37` → `probeImageDimensions` | ffprobe on the image | Rust `image::image_dimensions` or `BitmapFactory` `inJustDecodeBounds`. |
| F6 | **CUE split into tracks** | `local_song_file_actions.dart:344` → `splitCueToTracks` → `ffmpeg_cue.dart` (`-ss/-to`, copy, or FLAC level 8 for FLAC, WAV, APE and WV sources) | Cuts, and re-encodes lossless sources to FLAC. | See decision D5. (a) Play CUE tracks directly with `ClippingConfiguration`, which removes the *need* to split for playback. (b) If Split stays: decode with `OfflineDecoder` or the Kotlin decoders, encode with the platform FLAC encoder (`c2.android.flac.encoder`, probed at runtime), write the `fLaC` container yourself (STREAMINFO with the MD5 updated), then copy tags with the Rust writer. Lossy sources: MP3 frame-boundary byte copy; AAC/M4A through `MediaExtractor` + `MediaMuxer` (MP4); Opus through `MediaMuxer` OGG (API 29+). (b) is new code (about 400–600 lines) with no Sistrum source. |
| F7 | **Audio Quality Analysis: spectrogram** | `audio_analysis_widget.dart:631` (`showspectrumpic` to PNG) | Decodes and renders a spectrogram image. | `OfflineDecoder` → `dsp/fft/Plan.kt` (FFT) → magnitude grid → paint in Dart (`CustomPainter`) or encode the PNG in Rust with `image`. Keep the current bounded size and time limits. |
| F8 | **Audio Quality Analysis: peak, RMS and clipping per channel** | `audio_analysis_widget.dart` `astats` | Statistics per channel | `PcmAnalyzer` gives RMS, crest, the sample peak and the true peak. Per-channel peak, RMS and clip count are a few lines of new code on the same PCM. |
| F9 | **Audio Quality Analysis: spectral cutoff** (fake-lossless detection) | FFmpeg decodes → Rust `spectral_cutoff` job | Decode only | `OfflineDecoder` PCM → the same Rust job. The analysis is unchanged. |
| F10 | **Audio Quality Analysis: media information** | `audio_analysis_widget.dart:1432` `FFprobeKit.getMediaInformation` | Codec, sample rate, bit depth, channels, bitrate and duration | Media3 `Format` from the decode (`sampleMimeType`, `sampleRate`, `channelCount`, `pcmEncoding`, `bitrate`) plus Rust tag properties (already read at scan). |
| F11 | **Music haptics** | `music_haptics.dart:238,247` (decodes to mono s16le at `musicHapticsSampleRate`) | Decodes and downmixes | `OfflineDecoder` → `Matrix` downmix → `Resampler` → the same Dart hit detector. Alternative: tap the playing PCM with a pass-through `AudioProcessor` (no second decode). |
| F12 | **AutoMix analysis** | `automix_analyzer.dart:23` | Decodes a 24 s head and tail | `OfflineDecoder` with a start position and duration (seek, then stop), then the same Rust `automix` job. |
| F13 | **AutoMix effects render** | `automix_effect_renderer.dart:71` | Renders the effect tail | Live processors (3.4). Delete the renderer and its temp WAVs. |
| F14 | **FFmpeg log level, session IDs and cancel** | `ffmpeg_support.dart`, `audio_analysis_jobs.dart` (`cancel: FFmpegKit.cancel`) | Job control | `AudioAnalysisJobs` keeps its shape. `cancel` releases the decode `ExoPlayer` (Sistrum `OfflineDecoder` already completes once and cancels cleanly). |
| F15 | **androidTest FFmpeg** | `android/app/build.gradle.kts:214` `com.antonkarpenko:ffmpeg-kit-audio`, `androidTest/.../FFmpegCapabilitiesTest.kt` | Test fixtures | Remove the test. Generate fixtures on the host (Sistrum `scripts/test-corpus`, `waxflow-*-corpus.py`). |

### 4.1 One shared decode service

F1, F7–F12 all need "decode this file (optionally from start S for duration D) to PCM". Build that once, from Sistrum's code:

- `analysis/OfflineDecoder.kt`: its own ExoPlayer on two decode threads, with the registry's renderers and extractors.
- `analysis/CaptureAudioSink.kt`: an `AudioSink` that collects PCM instead of playing it.
- `analysis/PcmDecoder.kt`: the interface.
- `analysis/AnalysisConcurrency.kt`: limits how many decodes run at once.

Expose it to Dart as one native data job with path, start, duration, channels, sample rate and format. It returns a temp PCM file, or streams blocks to Rust or the analyzer. All decoding then uses the same decoders as playback, so APE, WavPack, WMA and DSD analysis work where FFmpeg handled them.

### 4.2 Strings, settings and UI that mention FFmpeg

- `lib/l10n/arb/app_en.arb`: `metadataSaveFailedFfmpeg` and any other FFmpeg wording.
- `pubspec.yaml:59` comment, `android/app/proguard-rules.pro:9` (comment about the FFmpeg plugin's keep rules).
- About and licences: `assets/licenses/` has no FFmpeg file today; check the About page's list.

---

## 5. Sistrum's plan: what is done and what is not

Read from `specs/*/HANDOFF.md` and `tasks.md` at `88e5987`.

| Spec | Scope | State | What you will need to continue |
|---|---|---|---|
| **001 media3-migration** | Engine seam, Media3 engine, Decoder Registry, AIFF, DSP chain and limiter session, normalization (tags, then measured), A/B crossfade, MediaSession fixes | **Done** (101 of 102 tasks; M1–M8 closed 2026-10-14). Owner checks not done: listening test, SC-013 1-hour screen-off power run. SC-013 (CPU and power budget) **not met**, deferred to cleanup. | Port as is. Carry over the open pre-v1.0 items from `001 HANDOFF` "Pre-v1.0 review phase": `LimiterStatus` keeps a stale state after the service stops; a failed restore decode keeps a bad session; FTS "AND" bug (Sistrum only). |
| **002 kotlin-decoders** | Kotlin decoders, Night mode, silence-aware crossfade, scan and tags, Mood Radio, CUE, performance gate | **M1 and M2 done** (26 of 48): all decoder providers, offline decode with the registry, Night mode, silence profiles. **Open:** M3 scan routing and extra-format tags (T021a–T028), M4 Mood Radio (T029–T033), **M5 CUE playback with `ClippingConfiguration` (T034–T039)**, M6 performance measurement (T040–T041), docs (T042). | For this app, M3's tag routing is not needed: Rust already reads tags. **M5 (CUE playback) and M6 (performance on device) are needed** and must be done here, since they were never finished in Sistrum. Real-world decoder bugs were left to the decode-failure log (FR-064a). |
| **003 native-removal** | Format inventory, remove the native engine and FFmpeg, then the NDK | **Not started** (0 of 38). | The method applies here: write the format inventory first (section 3.6 is a start), remove step by step, and check the APK `lib/` at the end. Here the NDK cannot go fully (section 8). |
| 004 ui-extensions, 005 bugfixes | Sistrum's Compose UI | Not relevant | Do not port. |

### 5.1 Known weak points to carry forward

1. **CPU and power with crossfade on.** SC-013 is not met in Sistrum. Measure on a weak device before turning AutoMix on by default.
2. **Hardware output continuity** during A/B overlap (HAL warnings, D-43 in 002 `DECISIONS.md`). This was not proven on hardware.
3. **Decoder coverage** is tested against WaxFlow oracles on synthetic or reference files. There were no real APE or DSD libraries, so keep the failure log.
4. `PlaybackQueue` 1000-track clamp is a Sistrum-only bug. Our queue is Dart, so it does not apply.

---

## 6. How to bring the code over

`git cherry-pick` does not work between these repositories. They have no shared history, the paths differ (`androidApp/` vs `android/app/`), the packages differ (`com.amwolfstein.sistrum` vs `com.zarz.spotiflac`) and the UI frameworks differ (Compose vs Flutter).

Use this instead:

1. **Pure JVM modules, copied whole.** `codecs`, `dsp`, `analysis` and `metadata` are `kotlin("jvm")` modules with no Android or Media3 dependency.
   - Add them under `android/` as Gradle modules: `include(":codecs")` and the others in `android/settings.gradle.kts`, then `implementation(project(":codecs"))` and so on.
   - Keep their package names, or rename them in one mechanical commit. Keep the `SPDX` and attribution headers and each module's `THIRD-PARTY-NOTICES`.
   - Bring their host tests and oracle fixtures (`docs/dsp`, `docs/analysis`, `androidApp/src/test/resources/waxflow`).
   - `metadata` is optional: Rust already reads tags.
2. **Android player code, copied and adapted:**
   - `player/media3/*`, `player/dsp/*`, `player/decoders/**`, `player/normalization/{GainSource,GainResolver,ItemGainMath}.kt` and `player/engine/{PlayerEngine,EngineEvent}.kt`;
   - `analysis/{OfflineDecoder,CaptureAudioSink,PcmDecoder,AnalysisConcurrency}.kt`.

   Replace Sistrum's DataStore, Room and `PlaybackCoordinator` dependencies with arguments that come from Dart.

   Do **not** copy:
   - `LegacyNativeEngine.kt`, `EngineFactory.kt`, `EngineSelectionPreferences.kt` and `FfmpegDecoder.kt`;
   - the Compose UI;
   - `PlaybackService.kt` and `PlaybackCoordinator.kt` (our Dart service does this job);
   - `TagGainSource.kt` (Rust reads tags).
3. **Dependencies:** `androidx.media3:media3-exoplayer` and `media3-common` 1.11.1 (Sistrum's pin; check for a newer stable). Add `androidx.work` only if measured loudness (3.3) is wanted.
4. **One commit per unit**, following `AGENTS.md`: code, then graphify, then docs. Record each port in `LOCAL_OFFLINE_MIGRATION_PLAN.md` with the Sistrum commit it came from.

### 6.1 The Flutter ↔ Media3 bridge (phase 1)

Add one Kotlin plugin (for example `Media3EnginePlugin.kt`) that owns the `PlayerEngine`. Remove `audioplayers` and its vendored copy.

**Method channel** (`com.zarz.spotiflac/engine`):

| Method | Purpose |
|---|---|
| `prepare(item, next?)` | Item fields: path or URI, clip start/end for CUE, gain dB, format hint. `next` is for gapless. |
| `play`, `pause`, `seek`, `stop` | Transport |
| `setSpeed`, `setPitch` | AutoMix rate and pitch |
| `setEqualizer(settings)` | EQ chain |
| `setNormalization(gainDb)` | ReplayGain gain |
| `beginTransition(plan)` | AutoMix: duration, curve, speed/pitch/low-pass/echo, beat offset |
| `snapTransition()` | Ends a running transition at once |
| `audioSessionId` | For EQ apps and the limiter |

**Event channel:** state, position, duration, completion, `TransitionStarted`, errors (with the decoder provider name), and output or route changes.

**Dart side:** `MusicPlaybackDeck` keeps its public API but talks to the plugin. AutoMix stops using two Dart decks and a volume timer. Instead it sends one `beginTransition` and the plugin runs both ExoPlayers on a shared session.

The USB routes (`UsbBitPerfectPlugin`, `UsbDirectPlayback`) stay separate plugins, used when USB mode is on, as today.

**Background playback:** `audio_service` keeps the Flutter engine alive in its service, so the plugin must live in that engine (it already does for `audioplayers`).

Phase 2 (optional): a Media3 `MediaSessionService` and `MediaLibraryService` for the notification and Android Auto, replacing `audio_service`. This is a separate project with its own risks (R9 in Sistrum's discovery: token and notification migration).

---

## 7. Suggested order

Each step: tests first where the step is risky, one analyze and full test run per batch, and three commits.

1. **Licence and minSdk decisions** (D1, D2).
2. **Modules:** add `dsp`, `codecs`, `analysis` with their host tests. No behaviour change.
3. **Offline decode service** (4.1). Move F12, F11 and F9 to it, then F7, F8 and F10, then F1. FFmpeg is still present for comparison: run both and compare the results on a corpus, then remove the FFmpeg path per feature.
4. **Cover resize and probe in Rust** (F4, F5).
5. **Remove the tag and ReplayGain write fallbacks** (F2, F3).
6. **Media3 engine plugin** with platform decoders only. Turn on gapless. Keep the `audioplayers` path behind a hidden developer switch until the device tests pass, as Sistrum did.
7. **Decoder Registry plus Kotlin providers.** Add the new formats to the scanner's playable set. Add a skipped or failed list.
8. **DSP chain:** EQ (N-band), balance, compressor, limiter, normalization gain.
9. **AutoMix on two ExoPlayers** with live effects (F13). Delete the renderer.
10. **CUE playback** with `ClippingConfiguration` (decision D5). Then the Split decision (F6).
11. **USB paths:** feed them from the Kotlin decoders or claxon. Remove libFLAC and WavPack C. Remove Oboe and `HiResPlayback` (decision D4).
12. **Remove:**
    - `audioplayers` and `third_party/audioplayers_android`;
    - `ffmpeg_kit_flutter_new_audio` and `lib/services/ffmpeg_*.dart`;
    - `android/app/src/main/cpp/`, `externalNativeBuild` and the `cmake` blocks;
    - `assets/licenses/{oboe,flac,wavpack}.txt`, the FFmpeg ProGuard comment and the FFmpeg test dependency;
    - the developer engine switch.

    Use the `AGENTS.md` feature-removal workflow: graphify first, then prove no references remain.
13. **Update `AGENTS.md` rules that name the old engine:**
    - "Audio playback uses only the built-in player…": keep the meaning, and name Media3.
    - "Exact PCM output decodes FLAC through the integer native source…": change it to the chosen Kotlin or claxon FLAC decoder.
    - "Artwork probing and FFmpeg processing for those retained features remain supported": remove the FFmpeg wording.
    - "Keep local tag/cover/lyrics editing, ReplayGain and CUE splitting as separate operations": update it per D5.
14. **Device checks** (owner): gapless, crossfade by ear, EQ, USB DAC bit-perfect, DSD, power with AutoMix on. Never report these as passed from host tests.

---

## 8. SDK and NDK after the migration

### Android SDK: **still needed**

Every Android build needs it:
- `compileSdk 37`, build-tools and platform-tools;
- AGP, Flutter's Gradle plugin and `adb` for the device tests;
- Media3, AndroidX and the Kotlin modules, which are ordinary SDK libraries.

Nothing in this migration removes the SDK.

### Android NDK: **still needed, but much less is built with it**

**What no longer needs the NDK after the migration:**

| Removed | Why it needed the NDK |
|---|---|
| `android/app/src/main/cpp/` (Oboe, libFLAC 1.5.0, WavPack 5.9.0), the CMake `externalNativeBuild`, `-DANDROID_STL=c++_static`, `CMakeLists.txt` and the CMake 4.1.2 pin | Compiled C/C++ with the NDK |
| FFmpeg Kit | Did not need the NDK (prebuilt `.so`), but it is the largest native payload in the APK. Removing it shrinks the APK and removes FFmpeg's LGPL notices. |
| `audioplayers` | Pure Kotlin. No NDK impact. |

The new code is pure Kotlin and JVM: Media3, Sistrum's `codecs`, `dsp` and `analysis`, and the processors. **None of it needs the NDK.**

**What still needs the NDK:**

| Still there | Why it needs the NDK |
|---|---|
| **Rust backend** (`rust_backend`, `libspotiflac_mobile.so`) | `scripts/build_rust_backend.sh` links with the NDK's `aarch64-linux-android24-clang` and `armv7a-…-clang` and uses NDK `llvm-ar` and its sysroot. Its C dependencies (`rusqlite` with bundled SQLite through `libsqlite3-sys`, and `libusb1-sys` vendored) are compiled by the NDK's clang. The `buildRustBackend` Gradle task reads `ANDROID_NDK_HOME` (`android/app/build.gradle.kts:169-173`). |
| **Direct USB** (decision D3) | Isochronous USB transfers are impossible from Java or Kotlin, so this driver must stay native (in Rust). |
| AGP release packaging | With `ndk { debugSymbolLevel = "FULL" }`, AGP uses the NDK's tools to strip packaged `.so` files and extract symbols: `libflutter.so`, `libapp.so`, the Rust library and JNA's `libjnidispatch.so`. Without an NDK it only warns and ships unstripped libraries. |

So keep `ndkVersion = "30.0.16248370"`, `ndk.abiFilters` and the ABI splits. Remove only `externalNativeBuild { cmake { … } }` (both blocks) and the CMake install from setup docs and CI.

**What it would take to need no NDK at all** (Sistrum's 003 step 2): rewrite or remove all of the Rust backend. That covers tags, scan, CUE, covers, palette, backup, the collections DB, lyrics, data jobs and the USB driver, and it drops Direct USB, because Java has no isochronous USB. That is not part of this migration and is not recommended. The Rust backend is tested, fast, and replaces much Dart and Kotlin code.

**Comparison:**

| Item | Today | After the migration |
|---|---|---|
| SDK | required | required |
| NDK | required (CMake C++ and Rust) | required (Rust only) |
| CMake | required | not needed |
| Native libraries built from our own sources | `libspotiflac_audio.so` and `libspotiflac_mobile.so` | `libspotiflac_mobile.so` only |
| Third-party prebuilt `.so` | FFmpeg Kit, JNA, Flutter | JNA, Flutter |

Unzip the release APK and list `lib/` before and after to confirm, as Sistrum 003 plans.

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| The GPL licence change is missed (D1). | Decide before step 2. Add `THIRD-PARTY-NOTICES` with each module. |
| Exact bit-perfect FLAC regresses (no libFLAC). | Byte-compare the decoded PCM of the Kotlin or claxon decoder against libFLAC on a 16, 24 and 32-bit corpus before removal. |
| EQ sound changes (DynamicsProcessing → biquads). | Keep DynamicsProcessing on the Media3 session as the first step. Change to biquads only with a measured comparison. |
| AutoMix CPU and battery (Sistrum SC-013 not met). | Measure on a weak device. Keep AutoMix off by default until measured. |
| Lower decode speed in Kotlin for WMA, APE and DSD on weak phones. | Sistrum 002 M6 never ran. Run the per-format real-time-factor test (Sistrum T040) here. |
| Analysis results change (FFmpeg ebur128 → Kotlin meter). | Sistrum's meter is validated against an FFmpeg oracle. Keep a tolerance test: ±0.1 LU integrated, ±0.1 dB true peak. |
| CUE Split has no clean replacement. | Play CUE directly (D5). Decide Split separately. |
| Background playback breaks when the plugin moves engines. | Keep `audio_service` in phase 1. Device test: screen off for 1 hour, Bluetooth, headset buttons. |
