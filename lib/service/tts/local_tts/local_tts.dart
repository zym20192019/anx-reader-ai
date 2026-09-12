import 'dart:async';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/local_tts/local_tts_provider.dart';
import 'package:anx_reader/service/tts/local_tts/local_voice_model.dart';
import 'package:anx_reader/service/tts/local_tts/local_voice_model_manager.dart';
import 'package:anx_reader/service/tts/local_tts/wav_encoder.dart';
import 'package:anx_reader/service/tts/models/tts_segment.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/system_tts.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

@visibleForTesting
typedef TtsDetailCollector = Future<List<TtsSentence>> Function({
  required int count,
  bool includeCurrent,
  int offset,
});

@visibleForTesting
typedef TtsCfiHighlighter = Future<void> Function(String cfi);

@visibleForTesting
typedef TtsNextSectionHandler = Future<String?> Function();

/// Offline natural voice text-to-speech service.
/// Uses on-device model and Sherpa-ONNX runtime with queue-based sentence audio playback.
class LocalTts extends BaseTts {
  static final LocalTts _instance = LocalTts._internal();

  factory LocalTts({LocalVoiceModelManager? modelManager}) {
    if (modelManager != null) {
      _instance._modelManager = modelManager;
    }
    return _instance;
  }

  LocalTts._internal();

  static const int _bufferCapacity = 2;
  static const int _fetchTimeoutSeconds = 15;
  static const int _maxConsecutiveEmpty = 3;
  static const int _maxConsecutiveEmptyCollects = 3;

  static final TtsSegment _eofSegment = TtsSegment(
    sentence: const TtsSentence(text: '', cfi: null),
  )..isSilent = true;

  AudioPlayer? _player;
  StreamSubscription<void>? _playerCompleteSubscription;

  final List<TtsSegment> _buffer = [];
  final Set<String> _bufferKeys = {};
  TtsSegment? _currentSegment;
  String? _currentVoiceText;
  int _audioFetchVersion = 0;
  int _consecutiveEmptyCount = 0;
  int _consecutiveEmptyCollects = 0;
  bool _hasReachedEof = false;
  bool _hasFetchedInitial = false;
  bool _isFirstSegmentPlayed = false;
  bool _skipGetHereOnNextSpeak = false;

  bool _isPrefetcherRunning = false;
  Completer<void>? _prefetcherCompleter;

  bool _isPlayerRunning = false;
  Completer<void>? _playerCompleter;
  Completer<void>? _playbackCompleter;
  Completer<void>? _activeStopCompleter;

  Function? getHereFunction;
  Function? getNextTextFunction;
  Function? getPrevTextFunction;
  bool isInit = false;
  bool _shouldStop = false;

  LocalTtsProvider _provider = LocalTtsProvider();
  LocalVoiceModelManager _modelManager = LocalVoiceModelManager();

  LocalTtsProvider get provider => _provider;

  @visibleForTesting
  set providerForTesting(LocalTtsProvider testProvider) =>
      _provider = testProvider;

  LocalVoiceModelManager get modelManager => _modelManager;

  set modelManager(LocalVoiceModelManager manager) => _modelManager = manager;

  @visibleForTesting
  set modelManagerForTesting(LocalVoiceModelManager manager) =>
      _modelManager = manager;

  @visibleForTesting
  TtsDetailCollector? detailCollectorForTesting;

  @visibleForTesting
  TtsCfiHighlighter? cfiHighlighterForTesting;

  @visibleForTesting
  TtsNextSectionHandler? nextSectionHandlerForTesting;

  @override
  final ValueNotifier<TtsStateEnum> ttsStateNotifier =
      ValueNotifier<TtsStateEnum>(TtsStateEnum.stopped);

  @override
  void updateTtsState(TtsStateEnum newState) {
    ttsStateNotifier.value = newState;
  }

  @visibleForTesting
  double? volumeOverrideForTesting;

  @visibleForTesting
  double? pitchOverrideForTesting;

  @visibleForTesting
  double? rateOverrideForTesting;

