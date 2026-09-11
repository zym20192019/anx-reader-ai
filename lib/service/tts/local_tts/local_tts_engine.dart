import 'dart:io';
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
  void dispose();
}

/// Official Sherpa-ONNX implementation of [LocalTtsEngine].
class SherpaOnnxLocalTtsEngine implements LocalTtsEngine {
  sherpa_onnx.OfflineTts? _tts;
  bool _initialized = false;
  int _sampleRate = 22050;

  @override
  bool get isAvailable => _initialized && _tts != null;

  @override
  Future<void> init({
    required String modelDir,
    required LocalVoiceModel model,
  }) async {
    dispose();
    try {
      sherpa_onnx.initBindings();

      final modelPath = p.join(modelDir, model.onnxFileName);
      final tokensPath = p.join(modelDir, model.tokensFileName);
      final lexiconPath = p.join(modelDir, model.lexiconFileName);

      final ruleFstPaths = model.ruleFsts
          .map((f) => p.join(modelDir, f))
          .where((f) => File(f).existsSync())
          .join(',');

      final vits = sherpa_onnx.OfflineTtsVitsModelConfig(
        model: modelPath,
        lexicon: lexiconPath,
        tokens: tokensPath,
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
        ruleFsts: ruleFstPaths,
        maxNumSenetences: 1,
      );

      _tts = sherpa_onnx.OfflineTts(config);
      _sampleRate = model.sampleRate;
      _initialized = true;
      AnxLog.info('SherpaOnnxLocalTtsEngine initialized successfully with model ${model.id}');
    } catch (e) {
      _initialized = false;
      _tts = null;
      AnxLog.severe('Failed to initialize SherpaOnnxLocalTtsEngine: $e');
      rethrow;
    }
  }

  @override
  Future<Uint8List> synthesize(
    String text, {
    double speed = 1.0,
    int speakerId = 0,
  }) async {
    if (!isAvailable || _tts == null) {
      throw StateError('SherpaOnnxLocalTtsEngine is not initialized');
    }

    try {
      final genConfig = sherpa_onnx.OfflineTtsGenerationConfig(
        sid: speakerId,
        speed: speed,
        silenceScale: 0.2,
      );

      final audio = _tts!.generateWithConfig(text: text, config: genConfig);
      if (audio.samples.isEmpty) {
        return Uint8List(0);
      }

      final rate = audio.sampleRate > 0 ? audio.sampleRate : _sampleRate;
      return WavEncoder.encodeToWav(
        samples: audio.samples,
        sampleRate: rate,
        numChannels: 1,
      );
    } catch (e) {
      AnxLog.severe('SherpaOnnxLocalTtsEngine synthesis error: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_tts != null) {
      try {
        _tts!.free();
      } catch (e) {
        AnxLog.warning('Error freeing SherpaOnnx tts: $e');
      }
      _tts = null;
    }
    _initialized = false;
  }
}
