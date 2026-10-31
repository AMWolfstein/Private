import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_controller.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_runner.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_store.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_worker.dart';

const _path = '/music/a.flac';

AudioAnalysisData _analysis({String path = _path, String codec = 'flac'}) =>
    AudioAnalysisData(
      filePath: path,
      fileSize: 1000,
      codec: codec,
      sampleRate: 44100,
      channels: 2,
      bitsPerSample: 16,
      duration: 180,
      bitrate: 900000,
      bitDepth: '16',
      dynamicRange: 12,
      peakAmplitude: -1,
      rmsLevel: -14,
      totalSamples: 7938000,
    );

Future<ui.Image> _image(WidgetTester tester) => tester
    .runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder);
      final picture = recorder.endRecording();
      final image = await picture.toImage(1, 1);
      picture.dispose();
      return image;
    })
    .then((image) => image!);

class _FakeArtifacts implements AudioAnalysisArtifacts {
  final analyses = <String, AudioAnalysisData>{};
  final spectrograms = <(String, int), ui.Image>{};
  final saved = <String>[];
  final cleared = <String>[];
  int trims = 0;
  bool failSpectrogramLoad = false;

  @override
  Future<AudioAnalysisData?> loadAnalysis(String path) async => analyses[path];

  @override
  Future<void> saveAnalysis(String path, AudioAnalysisData data) async {
    saved.add(path);
    analyses[path] = data;
  }

  @override
  Future<void> clearAnalysis(String path) async {
    cleared.add(path);
    analyses.remove(path);
  }

  @override
  Future<ui.Image?> loadSpectrogram(String path, {required int channel}) async {
    if (failSpectrogramLoad) throw StateError('unreadable');
    return spectrograms[(path, channel)]?.clone();
  }

  @override
  Future<void> saveSpectrogram(
    String path,
    ui.Image image, {
    required int channel,
  }) async {
    spectrograms[(path, channel)] = image;
  }

  @override
  void Function() retain(String path) => () {};

  @override
  void trim() => trims++;
}

class _FakeWorker implements AudioAnalysisWorker {
  _FakeWorker(this.image, this.checkRequest);

  final ui.Image image;
  final void Function(int requestId) checkRequest;
  final analyzeCalls = <String>[];
  final spectrogramChannels = <int>[];
  Object? analyzeError;
  Completer<void>? analyzeGate;
  Object? spectrogramError;
  int invalidations = 0;
  int nativeCancels = 0;
  bool disposed = false;

  @override
  Future<AudioAnalysisRunResult> analyze(String path, int requestId) async {
    analyzeCalls.add(path);
    await analyzeGate?.future;
    checkRequest(requestId);
    if (analyzeError != null) throw analyzeError!;
    return AudioAnalysisRunResult(
      data: _analysis(path: path),
      spectrogramImage: image.clone(),
    );
  }

  @override
  Future<GeneratedSpectrogram> spectrogram(
    String path, {
    required int requestId,
    required int channel,
    double? durationSeconds,
    int? sampleRate,
    int? channels,
  }) async {
    checkRequest(requestId);
    spectrogramChannels.add(channel);
    if (spectrogramError != null) throw spectrogramError!;
    return GeneratedSpectrogram(image: image.clone(), rgba: Uint8List(0));
  }

  @override
  void invalidate() => invalidations++;

  @override
  void cancelNative() => nativeCancels++;

  @override
  void dispose() => disposed = true;
}

AudioAnalysisController _controller({
  required _FakeArtifacts artifacts,
  required void Function(_FakeWorker worker) onWorker,
  String path = _path,
  String? codecHint,
  ui.Image? image,
}) {
  return AudioAnalysisController(
    filePath: path,
    codecHint: codecHint,
    artifacts: artifacts,
    createWorker: (checkRequest) {
      final worker = _FakeWorker(image!, checkRequest);
      onWorker(worker);
      return worker;
    },
  );
}

