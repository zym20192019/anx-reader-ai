import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:anx_reader/service/tts/local_tts/local_tts_engine.dart';
import 'package:anx_reader/service/tts/local_tts/local_voice_model.dart';
import 'package:anx_reader/service/tts/local_tts/local_voice_model_manager.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/material.dart';

/// Provider for offline natural voice text-to-speech.
class LocalTtsProvider extends TtsServiceProvider {
  static final LocalTtsProvider _instance = LocalTtsProvider._internal();

  factory LocalTtsProvider() => _instance;

  LocalTtsProvider._internal()
      : _modelManager = LocalVoiceModelManager(),
        _engine = SherpaOnnxLocalTtsEngine();

  /// Dependency-injected constructor for testing.
  LocalTtsProvider.withEngine({
    LocalVoiceModelManager? modelManager,
    required LocalTtsEngine engine,
  })  : _modelManager = modelManager ?? LocalVoiceModelManager(),
        _engine = engine;

  final LocalVoiceModelManager _modelManager;
  final LocalTtsEngine _engine;
  String? _initializedModelId;
  Future<void>? _initFuture;

  LocalVoiceModel get defaultModel => LocalVoiceModel.defaultChineseModel;

  @override
  TtsService get service => TtsService.local;

  @override
  String getLabel(BuildContext context) => '离线自然朗读';

  @override
  Future<List<TtsVoice>> getVoices() async {
    final isInstalled = await _modelManager.isModelInstalled(defaultModel);
    if (!isInstalled) {
      return [];
    }

    return [
      TtsVoice(
        name: defaultModel.displayName,
        shortName: defaultModel.id,
        locale: defaultModel.locale,
        gender: defaultModel.gender,
      ),
    ];
  }

  Future<void> _ensureInitialized() async {
    if (_engine.isAvailable && _initializedModelId == defaultModel.id) {
      return;
    }

    _initFuture ??= _doInit();
    try {
      await _initFuture;
    } finally {
      if (!_engine.isAvailable || _initializedModelId != defaultModel.id) {
        _initFuture = null;
      }
    }
  }

  Future<void> _doInit() async {
    final isInstalled = await _modelManager.isModelInstalled(defaultModel);
    if (!isInstalled) {
      throw StateError('离线声音包尚未安装，请在设置中下载后使用');
    }

    final modelDir = await _modelManager.getModelDir(defaultModel);
    AnxLog.info('Initializing local TTS engine from ${modelDir.path}');
    await _engine.init(
      modelDir: modelDir.path,
      model: defaultModel,
    );
    _initializedModelId = defaultModel.id;
  }

  /// Synthesizes [text] using the local on-device voice engine.
  @override
  Future<Uint8List> speak(
    String text,
    String? voice,
    double rate,
    double pitch,
  ) async {
    await _ensureInitialized();

    // Map rate (default 1.0) to engine speed
    final speed = rate > 0 ? rate : 1.0;
    return await _engine.synthesize(text, speed: speed);
  }

  Future<void> dispose() async {
    _initFuture = null;
    _initializedModelId = null;
    await _engine.dispose();
  }
}