  @visibleForTesting
  BaseTts? systemTtsForTesting;

  @override
  double get volume {
    if (volumeOverrideForTesting != null) return volumeOverrideForTesting!;
    try {
      return Prefs().ttsVolume;
    } catch (_) {
      return 1.0;
    }
  }

  @override
  set volume(double volume) {
    if (volumeOverrideForTesting != null) {
      volumeOverrideForTesting = volume;
    }
    try {
      Prefs().ttsVolume = volume;
    } catch (_) {}
    _player?.setVolume(volume);
  }

  @override
  double get pitch {
    if (pitchOverrideForTesting != null) return pitchOverrideForTesting!;
    try {
      return Prefs().ttsPitch;
    } catch (_) {
      return 1.0;
    }
  }

  @override
  set pitch(double pitch) {
    if (pitchOverrideForTesting != null) {
      pitchOverrideForTesting = pitch;
    }
    try {
      Prefs().ttsPitch = pitch;
    } catch (_) {}
    _clearPendingAudio();
  }

  @override
  double get rate {
    if (rateOverrideForTesting != null) return rateOverrideForTesting!;
    try {
      return Prefs().ttsRate;
    } catch (_) {
      return 1.0;
    }
  }

  @override
  set rate(double rate) {
    if (rateOverrideForTesting != null) {
      rateOverrideForTesting = rate;
    }
    try {
      Prefs().ttsRate = rate;
    } catch (_) {}
    _clearPendingAudio();
  }

  @override
  bool get isPlaying => ttsStateNotifier.value == TtsStateEnum.playing;

  @override
  String? get currentVoiceText => _currentVoiceText;

  @override
  Future<List<TtsVoice>> getVoices() async {
    return await provider.getVoices();
  }

  @override
  Future<void> init(
    Function getCurrentText,
    Function getNextText,
    Function getPrevText,
  ) async {
    getHereFunction = getCurrentText;
    getNextTextFunction = getNextText;
    getPrevTextFunction = getPrevText;
    isInit = true;
  }

