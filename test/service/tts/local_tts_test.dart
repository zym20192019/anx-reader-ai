import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/local_tts/local_tts.dart';
import 'package:anx_reader/service/tts/local_tts/local_tts_engine.dart';
import 'package:anx_reader/service/tts/local_tts/local_tts_provider.dart';
import 'package:anx_reader/service/tts/local_tts/local_voice_model.dart';
import 'package:anx_reader/service/tts/local_tts/local_voice_model_manager.dart';
import 'package:anx_reader/service/tts/models/tts_segment.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSystemTts extends BaseTts {
  bool initCalled = false;
  bool speakCalled = false;
  String? lastSpokenContent;

  @override
  final ValueNotifier<TtsStateEnum> ttsStateNotifier =
      ValueNotifier<TtsStateEnum>(TtsStateEnum.stopped);

  @override
  void updateTtsState(TtsStateEnum newState) {
    ttsStateNotifier.value = newState;
  }

  @override
  double get volume => 1.0;
  @override
  set volume(double volume) {}
  @override
  double get pitch => 1.0;
  @override
  set pitch(double pitch) {}
  @override
  double get rate => 1.0;
  @override
  set rate(double rate) {}

  @override
  Future<void> init(
    Function getCurrentText,
    Function getNextText,
    Function getPrevText,
  ) async {
    initCalled = true;
  }

  @override
  Future<void> speak({String? content}) async {
    speakCalled = true;
    lastSpokenContent = content;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> prev() async {}
  @override
  Future<void> restart() async {}
  @override
  Future<void> dispose() async {}
}

class MockLocalTtsEngine implements LocalTtsEngine {
  int activeConcurrentSyntheses = 0;
  int maxObservedConcurrency = 0;
  int synthesizeCallCount = 0;
  final Duration delay;

  MockLocalTtsEngine({this.delay = const Duration(milliseconds: 20)});

  @override
  bool get isAvailable => true;

  @override
  Future<void> init({
    required String modelDir,
    required LocalVoiceModel model,
  }) async {}

  @override
  Future<Uint8List> synthesize(
    String text, {
    double speed = 1.0,
    int speakerId = 0,
  }) async {
    synthesizeCallCount++;
    activeConcurrentSyntheses++;
    if (activeConcurrentSyntheses > maxObservedConcurrency) {
      maxObservedConcurrency = activeConcurrentSyntheses;
    }
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    activeConcurrentSyntheses--;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> dispose() async {}
}

class ControllableMockEngine implements LocalTtsEngine {
  bool _available = true;
  final List<Completer<Uint8List>> activeCompleters = [];
  int synthesizeCallCount = 0;

  @override
  bool get isAvailable => _available;

  @override
  Future<void> init({
    required String modelDir,
    required LocalVoiceModel model,
  }) async {
    _available = true;
  }

  @override
  Future<Uint8List> synthesize(
    String text, {
    double speed = 1.0,
    int speakerId = 0,
  }) {
    synthesizeCallCount++;
    final completer = Completer<Uint8List>();
    activeCompleters.add(completer);
    return completer.future;
  }

