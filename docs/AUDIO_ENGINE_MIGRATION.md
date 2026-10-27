# Audio engine migration: Media3/ExoPlayer, no FFmpeg

> Identity normalization (T16, 2026-10-28): historical names, paths and command strings below were mechanically renamed. Original evidence used the former terms; no listed checks were rerun by this rename. Encoded upstream/download identifiers retain their actual destinations.

Status: plan only. Nothing in this file has been implemented or tested.

Naming clarification after T16: in this plan, unqualified **Sistrum** source/module/spec
references mean the **retired Compose reference app** (`AMWolfstein/Sistrum` at `88e5987`),
not this renamed Flutter app. References to the upstream Flutter project retain their real
percent-encoded identifiers. The GPL discussion below concerns a future engine port; this
branding-only rename does not import that code or relicense the current MIT app.

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
| D1 | **Licence.** This app is **MIT**. Every Sistrum file is **GPL-3.0** (`codecs` 146, `metadata` 48, `dsp` 9 and `analysis` 15 files, `player/` and `analysis/` app code). Some files are ports of other GPL projects: Rhythm, Choir, aubio and Airmedy (`PcmAnalyzer.kt` is GPL-3.0-only). | Shipping Sistrum code makes the whole APK a GPL-3.0 work. You may relicense only code you wrote yourself. The Rhythm, Choir, aubio and Airmedy ports stay GPL. | **Decided (owner, 2026-10-24): accept GPL-3.0.** Change `LICENSE` to GPL-3.0-or-later in the same commit that first adds Sistrum code; keep the MIT notice for the original Sistrum code and add `THIRD-PARTY-NOTICES` for each module. |
| D2 | **Minimum SDK.** Sistrum requires API 31. This app uses `flutter.minSdkVersion` = 24. | Sistrum code assumes API 31 or newer. It uses `DynamicsProcessing` (API 28) and the newer `AudioTrack` and `MediaCodec` encodings without version checks. | **Decided (owner, 2026-10-24): raise minSdk to 31 (Android 12)** in the first engine-port code commit; record it in `LOCAL_OFFLINE_MIGRATION_PLAN.md`. |
| D3 | **Direct USB (libusb in Rust).** Media3 cannot do this. The Java USB API (`UsbRequest`) has no isochronous transfers. | The libusb direct USB driver must stay native, so the NDK stays. | **Decided (owner, 2026-10-24): drop Direct USB.** Remove it with the feature-removal workflow during the USB step (section 7, step 11). The Android 14+ bit-perfect path (`UsbBitPerfectPlugin.kt`, including DoP) stays. |
| D4 | **AAudio exact-rate output (`HiResPlayback.kt`, Oboe).** AAudio has no Java API. | Removing it removes the last C++ code in `cpp/`. | **Decided (owner, 2026-10-26): remove it.** Delete `HiResPlayback.kt`, Oboe, the `dapExclusive` setting, its strings, search entry and backup key (old imports ignore it). Bit-perfect USB on Android 14+ stays. |
| D5 | **CUE "Split into Tracks".** FFmpeg cuts the file today: it stream-copies, or re-encodes to FLAC. Android has no FLAC muxer, and Sistrum has no splitter. | Media3 can **play** CUE tracks directly with `MediaItem.ClippingConfiguration`. Today CUE tracks **must** be split before they play (`cueVirtualTrackRequiresSplitMessage`, `lib/utils/file_access.dart:26`). | **Decided (owner, 2026-10-26): remove Split into Tracks.** CUE tracks play directly through Media3 `ClippingConfiguration` instead. Remove Split only in the same batch that makes CUE tracks playable, never before (today CUE tracks play only after a split). |
| D6 | **The bridge between Flutter and Media3** (section 6). | This decides how much Dart playback code changes. | **Decided (owner, 2026-10-26): remove `audio_service` and move playback to Kotlin.** A Media3 `MediaSessionService` in Kotlin owns the player, queue, session, notification, Android Auto, media buttons and background playback (section 6.1). Flutter becomes the UI that controls it. |
| D7 | **Formats with no decoder after FFmpeg.** Sistrum lists `tta` with no provider (`DecoderRegistry.kt`). TAK and anything else FFmpeg plays are also uncovered. | Removing FFmpeg does not change playback: playback never used FFmpeg here. But analysis, ReplayGain scan, haptics and AutoMix lose FFmpeg's decoders. | Accept those as unsupported. Show them in a skipped or failed list (Sistrum FR-064a, the decode-failure log). |