  AudioPlayer get audioPlayer {
    if (_player == null) {
      _player = AudioPlayer();
      try {
        _player!.setVolume(volume);
      } catch (_) {}
      _playerCompleteSubscription = _player!.onPlayerComplete.listen((_) {
        if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
          _playbackCompleter!.complete();
        }
      });
    }
    return _player!;
  }

  void _clearPendingAudio() {
    _audioFetchVersion++;
    for (final segment in _buffer) {
      segment.audio = null;
      segment.fetchVersion = _audioFetchVersion;
    }
  }

  void _resetBuffer() {
    _buffer.clear();
    _bufferKeys.clear();
    _currentSegment = null;
    _currentVoiceText = null;
    _consecutiveEmptyCount = 0;
    _consecutiveEmptyCollects = 0;
    _hasReachedEof = false;
    _hasFetchedInitial = false;
    _isFirstSegmentPlayed = false;
  }

  Future<void> _disposePlayer() async {
    final playerToDispose = _player;
    final subToCancel = _playerCompleteSubscription;
    _player = null;
    _playerCompleteSubscription = null;

    if (subToCancel != null) {
      try {
        await subToCancel.cancel();
      } catch (_) {}
    }

    if (playerToDispose != null) {
      try {
        await playerToDispose.stop();
      } catch (_) {}
      try {
        await playerToDispose.dispose();
      } catch (_) {}
    }
  }

  /// Parses raw returned sentence object into a valid [TtsSentence].
  TtsSentence _parseSentence(dynamic raw) {
    if (raw == null) {
      return const TtsSentence(text: '', cfi: null);
    }
    if (raw is TtsSentence) {
      return raw;
    }
    if (raw is Map<dynamic, dynamic>) {
      try {
        return TtsSentence.fromMap(raw);
      } catch (_) {
        final text = raw['text']?.toString() ?? '';
        final cfi = raw['cfi'] is String && (raw['cfi'] as String).isNotEmpty
            ? raw['cfi'] as String
            : null;
        return TtsSentence(text: text, cfi: cfi);
      }
    }
    if (raw is String) {
      return TtsSentence(text: raw, cfi: null);
    }
    return TtsSentence(text: raw.toString(), cfi: null);
  }

  bool _isAlreadyBuffered(TtsSentence sentence) {
    final cfi = sentence.cfi;
    if (cfi != null && cfi.isNotEmpty) {
      if (_currentSegment?.sentence.cfi == cfi) return true;
      return _buffer.any((s) => s.sentence.cfi == cfi);
    }
    // When CFI is absent, do not use text.hashCode as a global unique identifier.
    // Allow duplicate text sentences to play in queue order.
    return false;
  }

  /// Collects sentences from the active reader or injected test collector
  /// without modifying the reader cursor or triggering DOM highlights.
  Future<List<TtsSentence>> _collectSentences(int count) async {
    final isFirst = !_hasFetchedInitial;
    final offset = isFirst ? 1 : (_buffer.isEmpty ? 1 : _buffer.length + 1);

    if (detailCollectorForTesting != null) {
      return await detailCollectorForTesting!(
        count: count,
        includeCurrent: isFirst,
        offset: offset,
      );
    }

    final state = epubPlayerKey.currentState;
    if (state == null) {
      return [];
    }

    try {
      final sentences = await state.ttsCollectDetails(
        count: count,
        includeCurrent: isFirst,
        offset: offset,
      );
      return sentences;
    } catch (e) {
      AnxLog.severe('Local TTS collect details error: $e');
      return [];
    }
  }

  Future<String?> _advanceNextSection() async {
    if (nextSectionHandlerForTesting != null) {
      return await nextSectionHandlerForTesting!();
    }
    final state = epubPlayerKey.currentState;
    if (state == null) return null;
    try {
      return await state.ttsNextSection();
    } catch (e) {
      AnxLog.warning('Local TTS next section error: $e');
      return null;
    }
  }

  /// Producer: Sequentially peeks upcoming sentences and enqueues them for synthesis.
  /// Never calls [getNextTextFunction] during prefetch to prevent cursor desync and DOM jumping.
  Future<void> _startPrefetcher() async {
    if (_isPrefetcherRunning) return;
    _isPrefetcherRunning = true;
    _shouldStop = false;
    _prefetcherCompleter = Completer<void>();

    try {
      while (!_shouldStop && !_hasReachedEof) {
        if (_buffer.length >= _bufferCapacity) {
          await Future.delayed(const Duration(milliseconds: 50));
          continue;
        }

        final neededCount = _bufferCapacity - _buffer.length;
        if (neededCount <= 0) {
          await Future.delayed(const Duration(milliseconds: 50));
          continue;
        }

        final sentences = await _collectSentences(neededCount);
        if (_shouldStop) break;

        final newSentences = <TtsSentence>[];
        for (final s in sentences) {
          if (!_isAlreadyBuffered(s)) {
            newSentences.add(s);
          }
        }

        if (newSentences.isEmpty) {
          // If buffer is completely drained and no sentence returned, advance section
          if (_buffer.isEmpty && _currentSegment == null) {
            _consecutiveEmptyCollects++;
            if (_consecutiveEmptyCollects >= _maxConsecutiveEmptyCollects) {
              final nextSec = await _advanceNextSection();
              if (nextSec == null || nextSec.isEmpty) {
                _consecutiveEmptyCount++;
                if (_consecutiveEmptyCount >= _maxConsecutiveEmpty) {
                  AnxLog.info('Local TTS reached EOF: no more sentences or sections');
                  _hasReachedEof = true;
                  _buffer.add(_eofSegment);
                  break;
                }
              } else {
                _consecutiveEmptyCount = 0;
                _consecutiveEmptyCollects = 0;
                _hasFetchedInitial = false;
              }
            }
          }
          await Future.delayed(const Duration(milliseconds: 100));
          continue;
        }

        _consecutiveEmptyCount = 0;
        _consecutiveEmptyCollects = 0;
        _hasFetchedInitial = true;

        for (final sentence in newSentences) {
          if (_shouldStop) break;
          if (sentence.text.trim().isEmpty) {
            continue;
          }

          final segment = TtsSegment(sentence: sentence)
            ..fetchVersion = _audioFetchVersion;
          _buffer.add(segment);

          // Strictly serial synthesis: synthesize one segment at a time
          await _fetchAudioForSegment(segment);
        }
      }
    } catch (e) {
      AnxLog.severe('Local TTS prefetcher error: $e');
    } finally {
      _isPrefetcherRunning = false;
      if (_prefetcherCompleter != null && !_prefetcherCompleter!.isCompleted) {
        _prefetcherCompleter!.complete();
      }
      _prefetcherCompleter = null;
    }
  }

  Future<void> _fetchAudioForSegment(TtsSegment segment) async {
    final version = segment.fetchVersion;
    try {
      final audio = await provider
          .speak(segment.sentence.text, null, rate, pitch)
          .timeout(const Duration(seconds: _fetchTimeoutSeconds));

      if (segment.fetchVersion == version && !_shouldStop) {
        if (audio.isEmpty) {
          segment.isSilent = true;
        } else {
          segment.audio = audio;
        }
      }
    } catch (e) {
      AnxLog.warning('Local TTS synthesis segment error: $e');
      if (segment.fetchVersion == version) {
        segment.isSilent = true; // Skip failed segment gracefully
      }
    }
  }

  /// Internal teardown when player finishes naturally (EOF) or terminates.
  Future<void> _teardownOnEof() async {
    _shouldStop = true;
    updateTtsState(TtsStateEnum.stopped);

    try {
      if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
        _playbackCompleter!.complete();
      }

      // Wait for the background prefetcher loop to finish if still active
      if (_prefetcherCompleter != null) {
        try {
          await _prefetcherCompleter!.future
              .timeout(const Duration(seconds: 1), onTimeout: () {});
        } catch (_) {}
      }

      await _disposePlayer();
    } finally {
      _resetBuffer();
      updateTtsState(TtsStateEnum.stopped);
    }
  }

  /// Consumer: Sequentially consumes buffered segments and plays audio.
  /// Sets DOM highlight right before starting audio playback for that segment.
  /// Never calls [getNextTextFunction], keeping reading highlight in exact sync with audio.
  Future<void> _startPlayer() async {
    if (_isPlayerRunning) return;
    _isPlayerRunning = true;
    _shouldStop = false;
    _playerCompleter = Completer<void>();

    try {
      while (!_shouldStop) {
        while (_buffer.isEmpty && !_shouldStop) {
          if (_hasReachedEof) {
            // All buffered sentences have completed and EOF reached
            await _teardownOnEof();
            return;
          }
          await Future.delayed(const Duration(milliseconds: 30));
        }
        if (_shouldStop) break;

        final segment = _buffer.first;
        if (identical(segment, _eofSegment)) {
          _buffer.removeAt(0);
          await _teardownOnEof();
          break;
        }

        while (!segment.isReady && !_shouldStop) {
          await Future.delayed(const Duration(milliseconds: 30));
        }
        if (_shouldStop) break;

        _buffer.removeAt(0);
        _currentSegment = segment;
        _currentVoiceText = segment.sentence.text;

        // Highlight segment synchronously right before audio starts
        await _highlightSegment(segment);

        if (segment.isSilent ||
            segment.audio == null ||
            segment.audio!.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 100));
          _currentSegment = null;
          continue;
        }

        final player = audioPlayer;
        _playbackCompleter = Completer<void>();
        final mimeType = WavEncoder.detectAudioMimeType(segment.audio!);
        final source = BytesSource(segment.audio!, mimeType: mimeType);

        try {
          await player.play(source);
          await _playbackCompleter!.future;
        } catch (e) {
          AnxLog.severe('Local TTS audio playback error: $e');
        }

        _playbackCompleter = null;
        _currentSegment = null;

        // Note: We do NOT call getNextTextFunction here.
        // Advancing cursor/highlight occurs strictly when the next segment begins.
      }
    } catch (e) {
      AnxLog.severe('Local TTS player loop error: $e');
      await _teardownOnEof();
    } finally {
      _isPlayerRunning = false;
      if (ttsStateNotifier.value == TtsStateEnum.playing) {
        updateTtsState(TtsStateEnum.stopped);
      }
      if (_playerCompleter != null && !_playerCompleter!.isCompleted) {
        _playerCompleter!.complete();
      }
      _playerCompleter = null;
    }
  }

  Future<void> _highlightSegment(TtsSegment segment) async {
    final cfi = segment.sentence.cfi;
    if (cfi != null && cfi.isNotEmpty) {
      if (cfiHighlighterForTesting != null) {
        await cfiHighlighterForTesting!(cfi);
        return;
      }

      final state = epubPlayerKey.currentState;
      if (state == null) return;
      try {
        await state.ttsHighlightByCfi(cfi);
      } catch (_) {}
      return;
    }

    if (_isFirstSegmentPlayed) {
      try {
        await getNextTextFunction?.call();
      } catch (_) {}
    } else {
      _isFirstSegmentPlayed = true;
    }
  }

  @override
  Future<void> speak({String? content}) async {
    // If specific content provided (e.g. preview text)
    if (content != null && content.isNotEmpty) {
      await speakPreview(content);
      return;
    }

    if (!isInit) {
      throw StateError('离线自然朗读未初始化阅读回调');
    }

    final isInstalled =
        await modelManager.isModelInstalled(LocalVoiceModel.defaultChineseModel);
    if (!isInstalled) {
      AnxLog.warning(
          'Local TTS model not installed, falling back to System TTS');
      final systemTts = systemTtsForTesting ?? SystemTts();
      if (getHereFunction != null &&
          getNextTextFunction != null &&
          getPrevTextFunction != null) {
        await systemTts.init(
          getHereFunction!,
          getNextTextFunction!,
          getPrevTextFunction!,
        );
        await systemTts.speak();
        return;
      }
      throw StateError('离线自然朗读声音包尚未安装，且未初始化阅读回调');
    }

    _shouldStop = false;
    _hasReachedEof = false;
    _consecutiveEmptyCount = 0;
    _consecutiveEmptyCollects = 0;
    updateTtsState(TtsStateEnum.playing);

    final skipGetHere = _skipGetHereOnNextSpeak;
    _skipGetHereOnNextSpeak = false;

    if (!skipGetHere) {
      try {
        await getHereFunction?.call();
      } catch (_) {}
    }

    unawaited(_startPrefetcher());
    await _startPlayer();
  }

  /// Synthesizes and plays preview audio for settings or test buttons.
  Future<void> speakPreview(String text, {String? voice}) async {
    await stop();

    final isInstalled =
        await modelManager.isModelInstalled(LocalVoiceModel.defaultChineseModel);
    if (!isInstalled) {
      AnxLog.warning(
          'Local TTS model not installed for preview, falling back to System TTS');
      final systemTts = systemTtsForTesting ?? SystemTts();
      await systemTts.speak(content: text);
      return;
    }

    try {
      final audio = await provider.speak(text, voice, rate, pitch);
      if (audio.isNotEmpty) {
        _shouldStop = false;
        updateTtsState(TtsStateEnum.playing);
        _playbackCompleter = Completer<void>();
        final mimeType = WavEncoder.detectAudioMimeType(audio);
        final source = BytesSource(audio, mimeType: mimeType);

        try {
          await audioPlayer.play(source);
          await _playbackCompleter!.future;
        } catch (e) {
          AnxLog.severe('Local TTS preview playback error: $e');
        } finally {
          _playbackCompleter = null;
          updateTtsState(TtsStateEnum.stopped);
        }
      } else {
        updateTtsState(TtsStateEnum.stopped);
      }
    } catch (e) {
      AnxLog.severe('Local TTS preview error: $e');
      updateTtsState(TtsStateEnum.stopped);
    }
  }

  @override
  Future<dynamic> stop() async {
    if (_activeStopCompleter != null) {
      return _activeStopCompleter!.future;
    }

    final stopCompleter = Completer<void>();
    _activeStopCompleter = stopCompleter;

    try {
      _shouldStop = true;
      _skipGetHereOnNextSpeak = false;
      updateTtsState(TtsStateEnum.stopped);

      if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
        _playbackCompleter!.complete();
      }

      await _prefetcherCompleter?.future;
      await _playerCompleter?.future;

      await _disposePlayer();
      _resetBuffer();
    } finally {
      if (!stopCompleter.isCompleted) {
        stopCompleter.complete();
      }
      if (_activeStopCompleter == stopCompleter) {
        _activeStopCompleter = null;
      }
    }
  }

  @override
  Future<void> pause() async {
    updateTtsState(TtsStateEnum.paused);
    await _player?.pause();
  }

  @override
  Future<void> resume() async {
    updateTtsState(TtsStateEnum.playing);
    await _player?.resume();
  }

  @override
  Future<void> prev() async {
    if (!isInit) return;
    await stop();
    try {
      await getPrevTextFunction?.call();
    } catch (_) {}
    _skipGetHereOnNextSpeak = true;
    await speak();
  }

  @override
  Future<void> next() async {
    if (!isInit) return;
    await stop();
    try {
      await getNextTextFunction?.call();
    } catch (_) {}
    _skipGetHereOnNextSpeak = true;
    await speak();
  }

  @override
  Future<void> restart() async {
    if (!isInit) return;
    await stop();
    await speak();
  }

  @override
  Future<void> dispose() async {
    await stop();
    isInit = false;
    getHereFunction = null;
    getNextTextFunction = null;
    getPrevTextFunction = null;
    detailCollectorForTesting = null;
    cfiHighlighterForTesting = null;
    nextSectionHandlerForTesting = null;
    systemTtsForTesting = null;
    volumeOverrideForTesting = null;
    pitchOverrideForTesting = null;
    rateOverrideForTesting = null;
    await provider.dispose();
  }

  @visibleForTesting
  static TtsSegment get eofSegment => _eofSegment;

  @visibleForTesting
  List<TtsSegment> get bufferForTesting => _buffer;

  @visibleForTesting
  Set<String> get bufferKeysForTesting => _bufferKeys;

  @visibleForTesting
  bool get hasReachedEofForTesting => _hasReachedEof;

  @visibleForTesting
  set hasReachedEofForTesting(bool value) => _hasReachedEof = value;

  @visibleForTesting
  bool get isPlayerRunningForTesting => _isPlayerRunning;

  @visibleForTesting
  bool get isPrefetcherRunningForTesting => _isPrefetcherRunning;

  @visibleForTesting
  Completer<void>? get playerCompleterForTesting => _playerCompleter;

  @visibleForTesting
  Completer<void>? get prefetcherCompleterForTesting => _prefetcherCompleter;

  @visibleForTesting
  Completer<void>? get activeStopCompleterForTesting => _activeStopCompleter;

  @visibleForTesting
  bool get shouldStopForTesting => _shouldStop;

  @visibleForTesting
  set shouldStopForTesting(bool value) => _shouldStop = value;

  @visibleForTesting
  Future<void> teardownOnEofForTesting() => _teardownOnEof();

  @visibleForTesting
  Future<void> startPlayerForTesting() {
    _shouldStop = false;
    return _startPlayer();
  }

  @visibleForTesting
  Future<void> startPrefetcherForTesting() {
    _shouldStop = false;
    return _startPrefetcher();
  }

  @visibleForTesting
  void resetBufferForTesting() => _resetBuffer();

  @visibleForTesting
  Future<void> fetchAudioForSegmentForTesting(TtsSegment segment) =>
      _fetchAudioForSegment(segment);
}
