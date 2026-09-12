import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:anx_reader/service/tts/local_tts/local_voice_model.dart';
import 'package:anx_reader/service/tts/local_tts/wav_encoder.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// Interface for on-device TTS synthesis engines.
abstract class LocalTtsEngine {
  bool get isAvailable;
  Future<void> init({required String modelDir, required LocalVoiceModel model});
  Future<Uint8List> synthesize(String text, {double speed = 1.0, int speakerId = 0});
  Future<void> dispose();
}

/// Official Sherpa-ONNX implementation of [LocalTtsEngine].
/// Runs CPU/FFI neural inference inside a dedicated background [Isolate]
/// to prevent UI thread blocking and frame drops.
class SherpaOnnxLocalTtsEngine implements LocalTtsEngine {
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  bool _initialized = false;
  Future<void> _synthesizeLock = Future.value();
  final Set<ReceivePort> _activeResponsePorts = {};
  final List<Completer<Uint8List>> _pendingSyntheses = [];

  @override
  bool get isAvailable => _initialized && _workerSendPort != null;

  @override
  Future<void> init({
    required String modelDir,
    required LocalVoiceModel model,
  }) async {
    await dispose();
    _synthesizeLock = Future.value();

    final modelPath = p.join(modelDir, model.onnxFileName);
    final tokensPath = p.join(modelDir, model.tokensFileName);
    final lexiconPath = p.join(modelDir, model.lexiconFileName);

    final ruleFstPaths = model.ruleFsts
        .map((f) => p.join(modelDir, f))
        .where((f) => File(f).existsSync())
        .join(',');

    final initReceivePort = ReceivePort();
    try {
      _workerIsolate = await Isolate.spawn(
        _isolateWorker,
        initReceivePort.sendPort,
        debugName: 'SherpaOnnxTtsWorker',
      );

      final workerSendPort = await initReceivePort.first as SendPort;
      initReceivePort.close();

      final responsePort = ReceivePort();
      workerSendPort.send({
        'action': 'init',
        'modelPath': modelPath,
        'tokensPath': tokensPath,
        'lexiconPath': lexiconPath,
        'ruleFstPaths': ruleFstPaths,
        'sampleRate': model.sampleRate,
        'replyPort': responsePort.sendPort,
      });

      final res = await responsePort.first.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('Worker isolate init timed out'),
      ) as Map<dynamic, dynamic>;
      responsePort.close();

      if (res['success'] != true) {
        _initialized = false;
        await dispose();
        final err = res['error']?.toString() ??
            'Failed to initialize Sherpa-ONNX in worker isolate';
        AnxLog.severe('SherpaOnnxLocalTtsEngine worker init error: $err');
        throw StateError(err);
      }

      _workerSendPort = workerSendPort;
      _initialized = true;
      AnxLog.info(
          'SherpaOnnxLocalTtsEngine worker isolate initialized with model ${model.id}');
    } catch (e) {
      _initialized = false;
      await dispose();
      AnxLog.severe('Failed to initialize SherpaOnnxLocalTtsEngine: $e');
      rethrow;
    }
  }

  @override
  Future<Uint8List> synthesize(
    String text, {
    double speed = 1.0,
    int speakerId = 0,
  }) {
    if (!isAvailable || _workerSendPort == null) {
      return Future.error(
          StateError('SherpaOnnxLocalTtsEngine is not initialized'));
    }

    final completer = Completer<Uint8List>();
    _pendingSyntheses.add(completer);

    _synthesizeLock = _synthesizeLock.then((_) async {
      if (!isAvailable || _workerSendPort == null) {
        if (!completer.isCompleted) {
          completer.completeError(
              StateError('SherpaOnnxLocalTtsEngine is not initialized'));
        }
        return;
      }

      ReceivePort? responsePort;
      try {
        responsePort = ReceivePort();
        _activeResponsePorts.add(responsePort);

        _workerSendPort!.send({
          'action': 'synthesize',
          'text': text,
          'speed': speed,
          'speakerId': speakerId,
          'replyPort': responsePort.sendPort,
        });

        final res = await responsePort.first.timeout(
          const Duration(seconds: 30),
          onTimeout: () =>
              throw TimeoutException('Sherpa-ONNX worker synthesis timed out'),
        ) as Map<dynamic, dynamic>;

        if (res['success'] != true) {
          final err = res['error']?.toString() ??
              'Sherpa-ONNX worker synthesis failed';
          AnxLog.severe('SherpaOnnxLocalTtsEngine worker error: $err');
          if (!completer.isCompleted) {
            completer.completeError(StateError(err));
          }
          return;
        }

        if (!completer.isCompleted) {
          completer.complete(res['audio'] as Uint8List);
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      } finally {
        if (responsePort != null) {
          responsePort.close();
          _activeResponsePorts.remove(responsePort);
        }
      }
    }).whenComplete(() {
      _pendingSyntheses.remove(completer);
    });

    return completer.future;
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
    final sendPort = _workerSendPort;
    final isolate = _workerIsolate;
    _workerSendPort = null;
    _workerIsolate = null;
    _synthesizeLock = Future.value();

    for (final port in _activeResponsePorts.toList()) {
      try {
        port.close();
      } catch (_) {}
    }
    _activeResponsePorts.clear();

    for (final completer in _pendingSyntheses.toList()) {
      if (!completer.isCompleted) {
        completer.completeError(
            StateError('SherpaOnnxLocalTtsEngine was disposed'));
      }
    }
    _pendingSyntheses.clear();

    if (sendPort != null) {
      final replyPort = ReceivePort();
      try {
        sendPort.send({
          'action': 'dispose',
          'replyPort': replyPort.sendPort,
        });
        await replyPort.first.timeout(const Duration(milliseconds: 500));
      } catch (_) {
        if (isolate != null) {
          try {
            isolate.kill(priority: Isolate.immediate);
          } catch (_) {}
        }
      } finally {
        replyPort.close();
      }
    } else if (isolate != null) {
      try {
        isolate.kill(priority: Isolate.immediate);
      } catch (_) {}
    }
  }

  static void _isolateWorker(SendPort mainSendPort) {
    final workerReceivePort = ReceivePort();
    mainSendPort.send(workerReceivePort.sendPort);

    sherpa_onnx.OfflineTts? tts;
    int sampleRate = 22050;

    workerReceivePort.listen((message) {
      if (message is! Map<dynamic, dynamic>) return;
      final action = message['action'] as String?;
      final replyPort = message['replyPort'] as SendPort?;

      if (action == 'init') {
        try {
          sherpa_onnx.initBindings();

          final vits = sherpa_onnx.OfflineTtsVitsModelConfig(
            model: message['modelPath'] as String,
            lexicon: message['lexiconPath'] as String,
            tokens: message['tokensPath'] as String,
            dataDir: '',
          );

          final modelConfig = sherpa_onnx.OfflineTtsModelConfig(
            vits: vits,
            numThreads: 2,
            debug: false,
            provider: 'cpu',
          );

          final config = sherpa_onnx.OfflineTtsConfig(
            model: modelConfig,
            ruleFsts: message['ruleFstPaths'] as String,
            maxNumSenetences: 1,
          );

          if (tts != null) {
            try {
              tts!.free();
            } catch (_) {}
            tts = null;
          }

          tts = sherpa_onnx.OfflineTts(config);
          sampleRate = (message['sampleRate'] as num?)?.toInt() ?? 22050;
          replyPort?.send({'success': true});
        } catch (e, stack) {
          replyPort?.send({'success': false, 'error': '$e\n$stack'});
        }
      } else if (action == 'synthesize') {
        if (tts == null) {
          replyPort?.send({
            'success': false,
            'error': 'Sherpa-ONNX tts engine is not initialized in worker isolate',
          });
          return;
        }

        try {
          final text = message['text'] as String;
          final speed = (message['speed'] as num?)?.toDouble() ?? 1.0;
          final speakerId = (message['speakerId'] as num?)?.toInt() ?? 0;

          final genConfig = sherpa_onnx.OfflineTtsGenerationConfig(
            sid: speakerId,
            speed: speed,
            silenceScale: 0.2,
          );

          final audio = tts!.generateWithConfig(text: text, config: genConfig);
          if (audio.samples.isEmpty) {
            replyPort?.send({
              'success': true,
              'audio': Uint8List(0),
            });
            return;
          }

          final rate = audio.sampleRate > 0 ? audio.sampleRate : sampleRate;
          final wavBytes = WavEncoder.encodeToWav(
            samples: audio.samples,
            sampleRate: rate,
            numChannels: 1,
          );

          replyPort?.send({
            'success': true,
            'audio': wavBytes,
          });
        } catch (e, stack) {
          replyPort?.send({'success': false, 'error': '$e\n$stack'});
        }
      } else if (action == 'dispose') {
        if (tts != null) {
          try {
            tts!.free();
          } catch (_) {}
          tts = null;
        }
        replyPort?.send({'success': true});
        workerReceivePort.close();
        Isolate.current.kill();
      }
    });
  }
}