---

## 2. What the audio engine is today

| Layer | Code | Notes |
|---|---|---|
| Dart player service | `lib/services/music_player_service.dart` (2263 lines), `music_player_runtime.dart`, `music_player_automix.dart`, `music_player_autoplay.dart`, `playback_*.dart` | Owns the queue, session restore, history, normalization, sleep timer, AutoMix and headphone handling. |
| Dart deck | `lib/services/music_playback_deck.dart` | Wraps one `audioplayers` `AudioPlayer` plus the native USB/hi-res route (`com.amwolfstein.sistrum/usb_pcm`). There are two decks for AutoMix. |
| Ordinary engine | `audioplayers` 6.8.1 with a vendored `third_party/audioplayers_android` | Android **MediaPlayer**. Local patches: `/proc/self/fd` SAF leases, output-error handling and a `DynamicsProcessing` EQ (`PlaybackEqualizer.kt`). **No gapless playback.** |
| Session | vendored `third_party/audio_service` 0.18.19, `audio_session` 0.2.4 | Framework MediaSession, notification, Android Auto browse, focus and noisy events. |
| Hi-res / bit-perfect | `UsbBitPerfectPlugin.kt` (AudioTrack and Android 14 preferred mixer), `HiResPlayback.kt` (Oboe AAudio), `UsbDirectPlayback.kt` and Rust `mobile/src/usb_audio/*` (libusb), `UsbPcmSource.kt`, `BitPerfectPcm.kt`, `DsdFile.kt`, `DsdSource.kt` | The USB route decodes with MediaExtractor/MediaCodec, **libFLAC** (`flac_pcm_source.cpp`) and **WavPack** (C). DSD goes through DoP or native USB only. |
| C++ library | `android/app/src/main/cpp/` (CMake, `libsistrum_audio.so`): Oboe 1.11, libFLAC 1.5.0, WavPack 5.9.0 | Exports 18 JNI functions (`native_audio.map`). |
| Rust | `rust_backend` (UniFFI and JNA, `libsistrum_mobile.so`) | Tags (read and write), CUE parsing, scan, covers, palette, backup, collections DB (`rusqlite` bundled), USB driver, and analysis maths for AutoMix and spectral cutoff on PCM that FFmpeg decoded. |
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
| Volume, focus ducking, noisy and headphone events | `audio_session`, `_configureAudioSession`, `_pauseForFocusLoss`, `_startHeadphoneMonitoring` | Kotlin `PlaybackService` handles focus, noisy and headset events (D6); remove `audio_session`. Media3 runs with `handleAudioFocus = false` as in Sistrum. | `player/media3/FocusVolumeRamp.kt` | Sistrum ramps the duck to 0.2. Optional. |
| Sleep timer, repeat, shuffle, queue, session restore, autoplay | Dart | Move to Kotlin `PlaybackCoordinator` (D6, section 6.1); port the Dart tests first | — | Must keep working with the app closed. |
| Notification, lock screen, Android Auto, media buttons | `audio_service` | Media3 `MediaLibraryService` in Kotlin (decision D6); remove `audio_service` and `third_party/audio_service`. | ADR-006 (Sistrum also kept the framework session in 001) | Keep the behaviour ported from Sistrum `463c2ce9`: metadata or artwork that arrives after a track starts must update the notification, lock screen and Auto without changing position or controls (Media3 `replaceMediaItem` or a metadata update on the session). |
| Home-screen widget | `player_widget_service.dart`, `PlayerWidgetProvider.kt` | Updated by the Kotlin service, so it also works with the app closed (D6) | — | — |

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
| Beat landing check and phase lock (Sistrum `9843149d`, `44c9ba92`, ported 2026-10-27) | `music_player_automix.dart` `_alignIncoming`, `_phaseError`; `automix_phase_lock.dart`; uncertain grids get a bass handoff at unchanged tempo | Keep the same rules in the Kotlin transition: seek the incoming player onto the outgoing beat grid (up to three tries), fall back to an unstretched crossfade when the landing cannot be verified, and apply small bounded rate corrections from spaced position samples during the overlap | none in Sistrum | Port `AutoMixPhaseLock` and its tests with the transition; ExoPlayer positions are more precise, so the tolerances may be tightened after device checks. |

