# C++/JNI and Java registration supplement (N4)

## Scope

Completes explicit native-language entrypoint reconciliation after general N1 screening. Source d5d5a02 unchanged. Coordinator dead-code-hunter declaration screen of android/app/src/main/cpp/{native_audio.cpp,flac_pcm_source.cpp,flac_pcm_source.h}; full native_audio.map,NativeAudio.kt and CMakeLists.txt reviewed (CMake retained from N1). Ranged body reads: flac_pcm_source.cpp1–70, native_audio.cpp1–70/115–145; combined output partly truncated, so no whole-body engine correctness claim. Test-provider AndroidManifest names checked. Graph-first native query already executed for same audit.

## Findings

None new. All18 external NativeAudio methods have explicit Kotlin/Java NativeAudio.<name> consumers (entire tracked Android source corpus searched), matching JNI macro functions and linker exports. NativeAudio initializer loads spotiflac_audio. CMake compiles native_audio.cpp and flac_pcm_source.cpp; host-test option registers flac_pcm_source_test as executable/test. Flac callbacks passed to init_file, DeleteDecoder through unique_ptr deleter, Oboe onAudioReady override through framework callback; absence of ordinary call syntax is not dead-code evidence. Two Java instrumentation providers registered by class name in androidTest manifest.

## Verification / limits

Read-only declarations/reference/config screen, no native compile/test, link map, runtime, security or behavioral review. Entry-point correspondence does not prove every internal branch/data member live; no new safe removal proved. Source unchanged, no graph update. Result PASS for bounded supplement.