void main() {
  testWidgets('a cached analysis and spectrogram show without analyzing', (
    tester,
  ) async {
    final image = await _image(tester);
    final artifacts = _FakeArtifacts()
      ..analyses[_path] = _analysis()
      ..spectrograms[(_path, -1)] = image;
    _FakeWorker? worker;
    final controller = _controller(
      artifacts: artifacts,
      image: image,
      onWorker: (w) => worker = w,
    );
    addTearDown(controller.dispose);

    controller.start();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(controller.data?.codec, 'flac');
    expect(controller.spectrogramImage, isNotNull);
    expect(controller.checkingCache, isFalse);
    expect(worker!.analyzeCalls, isEmpty);
  });

  testWidgets('a cache miss analyses once and stores both results', (
    tester,
  ) async {
    final image = await _image(tester);
    final artifacts = _FakeArtifacts();
    _FakeWorker? worker;
    final controller = _controller(
      artifacts: artifacts,
      image: image,
      onWorker: (w) => worker = w,
    );
    addTearDown(controller.dispose);

    controller.start();
    await tester.runAsync(() => controller.analyze());

    expect(worker!.analyzeCalls, [_path]);
    expect(artifacts.saved, [_path]);
    expect(controller.data?.filePath, _path);
    expect(controller.spectrogramImage, isNotNull);
    expect(controller.analyzing, isFalse);
    expect(controller.error, isNull);
  });

  testWidgets('an unsupported cached codec clears the entry and reports it', (
    tester,
  ) async {
    final image = await _image(tester);
    final artifacts = _FakeArtifacts()
      ..analyses[_path] = _analysis(codec: 'ac4');
    final controller = _controller(
      artifacts: artifacts,
      image: image,
      onWorker: (_) {},
    );
    addTearDown(controller.dispose);

    controller.start();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(artifacts.cleared, [_path]);
    expect(controller.unsupportedCodec, 'AC-4');
    expect(controller.data, isNull);
  });

  testWidgets('an analysis failure keeps the error and stops analyzing', (
    tester,
  ) async {
    final image = await _image(tester);
    final failure = StateError('ffmpeg exited');
    final controller = _controller(
      artifacts: _FakeArtifacts(),
      image: image,
      onWorker: (w) => w.analyzeError = failure,
    );
    addTearDown(controller.dispose);

    await tester.runAsync(() => controller.analyze());

    expect(controller.error, same(failure));
    expect(controller.analyzing, isFalse);
    expect(controller.data, isNull);
  });

  testWidgets('a superseded analysis cannot change the new file state', (
    tester,
  ) async {
    final image = await _image(tester);
    final gate = Completer<void>();
    final controller = _controller(
      artifacts: _FakeArtifacts(),
      image: image,
      onWorker: (w) => w.analyzeGate = gate,
    );
    addTearDown(controller.dispose);

    final first = controller.analyze();
    controller.changeFile('/music/b.flac');
    gate.complete();
    await tester.runAsync(() => first);

    expect(controller.filePath, '/music/b.flac');
    expect(controller.data, isNull);
    expect(controller.error, isNull);
    expect(controller.analyzing, isFalse);
  });

  testWidgets('changing channel loads that channel and keeps it on success', (
    tester,
  ) async {
    final image = await _image(tester);
    final artifacts = _FakeArtifacts()
      ..analyses[_path] = _analysis()
      ..spectrograms[(_path, -1)] = image;
    _FakeWorker? worker;
    final controller = _controller(
      artifacts: artifacts,
      image: image,
      onWorker: (w) => worker = w,
    );
    addTearDown(controller.dispose);
    controller.start();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    await tester.runAsync(() => controller.changeChannel(1));

    expect(controller.spectrogramChannel, 1);
    expect(controller.spectrogramChannelLoading, isFalse);
    expect(worker!.spectrogramChannels, [1]);
  });

  testWidgets('a failed channel switch restores the previous channel', (
    tester,
  ) async {
    final image = await _image(tester);
    final artifacts = _FakeArtifacts()
      ..analyses[_path] = _analysis()
      ..spectrograms[(_path, -1)] = image;
    _FakeWorker? worker;
    final controller = _controller(
      artifacts: artifacts,
      image: image,
      onWorker: (w) => worker = w,
    );
    addTearDown(controller.dispose);
    controller.start();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    worker!.spectrogramError = StateError('decode failed');

    await tester.runAsync(() => controller.changeChannel(1));

    expect(controller.spectrogramChannel, -1);
    expect(controller.spectrogramChannelLoading, isFalse);
  });

  testWidgets('dispose cancels native work and ignores late results', (
    tester,
  ) async {
    final image = await _image(tester);
    final gate = Completer<void>();
    _FakeWorker? worker;
    final controller = _controller(
      artifacts: _FakeArtifacts(),
      image: image,
      onWorker: (w) {
        worker = w;
        w.analyzeGate = gate;
      },
    );

    final pending = controller.analyze();
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.dispose();
    gate.complete();
    await tester.runAsync(() => pending);

    expect(worker!.disposed, isTrue);
    expect(worker!.nativeCancels, greaterThan(0));
    expect(controller.data, isNull);
    expect(notifications, 0);
  });
}