### 3.5 Hi-res, bit-perfect, USB and DSD

| Feature | Current code | Replacement | Sistrum source | Gap / note |
|---|---|---|---|---|
| Android 14+ bit-perfect mixer to USB DAC (`usbBitPerfect`, `usbAllowFixedVolume`, `dapExclusive`) | `UsbBitPerfectPlugin.kt` (own AudioTrack) | Keep the plugin. Change its **source** to the Kotlin decoders. | `player/decoders/kotlin/CodecStream.kt`, `codecs/*` | Media3 bypasses no processors on this path, so keep it separate from the Media3 chain. ReplayGain, AutoMix and EQ stay bypassed here, as today. |
| Exact FLAC PCM (`AGENTS.md`: "never trust vendor raw FLAC decoding") | `flac_pcm_source.cpp` (libFLAC) | A Kotlin FLAC decoder, or Rust `claxon` (listed in `sistrum-core`'s `Cargo.toml` but unused since `ef8ba64` removed the Hi-Res module; RUST-201: it needs a frame channel-count guard). If Rust moves to Kotlin (section 10), choose the Kotlin decoder. | **Sistrum has no Kotlin FLAC decoder.** It uses the platform decoder. WaxFlow has `codec/flac` that could be ported. | **Gap.** Choose claxon in Rust (no JNI hop for the USB worker) or port WaxFlow's FLAC. The platform decoder's float output is lossless only up to 24-bit. |
| WavPack PCM for the USB path | WavPack C (`openWavPack`…) | `codecs/.../codec/wavpack/*`, `container/wv/*` | `KotlinWavPackProvider.kt` | Oracle-tested against WaxFlow in Sistrum. Sistrum's notes say WaxFlow refuses hybrid, float and >2-channel WavPack, so check the Kotlin port's own refusals. |
| WavPack DSD | `WavPackDsdSource` (C) | `codecs/.../container/wv/WavPackDsd.kt`, `codec/wavpack/Dsd.kt` | — | — |
| DSF and DFF over DoP or native USB (`usbDsdOverPcm`) | `DsdFile.kt`, `DsdSource.kt`, Rust USB | Keep `DsdFile.kt` or use `codecs/.../container/dsf`, `container/dff`, plus `codec/dsd/DopPacker.kt` | `KotlinDsdProvider.kt` | — |
| DSD on ordinary output | **not supported** (`dsd_unsupported`) | DSD→PCM decimation | `codecs/.../codec/dsd/DsdDecimationPipeline.kt`, `DsdRateConverter.kt` | **New feature:** DSD plays on any output. |
| AAudio exact-rate output | `HiResPlayback.kt` and Oboe | none (decision D4) | — | — |
| Direct USB driver (libusb, isochronous) | Rust `usb_audio/*`, `UsbDirectPlayback.kt` | **Dropped** (decision D3) | — | **Dropped (decision D3).** Remove `UsbDirectPlayback.kt`, Rust `usb_audio/*`, `libusb1-sys`, the `usbDirect` setting, its strings, search entries and backup key (old imports ignore it). |
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
| F4 | **Cover resize** (save cover with max dimension; collection/playlist covers) | `metadata_cover_resources.dart:149`, `library_collections_provider.dart:36` → `resizeCoverArt` (`scale … lanczos`, JPEG q 2) | Decodes the image, scales it and encodes JPEG. | Rust `image` crate (already in `sistrum-core`, used by `native_palette`), as a new `data_jobs` job, or Android `ImageDecoder` with a target size and `Bitmap.compress(JPEG, 95)`. Prefer Rust: it needs no channel per platform and gives the same output everywhere. |
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

`git cherry-pick` does not work between these repositories. They have no shared history,
the paths differ (`androidApp/` vs `android/app/`) and the UI frameworks differ (the retired
Compose app vs this Flutter app). Both now use `com.amwolfstein.sistrum`; the retired
Compose app must be uninstalled before installing this Flutter app because their signing
identities can conflict. A shared package name does not make their code interchangeable.

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

### 6.1 Playback moves to Kotlin; Flutter is the UI (decision D6)

`audio_service` goes. Without it, nothing keeps the Flutter engine alive when the app is closed, so **everything
that must keep working with the screen off or the app closed moves to Kotlin**. That covers the player, queue,
session, notification, Android Auto, media buttons, widget updates, sleep timer and play history. Flutter stays the
UI and sends commands.

**Kotlin side** (largely from Sistrum):

| Piece | What it does | Sistrum source |
|---|---|---|
| `PlaybackService` (Media3 `MediaLibraryService`) | Foreground service, notification with the favorite and shuffle actions, lock screen, Android Auto browse tree, media buttons | `player/PlaybackService.kt`, `AndroidPlaybackSession.kt`, `AndroidPlaybackRuntime.kt` |
| `PlaybackCoordinator` | Queue, shuffle, repeat, next and previous, errors kept for retry, session save and restore, history and play counts | `player/PlaybackCoordinator.kt`, `PlaybackSessionStore.kt`, `QueueHandoff.kt` |
| `Media3Engine` | Two ExoPlayers, gapless, AutoMix transitions, DSP chain, normalization | `player/media3/*`, `player/dsp/*` |
| Focus, noisy and headset events | Pause on focus loss or unplug, resume on headphones connected | `PlaybackService.kt`, `FocusVolumeRamp.kt` (replaces `audio_session`) |

Port Sistrum's command-path fixes with them (FR-080…092 in Sistrum's 001 spec): one command channel, ordered
shutdown, foreground start on every start path.