  @override
  Future<void> dispose() async {
    _available = false;
    for (final c in activeCompleters) {
      if (!c.isCompleted) {
        c.completeError(StateError('Engine disposed'));
      }
    }
    activeCompleters.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testTempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'awaitSpeakCompletion':
        case 'awaitSynthCompletion':
        case 'setQueueMode':
        case 'setVolume':
        case 'setSpeechRate':
        case 'setPitch':
        case 'speak':
        case 'stop':
        case 'pause':
          return 1;
        case 'getEngines':
          return <String>[];
        case 'getDefaultEngine':
          return 'default';
        case 'getDefaultVoice':
          return <String, String>{'name': 'default', 'locale': 'zh-CN'};
        case 'getVoices':
          return <dynamic>[];
        default:
          return null;
      }
    });
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    testTempDir = Directory.systemTemp.createTempSync('anx_local_tts_test_');

    final modelDir = Directory(
      '${testTempDir.path}/tts_models/${LocalVoiceModel.defaultChineseModel.id}',
    )..createSync(recursive: true);
    for (final filename in LocalVoiceModel.defaultChineseModel.requiredFiles) {
      File('${modelDir.path}/$filename').writeAsStringSync('dummy');
    }

    final localTts = LocalTts(
      modelManager: LocalVoiceModelManager.withDirs(
        getBaseDir: () async => testTempDir,
        getTempDir: () async => testTempDir,
      ),
    );
    await localTts.stop();
    localTts.isInit = false;
    localTts.volumeOverrideForTesting = 1.0;
    localTts.pitchOverrideForTesting = 1.0;
    localTts.rateOverrideForTesting = 1.0;
    localTts.systemTtsForTesting = null;
    localTts.getHereFunction = null;
    localTts.getNextTextFunction = null;
    localTts.getPrevTextFunction = null;
    localTts.detailCollectorForTesting = null;
    localTts.cfiHighlighterForTesting = null;
    localTts.nextSectionHandlerForTesting = null;
    localTts.providerForTesting = LocalTtsProvider();
    localTts.hasReachedEofForTesting = false;
  });

  tearDown(() async {
    final localTts = LocalTts();
    await localTts.stop();
    localTts.isInit = false;
    localTts.volumeOverrideForTesting = null;
    localTts.pitchOverrideForTesting = null;
    localTts.rateOverrideForTesting = null;
    localTts.systemTtsForTesting = null;
    localTts.getHereFunction = null;
    localTts.getNextTextFunction = null;
    localTts.getPrevTextFunction = null;
    localTts.detailCollectorForTesting = null;
    localTts.cfiHighlighterForTesting = null;
    localTts.nextSectionHandlerForTesting = null;
    localTts.providerForTesting = LocalTtsProvider();
    localTts.hasReachedEofForTesting = false;
    localTts.modelManager = LocalVoiceModelManager();
    if (testTempDir.existsSync()) {
      try {
        testTempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('LocalTts Sentence Parsing & Contract', () {
    test(
        'constructs valid TtsSentence without fake cfi for pure String callbacks',
        () {
      const sentence = TtsSentence(text: '测试第一句', cfi: null);
      expect(sentence.text, equals('测试第一句'));
      expect(sentence.cfi, isNull);

      final fromMap =
          TtsSentence.fromMap({'text': '测试第二句', 'cfi': 'epubcfi(/6/2)'});
      expect(fromMap.text, equals('测试第二句'));
      expect(fromMap.cfi, equals('epubcfi(/6/2)'));
    });
  });

  group('LocalTtsProvider Lifecycle & Singleton', () {
    test('LocalTtsProvider factory returns identical singleton instance', () {
      final p1 = LocalTtsProvider();
      final p2 = LocalTtsProvider();
      expect(identical(p1, p2), isTrue);
    });
  });

  group('LocalTts Safety & Fallback', () {
    test(
        'speak throws descriptive StateError when model is uninstalled and not initialized',
        () async {
      final localTts = LocalTts();
      localTts.isInit = false;
      localTts.getHereFunction = null;
      localTts.getNextTextFunction = null;
      localTts.getPrevTextFunction = null;

      await expectLater(
        localTts.speak(),
        throwsA(isA<StateError>()),
      );
    });

    test('dispose resets isInit and stops playback', () async {
      final localTts = LocalTts();
      localTts.isInit = true;

      await localTts.dispose();

      expect(localTts.isInit, isFalse);
      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
    });
  });

  group('LocalTts Uninitialized Safety (prev / next / restart)', () {
    test('prev does not throw LateInitializationError when uninitialized',
        () async {
      final localTts = LocalTts();
      localTts.isInit = false;
      localTts.getPrevTextFunction = null;

      await expectLater(
        localTts.prev(),
        completes,
      );
      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
    });

    test('next does not throw LateInitializationError when uninitialized',
        () async {
      final localTts = LocalTts();
      localTts.isInit = false;
      localTts.getNextTextFunction = null;

      await expectLater(
        localTts.next(),
        completes,
      );
      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
    });

    test('restart does not throw LateInitializationError when uninitialized',
        () async {
      final localTts = LocalTts();
      localTts.isInit = false;

      await expectLater(
        localTts.restart(),
        completes,
      );
      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
    });

    test('init binds reading callbacks and enables isInit', () async {
      final localTts = LocalTts();
      var hereCalled = false;
      var nextCalled = false;
      var prevCalled = false;

      await localTts.init(
        () {
          hereCalled = true;
        },
        () {
          nextCalled = true;
        },
        () {
          prevCalled = true;
        },
      );

      expect(localTts.isInit, isTrue);
      expect(localTts.getHereFunction, isNotNull);
      expect(localTts.getNextTextFunction, isNotNull);
      expect(localTts.getPrevTextFunction, isNotNull);

      localTts.getHereFunction!();
      localTts.getNextTextFunction!();
      localTts.getPrevTextFunction!();

      expect(hereCalled, isTrue);
      expect(nextCalled, isTrue);
      expect(prevCalled, isTrue);

      await localTts.dispose();
      expect(localTts.isInit, isFalse);
      expect(localTts.getHereFunction, isNull);
      expect(localTts.getNextTextFunction, isNull);
      expect(localTts.getPrevTextFunction, isNull);
    });
  });

  group('LocalTts Stop & Concurrency Safety', () {
    test('stop on idle state returns cleanly and immediately', () async {
      final localTts = LocalTts();
      await localTts.stop().timeout(const Duration(seconds: 2));

      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
      expect(localTts.activeStopCompleterForTesting, isNull);
    });

    test('concurrent stop calls deduplicate and avoid reentrancy deadlock',
        () async {
      final localTts = LocalTts();

      final futures = List.generate(5, (_) => localTts.stop());
      await Future.wait(futures).timeout(const Duration(seconds: 2));

      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
      expect(localTts.activeStopCompleterForTesting, isNull);
    });

    test('external stop halts active player loop waiting in buffer', () async {
      final localTts = LocalTts();
      await localTts.stop();

      localTts.hasReachedEofForTesting = false;
      localTts.updateTtsState(TtsStateEnum.playing);
      final playerFuture = localTts.startPlayerForTesting();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(localTts.isPlayerRunningForTesting, isTrue);

      // Trigger external stop
      await localTts.stop().timeout(const Duration(seconds: 2));

      // Player loop must exit promptly
      await playerFuture.timeout(const Duration(seconds: 2));

      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
      expect(localTts.isPlayerRunningForTesting, isFalse);
    });
  });

  group('LocalTts EOF Non-Deadlock Teardown', () {
    test(
        '_startPlayer reaches EOF on empty buffer and completes without self-await deadlock',
        () async {
      final localTts = LocalTts();
      await localTts.stop();

      // Configure player loop to encounter EOF immediately
      localTts.hasReachedEofForTesting = true;
      localTts.updateTtsState(TtsStateEnum.playing);

      await localTts
          .startPlayerForTesting()
          .timeout(const Duration(seconds: 2));

      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
      expect(localTts.isPlayerRunningForTesting, isFalse);
      expect(localTts.bufferForTesting, isEmpty);

      // Subsequent external stop must also return immediately
      await localTts.stop().timeout(const Duration(seconds: 2));
    });

    test('_startPlayer completes naturally when buffer contains eofSegment',
        () async {
      final localTts = LocalTts();
      await localTts.stop();

      // Buffer contains eofSegment marker
      localTts.bufferForTesting.add(LocalTts.eofSegment);
      localTts.updateTtsState(TtsStateEnum.playing);

      await localTts
          .startPlayerForTesting()
          .timeout(const Duration(seconds: 2));

      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
      expect(localTts.isPlayerRunningForTesting, isFalse);
      expect(localTts.bufferForTesting, isEmpty);
    });

    test('teardownOnEof directly cleans up resources without deadlock',
        () async {
      final localTts = LocalTts();
      localTts.updateTtsState(TtsStateEnum.playing);

      await localTts
          .teardownOnEofForTesting()
          .timeout(const Duration(seconds: 2));

      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
      expect(localTts.bufferForTesting, isEmpty);
    });
  });

  group('LocalTts State Transitions & Preview Lifecycle', () {
    test('pause and resume transition states accurately', () async {
      final localTts = LocalTts();
      await localTts.stop();

      await localTts.pause();
      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.paused));

      await localTts.resume();
      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.playing));

      await localTts.stop();
      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
    });

    test(
        'speakPreview recovers to stopped state when model uninstalled or on error',
        () async {
      final localTts = LocalTts();
      await localTts.stop();

      try {
        await localTts.speakPreview('试听语音测试内容');
      } catch (_) {}

      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
    });
  });

  group('LocalTts Prefetch & Cursor Invariance', () {
    test(
        'prefetcher collects sentences via detailCollector without calling getNextTextFunction',
        () async {
      final localTts = LocalTts();
      int getNextCalledCount = 0;
      localTts.getNextTextFunction = () {
        getNextCalledCount++;
        return 'next_sentence';
      };

      final testSentences = [
        const TtsSentence(text: '第一句文本', cfi: 'epubcfi(/6/2[chap1]!/4/1)'),
        const TtsSentence(text: '第二句文本', cfi: 'epubcfi(/6/2[chap1]!/4/2)'),
      ];

      localTts.detailCollectorForTesting = ({
        required int count,
        bool includeCurrent = false,
        int offset = 1,
      }) async {
        return testSentences;
      };

      final mockEngine = MockLocalTtsEngine(delay: Duration.zero);
      localTts.providerForTesting =
          LocalTtsProvider.withEngine(engine: mockEngine);

      final prefetcherFuture = localTts.startPrefetcherForTesting();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      localTts.shouldStopForTesting = true;
      await prefetcherFuture;

      expect(getNextCalledCount, equals(0),
          reason:
              'Prefetcher must never call getNextTextFunction (cursor advance callback)');
      expect(localTts.bufferForTesting.length, equals(2));
      expect(localTts.bufferForTesting[0].sentence.cfi,
          equals('epubcfi(/6/2[chap1]!/4/1)'));
      expect(localTts.bufferForTesting[1].sentence.cfi,
          equals('epubcfi(/6/2[chap1]!/4/2)'));
    });

    test('collected segments strictly retain CFI metadata from TtsSentence',
        () async {
      final localTts = LocalTts();
      const sentenceWithCfi = TtsSentence(
        text: '带CFI的句子',
        cfi: 'epubcfi(/6/12[c03]!/4/2/14/1:0)',
      );

      localTts.detailCollectorForTesting = ({
        required int count,
        bool includeCurrent = false,
        int offset = 1,
      }) async {
        return [sentenceWithCfi];
      };

      final mockEngine = MockLocalTtsEngine(delay: Duration.zero);
      localTts.providerForTesting =
          LocalTtsProvider.withEngine(engine: mockEngine);

      final prefetcherFuture = localTts.startPrefetcherForTesting();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      localTts.shouldStopForTesting = true;
      await prefetcherFuture;

      expect(localTts.bufferForTesting.isNotEmpty, isTrue);
      final segment = localTts.bufferForTesting.first;
      expect(segment.sentence.text, equals('带CFI的句子'));
      expect(segment.sentence.cfi, equals('epubcfi(/6/12[c03]!/4/2/14/1:0)'));
    });

    test(
        'initial prefetch requests includeCurrent: true preserving first sentence',
        () async {
      final localTts = LocalTts();
      bool? capturedIncludeCurrent;
      int? capturedOffset;

      localTts.detailCollectorForTesting = ({
        required int count,
        bool includeCurrent = false,
        int offset = 1,
      }) async {
        capturedIncludeCurrent = includeCurrent;
        capturedOffset = offset;
        return [
          const TtsSentence(text: '首句内容', cfi: 'cfi_first'),
        ];
      };

      final mockEngine = MockLocalTtsEngine(delay: Duration.zero);
      localTts.providerForTesting =
          LocalTtsProvider.withEngine(engine: mockEngine);

      final prefetcherFuture = localTts.startPrefetcherForTesting();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      localTts.shouldStopForTesting = true;
      await prefetcherFuture;

      expect(capturedIncludeCurrent, isTrue,
          reason:
              'Initial fetch with empty buffer must include current sentence');
      expect(capturedOffset, equals(1));
      expect(localTts.bufferForTesting.first.sentence.text, equals('首句内容'));
      expect(localTts.bufferForTesting.first.sentence.cfi, equals('cfi_first'));
    });
  });

  group('LocalTts Concurrency & Buffer Boundary', () {
    test(
        'synthesis is strictly serialized with max concurrency 1 and buffer capacity <= 2',
        () async {
      final localTts = LocalTts();
      int sentenceIndex = 0;
      final sentences = List.generate(
        6,
        (i) => TtsSentence(text: '句子 $i', cfi: 'cfi_$i'),
      );

      localTts.detailCollectorForTesting = ({
        required int count,
        bool includeCurrent = false,
        int offset = 1,
      }) async {
        if (sentenceIndex < sentences.length) {
          final s = sentences[sentenceIndex++];
          return [s];
        }
        return [];
      };

      final mockEngine =
          MockLocalTtsEngine(delay: const Duration(milliseconds: 30));
      localTts.providerForTesting =
          LocalTtsProvider.withEngine(engine: mockEngine);

      final prefetcherFuture = localTts.startPrefetcherForTesting();

      // Let prefetcher run through multiple sentences
      await Future<void>.delayed(const Duration(milliseconds: 120));
      localTts.shouldStopForTesting = true;
      await prefetcherFuture;

      expect(mockEngine.maxObservedConcurrency, equals(1),
          reason:
              'Audio synthesis must never run concurrently across multiple requests');
      expect(localTts.bufferForTesting.length, lessThanOrEqualTo(2),
          reason:
              'Buffer capacity must be constrained to at most 2 to prevent memory/CPU storm');
    });
  });

  group('LocalTts Playback Highlight Synchronization', () {
    test(
        'cfi highlight occurs before segment playback without rushing ahead',
        () async {
      final localTts = LocalTts();
      final events = <String>[];

      localTts.cfiHighlighterForTesting = (cfi) async {
        events.add('highlight:$cfi');
      };

      // Add 2 silent segments with CFIs to buffer to test player loop without real audio driver
      final seg1 = TtsSegment(
        sentence: const TtsSentence(text: '第一句', cfi: 'cfi_seg1'),
      )..isSilent = true;

      final seg2 = TtsSegment(
        sentence: const TtsSentence(text: '第二句', cfi: 'cfi_seg2'),
      )..isSilent = true;

      localTts.bufferForTesting.add(seg1);
      localTts.bufferForTesting.add(seg2);
      localTts.bufferForTesting.add(LocalTts.eofSegment);

      localTts.updateTtsState(TtsStateEnum.playing);
      await localTts.startPlayerForTesting().timeout(const Duration(seconds: 2));

      expect(events, equals(['highlight:cfi_seg1', 'highlight:cfi_seg2']));
    });
  });

  group('LocalTtsEngine Request Management & Lifecycle', () {
    test(
        'synthesize fails immediately with StateError when engine uninitialized',
        () async {
      final engine = SherpaOnnxLocalTtsEngine();
      expect(engine.isAvailable, isFalse);

      await expectLater(
        engine.synthesize('测试未初始化推理'),
        throwsA(isA<StateError>()),
      );
    });

    test('dispose on idle uninitialized engine completes cleanly without leak',
        () async {
      final engine = SherpaOnnxLocalTtsEngine();
      await expectLater(engine.dispose(), completes);
      expect(engine.isAvailable, isFalse);
    });
  });

  group('LocalTtsProvider Shared Future & Safe Error Propagation', () {
    test(
        'concurrent speak calls share same init future and propagate identical error without unhandled exception',
        () async {
      final tempDir =
          Directory.systemTemp.createTempSync('tts_provider_err_test_');
      try {
        final modelManager = LocalVoiceModelManager.withDirs(
          getBaseDir: () async => tempDir,
          getTempDir: () async => tempDir,
        );
        final mockEngine = MockLocalTtsEngine();
        final provider = LocalTtsProvider.withEngine(
          modelManager: modelManager,
          engine: mockEngine,
        );

        final f1 = provider.speak('第一句', null, 1.0, 1.0);
        final f2 = provider.speak('第二句', null, 1.0, 1.0);

        await expectLater(f1, throwsA(isA<StateError>()));
        await expectLater(f2, throwsA(isA<StateError>()));

        await expectLater(
          provider.speak('第三句', null, 1.0, 1.0),
          throwsA(isA<StateError>()),
        );
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });

  group('LocalTts Duplicate Sentences & Non-CFI Progression', () {
    test('duplicate sentences without CFI are both buffered and not skipped',
        () async {
      final localTts = LocalTts();
      final sentences = [
        const TtsSentence(text: '重复句', cfi: null),
        const TtsSentence(text: '重复句', cfi: null),
      ];

      localTts.detailCollectorForTesting = ({
        required int count,
        bool includeCurrent = false,
        int offset = 1,
      }) async {
        return sentences;
      };

      final mockEngine = MockLocalTtsEngine(delay: Duration.zero);
      localTts.providerForTesting =
          LocalTtsProvider.withEngine(engine: mockEngine);

      final prefetcherFuture = localTts.startPrefetcherForTesting();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      localTts.shouldStopForTesting = true;
      await prefetcherFuture;

      expect(localTts.bufferForTesting.length, equals(2),
          reason:
              'Both identical sentences without CFI must be enqueued in queue order');
      expect(localTts.bufferForTesting[0].sentence.text, equals('重复句'));
      expect(localTts.bufferForTesting[1].sentence.text, equals('重复句'));
    });

    test(
        'non-CFI playback advances reader cursor via getNextTextFunction for subsequent sentences',
        () async {
      final localTts = LocalTts();
      int getNextCallCount = 0;
      localTts.getNextTextFunction = () {
        getNextCallCount++;
        return 'advanced';
      };

      final seg1 = TtsSegment(
        sentence: const TtsSentence(text: '第一句无CFI', cfi: null),
      )..isSilent = true;

      final seg2 = TtsSegment(
        sentence: const TtsSentence(text: '第二句无CFI', cfi: null),
      )..isSilent = true;

      localTts.bufferForTesting.add(seg1);
      localTts.bufferForTesting.add(seg2);
      localTts.bufferForTesting.add(LocalTts.eofSegment);

      localTts.updateTtsState(TtsStateEnum.playing);
      await localTts
          .startPlayerForTesting()
          .timeout(const Duration(seconds: 2));

      expect(getNextCallCount, equals(1),
          reason:
              'Second non-CFI segment must advance reader cursor via getNextTextFunction');
    });

    test('CFI playback highlights by CFI and does not invoke getNextTextFunction',
        () async {
      final localTts = LocalTts();
      int getNextCallCount = 0;
      final highlighted = <String>[];

      localTts.getNextTextFunction = () {
        getNextCallCount++;
        return 'advanced';
      };
      localTts.cfiHighlighterForTesting = (cfi) async {
        highlighted.add(cfi);
      };

      final seg1 = TtsSegment(
        sentence: const TtsSentence(text: '第一句有CFI', cfi: 'cfi_1'),
      )..isSilent = true;

      final seg2 = TtsSegment(
        sentence: const TtsSentence(text: '第二句有CFI', cfi: 'cfi_2'),
      )..isSilent = true;

      localTts.bufferForTesting.add(seg1);
      localTts.bufferForTesting.add(seg2);
      localTts.bufferForTesting.add(LocalTts.eofSegment);

      localTts.updateTtsState(TtsStateEnum.playing);
      await localTts
          .startPlayerForTesting()
          .timeout(const Duration(seconds: 2));

      expect(getNextCallCount, equals(0),
          reason: 'CFI playback must not call getNextTextFunction');
      expect(highlighted, equals(['cfi_1', 'cfi_2']));
    });
  });

  group('LocalTts Buffer Underrun & False EOF Prevention', () {
    test(
        'buffer underrun during playback requests offset=1 with includeCurrent=false',
        () async {
      final localTts = LocalTts();
      final capturedCalls = <Map<String, dynamic>>[];

      int callIndex = 0;
      localTts.detailCollectorForTesting = ({
        required int count,
        bool includeCurrent = false,
        int offset = 1,
      }) async {
        capturedCalls.add({
          'includeCurrent': includeCurrent,
          'offset': offset,
          'count': count,
        });
        callIndex++;
        if (callIndex == 1) {
          return [const TtsSentence(text: '首句', cfi: 'cfi_start')];
        }
        return [const TtsSentence(text: '续句', cfi: 'cfi_continue')];
      };

      final mockEngine = MockLocalTtsEngine(delay: Duration.zero);
      localTts.providerForTesting =
          LocalTtsProvider.withEngine(engine: mockEngine);

      final prefetcherFuture = localTts.startPrefetcherForTesting();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(capturedCalls.first['includeCurrent'], isTrue);

      localTts.bufferForTesting.clear();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      localTts.shouldStopForTesting = true;
      await prefetcherFuture;

      expect(capturedCalls.length, greaterThanOrEqualTo(2));
      final secondCall = capturedCalls[1];
      expect(secondCall['includeCurrent'], isFalse,
          reason:
              'Subsequent fetch during underrun must not re-include current sentence');
    });

    test(
        'buffer underrun retries sentence collection and avoids jumping sections when sentences arrive',
        () async {
      final localTts = LocalTts();
      bool nextSectionCalled = false;
      localTts.nextSectionHandlerForTesting = () async {
        nextSectionCalled = true;
        return 'next_chapter';
      };

      int fetchAttempt = 0;
      localTts.detailCollectorForTesting = ({
        required int count,
        bool includeCurrent = false,
        int offset = 1,
      }) async {
        fetchAttempt++;
        if (fetchAttempt == 1) {
          return [const TtsSentence(text: '第一句', cfi: 'cfi_1')];
        } else if (fetchAttempt == 2) {
          return [];
        } else {
          return [const TtsSentence(text: '第二句', cfi: 'cfi_2')];
        }
      };

      final mockEngine = MockLocalTtsEngine(delay: Duration.zero);
      localTts.providerForTesting =
          LocalTtsProvider.withEngine(engine: mockEngine);

      final prefetcherFuture = localTts.startPrefetcherForTesting();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      localTts.shouldStopForTesting = true;
      await prefetcherFuture;

      expect(nextSectionCalled, isFalse,
          reason:
              'Temporary empty underrun must retry and not immediately jump sections');
    });
  });

  group('LocalTts Next/Prev Navigation Semantics', () {
    test(
        'next() does not invoke getHereFunction, preserving advanced reader position',
        () async {
      final localTts = LocalTts();
      bool hereCalled = false;
      bool nextCalled = false;

      await localTts.init(
        () {
          hereCalled = true;
        },
        () {
          nextCalled = true;
        },
        () {},
      );

      localTts.detailCollectorForTesting = ({
        required int count,
        bool includeCurrent = false,
        int offset = 1,
      }) async {
        return [const TtsSentence(text: '下句内容', cfi: 'cfi_next')];
      };

      final mockEngine = MockLocalTtsEngine(delay: Duration.zero);
      localTts.providerForTesting =
          LocalTtsProvider.withEngine(engine: mockEngine);

      unawaited(localTts.next());
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await localTts.stop();

      expect(nextCalled, isTrue,
          reason: 'next() must invoke getNextTextFunction');
      expect(hereCalled, isFalse,
          reason:
              'next() must skip getHereFunction to prevent resetting cursor to viewport top');
    });

    test(
        'prev() does not invoke getHereFunction, preserving previous reader position',
        () async {
      final localTts = LocalTts();
      bool hereCalled = false;
      bool prevCalled = false;

      await localTts.init(
        () {
          hereCalled = true;
        },
        () {},
        () {
          prevCalled = true;
        },
      );

      localTts.detailCollectorForTesting = ({
        required int count,
        bool includeCurrent = false,
        int offset = 1,
      }) async {
        return [const TtsSentence(text: '上句内容', cfi: 'cfi_prev')];
      };

      final mockEngine = MockLocalTtsEngine(delay: Duration.zero);
      localTts.providerForTesting =
          LocalTtsProvider.withEngine(engine: mockEngine);

      unawaited(localTts.prev());
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await localTts.stop();

      expect(prevCalled, isTrue,
          reason: 'prev() must invoke getPrevTextFunction');
      expect(hereCalled, isFalse,
          reason:
              'prev() must skip getHereFunction to prevent resetting cursor to viewport top');
    });

    test('standard speak() invokes getHereFunction to sync with viewport',
        () async {
      final localTts = LocalTts();
      bool hereCalled = false;

      await localTts.init(
        () {
          hereCalled = true;
        },
        () {},
        () {},
      );

      localTts.detailCollectorForTesting = ({
        required int count,
        bool includeCurrent = false,
        int offset = 1,
      }) async {
        return [const TtsSentence(text: '当前句', cfi: 'cfi_cur')];
      };

      final mockEngine = MockLocalTtsEngine(delay: Duration.zero);
      localTts.providerForTesting =
          LocalTtsProvider.withEngine(engine: mockEngine);

      unawaited(localTts.speak());
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await localTts.stop();

      expect(hereCalled, isTrue,
          reason:
              'Standard speak() must invoke getHereFunction to sync with viewport');
    });
  });

  group('LocalTts Volume, Pitch, and Rate Injection & Safety', () {
    test('overrides provide isolated rate, pitch, and volume without platform channel', () {
      final localTts = LocalTts();
      localTts.volumeOverrideForTesting = 0.8;
      localTts.pitchOverrideForTesting = 1.2;
      localTts.rateOverrideForTesting = 1.5;

      expect(localTts.volume, equals(0.8));
      expect(localTts.pitch, equals(1.2));
      expect(localTts.rate, equals(1.5));

      localTts.volume = 0.5;
      localTts.pitch = 0.9;
      localTts.rate = 1.1;

      expect(localTts.volume, equals(0.5));
      expect(localTts.pitch, equals(0.9));
      expect(localTts.rate, equals(1.1));
    });
  });

  group('LocalTts Fallback to SystemTts When Uninstalled', () {
    test(
        'speak() invokes SystemTts fallback when voice model is not installed',
        () async {
      final uninstalledDir =
          Directory.systemTemp.createTempSync('anx_tts_uninstalled_');
      try {
        final localTts = LocalTts(
          modelManager: LocalVoiceModelManager.withDirs(
            getBaseDir: () async => uninstalledDir,
            getTempDir: () async => uninstalledDir,
          ),
        );

        final mockSystemTts = MockSystemTts();
        localTts.systemTtsForTesting = mockSystemTts;

        await localTts.init(
          () {},
          () {},
          () {},
        );

        await localTts.speak();

        expect(mockSystemTts.initCalled, isTrue,
            reason: 'Fallback must initialize SystemTts with reader callbacks');
        expect(mockSystemTts.speakCalled, isTrue,
            reason: 'Fallback must call SystemTts.speak()');
      } finally {
        if (uninstalledDir.existsSync()) {
          uninstalledDir.deleteSync(recursive: true);
        }
      }
    });

    test(
        'speakPreview() delegates to SystemTts when voice model is not installed',
        () async {
      final uninstalledDir =
          Directory.systemTemp.createTempSync('anx_tts_uninstalled_');
      try {
        final localTts = LocalTts(
          modelManager: LocalVoiceModelManager.withDirs(
            getBaseDir: () async => uninstalledDir,
            getTempDir: () async => uninstalledDir,
          ),
        );

        final mockSystemTts = MockSystemTts();
        localTts.systemTtsForTesting = mockSystemTts;

        await localTts.speakPreview('测试预览内容');

        expect(mockSystemTts.speakCalled, isTrue,
            reason: 'Fallback preview must call SystemTts.speak(content: ...)');
        expect(mockSystemTts.lastSpokenContent, equals('测试预览内容'));
      } finally {
        if (uninstalledDir.existsSync()) {
          uninstalledDir.deleteSync(recursive: true);
        }
      }
    });
  });
}