**Dart side:**
- `music_player_service.dart` (2263 lines) and its helpers (`music_player_runtime.dart`, `music_player_automix.dart`,
  `music_player_autoplay.dart`, `playback_*`, `library_queue_store.dart`) shrink to a **client**. It sends
  commands and shows the state the service reports.
- **Player decisions move to Kotlin:**
  - the queue and its order;
  - AutoMix timing and the beat-match plan;
  - the autoplay and personalization picks;
  - normalization gain.

  Port them with their existing Dart tests as the specification: translate each test to Kotlin first, then the code.
- Remove `audio_service`, `third_party/audio_service`, `audio_session` and `audioplayers` (with its vendored copy).

**Method channel** (`<package>/playback`, Dart → Kotlin):

| Method | Purpose |
|---|---|
| `setQueue(items, startIndex, startPosition)`, `enqueue(items, playNext)`, `move`, `remove` | Queue. Items carry the path or URI, CUE clip start and end, and display metadata. |
| `play`, `pause`, `seek`, `skipToNext`, `skipToPrevious`, `skipToIndex`, `stop` | Transport |
| `setShuffle`, `setRepeat`, `setSleepTimer`, `cancelSleepTimer` | Modes |
| `setSettings(map)` | EQ, normalization, AutoMix, speed and pitch, bit-perfect, autoplay, "play on headphones connected" |
| `restoreSession`, `retry` | Session restore; retry after an error |

**Event channel** (Kotlin → Dart): the queue, current item, state, position, duration, errors (with the decoder
provider name), AutoMix status, output and route changes, and the equalizer and limiter status.

**Library data while the app is closed.** Android Auto browsing, history and play counts need the library and the
collections while no Dart code runs. Kotlin reads and writes the same SQLite database files that Dart uses, with
Android's SQLite (the same engine as `sqflite`). It must follow the same schema, WAL and locking rules, and the two
sides must never hold conflicting copies.

This is the biggest single step in the plan. Do it as its own milestone, after the Media3 engine works under the
current `audio_service` setup:
1. Characterization tests for today's notification, Android Auto, media button, restore and focus behaviour.
2. The Kotlin service and coordinator.
3. Switch the Dart client.
4. Remove `audio_service`.

---

## 7. Suggested order

Each step: tests first where the step is risky, one analyze and full test run per batch, and three commits.

1. **Licence and minSdk decisions** (D1 decided: GPL-3.0; D2 decided: minSdk 31).
2. **Modules:** add `dsp`, `codecs`, `analysis` with their host tests. No behaviour change.
3. **Offline decode service** (4.1). Move F12, F11 and F9 to it, then F7, F8 and F10, then F1. FFmpeg is still present for comparison: run both and compare the results on a corpus, then remove the FFmpeg path per feature.
4. **Cover resize and probe in Rust** (F4, F5).
5. **Remove the tag and ReplayGain write fallbacks** (F2, F3).
6. **Media3 engine plugin** with platform decoders only. Turn on gapless. Keep the `audioplayers` path behind a hidden developer switch until the device tests pass, as Sistrum did.
7. **Decoder Registry plus Kotlin providers.** Add the new formats to the scanner's playable set. Add a skipped or failed list.
8. **DSP chain:** EQ (N-band), balance, compressor, limiter, normalization gain.
9. **AutoMix on two ExoPlayers** with live effects (F13). Delete the renderer.
10. **CUE playback** with `ClippingConfiguration`, and in the same batch remove Split into Tracks (decision D5, F6).
11. **Playback moves to Kotlin** (D6, section 6.1): its own milestone, then remove `audio_service`, `audio_session` and `audioplayers`.
12. **USB paths:** remove Direct USB (D3). Feed the Android 14+ bit-perfect path from the Kotlin decoders or claxon. Remove libFLAC and WavPack C. Remove Oboe and `HiResPlayback` (decision D4).
13. **Remove:**
    - `audioplayers` and `third_party/audioplayers_android`;
    - `ffmpeg_kit_flutter_new_audio` and `lib/services/ffmpeg_*.dart`;
    - `android/app/src/main/cpp/`, `externalNativeBuild` and the `cmake` blocks;
    - `assets/licenses/{oboe,flac,wavpack}.txt`, the FFmpeg ProGuard comment and the FFmpeg test dependency;
    - the developer engine switch.

    Use the `AGENTS.md` feature-removal workflow: graphify first, then prove no references remain.
14. **Update `AGENTS.md` rules that name the old engine:**
    - "Audio playback uses only the built-in player…": keep the meaning, and name Media3.
    - "Exact PCM output decodes FLAC through the integer native source…": change it to the chosen Kotlin or claxon FLAC decoder.
    - "Artwork probing and FFmpeg processing for those retained features remain supported": remove the FFmpeg wording.
    - "Keep local tag/cover/lyrics editing, ReplayGain and CUE splitting as separate operations": drop "and CUE splitting" (D5).
    - "CUE tracks have Split into Tracks": replace with "CUE tracks play directly" (D5).
    - Remove the "DAP hi-res" mentions (D4) and the `audio_service` patch notes (D6).
15. **Device checks** (owner): gapless, crossfade by ear, EQ, USB DAC bit-perfect, DSD, power with AutoMix on. Never report these as passed from host tests.

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
| **Rust backend** (`rust_backend`, `libsistrum_mobile.so`) | `scripts/build_rust_backend.sh` links with the NDK's `aarch64-linux-android24-clang` and `armv7a-…-clang` and uses NDK `llvm-ar` and its sysroot. Its C dependencies (`rusqlite` with bundled SQLite through `libsqlite3-sys`, and `libusb1-sys` vendored) are compiled by the NDK's clang. The `buildRustBackend` Gradle task reads `ANDROID_NDK_HOME` (`android/app/build.gradle.kts:169-173`). |
| **Direct USB** (decision D3) | No longer: Direct USB is dropped (D3). Only the Rust backend keeps the NDK until section 10. |
| AGP release packaging | With `ndk { debugSymbolLevel = "FULL" }`, AGP uses the NDK's tools to strip packaged `.so` files and extract symbols: `libflutter.so`, `libapp.so`, the Rust library and JNA's `libjnidispatch.so`. Without an NDK it only warns and ships unstripped libraries. |

So keep `ndkVersion = "30.0.16248370"`, `ndk.abiFilters` and the ABI splits. Remove only `externalNativeBuild { cmake { … } }` (both blocks) and the CMake install from setup docs and CI.

**What it would take to need no NDK at all** (Sistrum's 003 step 2): move the whole Rust backend to Kotlin and drop Direct USB, because Java has no isochronous USB. That is a separate project to run **after** this migration (section 10).

**Comparison:**

| Item | Today | After the migration |
|---|---|---|
| SDK | required | required |
| NDK | required (CMake C++ and Rust) | required (Rust only) |
| CMake | required | not needed |
| Native libraries built from our own sources | `libsistrum_audio.so` and `libsistrum_mobile.so` | `libsistrum_mobile.so` only |
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
| CUE tracks become unplayable if Split is removed first. | Remove Split only in the batch that makes CUE tracks play directly (D5). |
| Background playback, Android Auto or the notification break when `audio_service` goes (D6). | Move playback to Kotlin step by step (6.1) with a characterization test for each `audio_service` behaviour first. Device test: screen off for 1 hour, Bluetooth, headset buttons, Android Auto, widget. |

---

## 10. Later project: move the Rust backend to Kotlin (no NDK)

Run this **after** the Media3 migration (sections 1–9) is finished and tested on a device, not at the same time.
Two engine rewrites at once make failures hard to trace.

### 10.1 Why

- **No NDK, no Rust toolchain, no cargo build, no per-ABI Rust builds, no UniFFI and no JNA.** The Android side
  becomes ordinary Gradle and Kotlin.
- **One native language on Android (Kotlin)**, the same as Sistrum, so code moves between the projects easily.
- **One SQLite engine.** Rust opens the app's databases with its own bundled SQLite (`rusqlite` `bundled`), while
  Dart (`sqflite`) uses Android's. Their features can differ: Dart already probes for trigram FTS5
  (`lib/services/sqlite_helpers.dart`). Kotlin would use the same Android SQLite as Dart.
- Faster, simpler builds and CI.

### 10.2 What moves (Rust at `05cbce5`: about 22,400 lines, 189 `#[test]`s)

| Rust part | Lines | Kotlin replacement | Difficulty |
|---|---|---|---|
| Tag reading and writing (`core/src/tags`, `mobile/src/tags.rs`, `native_id3.rs`) | about 6,100 | Port our own Rust readers and writers (our code, MIT). Optional source for reading: Sistrum `:metadata` (WaxLabel read port, GPL) or WaxLabel itself (Go, MIT, reads and writes). | **High**: the largest part, and a bug damages user files |
| File access and scan backend (`local/src/backend`, `files.rs`, capability checks with `cap-std`) | about 3,150 | `java.io` / `java.nio` plus the existing SAF code (`MainActivitySafIo.kt`, `SafFileOps.kt`). Keep the same path and grant checks. | Medium |
| **Direct USB driver** (`mobile/src/usb_audio`, libusb) | about 1,820 | **None.** Android's Java USB API (`UsbRequest`) has no isochronous transfers. | **Blocker** (10.3) |
| Backup (`native_backup`, `zip`) | about 2,130 | `java.util.zip` plus Android SQLite | Medium: the archive format must stay identical |
| Library DB, collections, playlists, cache (`native_library`, `native_collections`, `native_playlist*`, `native_cache`) | about 3,000 | Android SQLite (`SQLiteDatabase`) | Medium: same schema, transactions and WAL rules |
| Lyrics, XML, helpers (`native_lyrics.rs`, `native_xml.rs`, `core/src/lyrics`) | about 1,300 | Plain Kotlin | Easy |
| CUE parser (`core/src/cue.rs`) | 430 | Sistrum `codecs/cue/Cue.kt` (GPL) or a direct translation | Easy |
| Cover cache and palette (`core/src/cover*`, `native_palette.rs`, `image` crate) | about 960 | `ImageDecoder` / `BitmapFactory` plus `material-color-utilities` (Java). Keep the HCT rules in `AGENTS.md` (one analysis per cover version, `sistrumCoverColors`). | Easy to medium |
| Audio analysis maths (`native_audio_analysis.rs`) | 480 | Sistrum `:analysis` / `:dsp` | Easy |
| Data jobs and cancellation (`data_jobs.rs`, `cancellation.rs`) | about 560 | Kotlin coroutines with `Job` cancellation | Easy |
| UniFFI bindings, JNA, `SelectedCoreBackend.kt`, `NativeDataJobs.kt` | — | Removed | — |

**The seam already exists.** `CoreBackend.kt` (23 functions) is the interface, and `SelectedCoreBackend.kt` picks
the Rust implementation. Add a Kotlin implementation of the same interface and switch one part at a time. Dart and
the channel API stay unchanged.

### 10.3 Direct USB: the one blocker

**Decided (owner, 2026-10-24): drop Direct USB (D3).** The first row below applies, so this project ends with no NDK.

| Choice | Result |
|---|---|
| **Drop Direct USB** | Bit-perfect USB stays on Android 14+ through `UsbBitPerfectPlugin.kt` (Kotlin, preferred mixer). Phones below Android 14 lose bit-perfect USB output. Native DSD to DACs is lost; DSD still plays through DoP on the Android 14+ path, or converted to PCM. **No NDK at all.** |
| **Keep a small native libusb piece** | Only the USB worker stays native (Rust or C). The NDK stays, but only for that one library. |

### 10.4 What must stay byte-compatible

Each needs a test that runs the Rust and the Kotlin implementation on the same input and compares the outputs,
before the Rust part is removed:

- **library song IDs** (the T4 identity rules; a change breaks play counts, Loved and playlists);
- **database schemas** and migrations;
- **the backup archive format** (old backups must restore, new backups must open in older versions where that is
  promised today);
- **cover cache keys** and `cover_analysis` rows;
- **tag write output** (the same files, frames and padding policy; no lost pictures, lyrics or ReplayGain);
- **CUE parsing results** (track numbers, start and end times, the data-track skip).

Carry over the fixes from TASKS T1–T5 and the audit findings recorded for these files, with their tests. Do not
lose them in the rewrite.

### 10.5 Order (one part per batch, behind `CoreBackend`)

1. Lyrics, XML and playlist writing, the CUE parser, the palette.
2. Audio analysis (from Sistrum).
3. Cover cache, library DB and collections.
4. Backup.
5. Tag reading, then tag writing (highest risk, last).
6. The Direct USB decision (10.3).
7. Remove Rust, UniFFI, JNA, `buildRustBackend`, `scripts/build_rust_backend.sh`, `ndkVersion`, `ndk.abiFilters`,
   the Rust ABI checks and the related `AGENTS.md` and review rules, using the feature-removal workflow
   (graphify first, then prove no references remain).

Each batch follows the usual rules: tests first for risky parts, one analyze and full test run per batch, three
commits (code, graphify, docs).

### 10.6 Exact FLAC after this project

`claxon` goes away with Rust, so the bit-perfect FLAC decoder (section 3.5) must be Kotlin: port WaxFlow's
`codec/flac` (MIT; bit-exact on the IETF FLAC test suite). Compare it byte for byte with libFLAC before libFLAC is
removed.

### 10.7 End state

| Item | Today | After Media3 (sections 1–9) | After this project |
|---|---|---|---|
| Languages | Dart, Kotlin, Rust, C++ | Dart, Kotlin, Rust | **Dart, Kotlin** |
| SDK | required | required | required |
| NDK | required | required (Rust) | **not needed** (if Direct USB is dropped) |
| CMake, cargo, Rust toolchain | required | cargo and Rust toolchain only | **none** |
| Native libraries from our own sources | `libsistrum_audio.so`, `libsistrum_mobile.so` | `libsistrum_mobile.so` | **none** |
| Third-party prebuilt `.so` | FFmpeg Kit, JNA, Flutter | JNA, Flutter | Flutter only |

Size: about as big as the Media3 migration itself, roughly 20,000 lines of Kotlin plus tests.

### 10.8 Other option considered: WaxFlow and WaxLabel in Go

Sistrum used a Go backend (gomobile) until `aa997264` (2026-09-14). That backend was the download app's code
(providers, extensions, downloads, online lyrics, scan, basic tag editing) and had **no audio decoding**, so
restoring it does not help.

Using WaxFlow and WaxLabel directly from Go through gomobile, without porting, would give:
- exact FLAC decoding;
- CUE split with a FLAC encoder;
- R128 loudness with ReplayGain tagging;
- the decoders;
- tag writing, all MIT.

But it adds the Go runtime library (estimated +10–30 MB per ABI, not measured), gomobile's experimental status
(a Go crash kills the app with no Java stack) and keeps the NDK (cgo). Not chosen for the Kotlin end state. A size
and speed spike would be needed before reconsidering it.
