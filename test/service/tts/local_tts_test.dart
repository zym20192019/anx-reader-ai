import 'dart:async';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/local_tts/local_tts.dart';
import 'package:anx_reader/service/tts/local_tts/local_tts_provider.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:test/test.dart';

void main() {
  setUp(() async {
    final localTts = LocalTts();
    await localTts.stop();
  });

  tearDown(() async {
    final localTts = LocalTts();
    await localTts.stop();
  });

  group('LocalTts Sentence Parsing & Contract', () {
    test('constructs valid TtsSentence without fake cfi for pure String callbacks', () {
      const sentence = TtsSentence(text: '测试第一句', cfi: null);
      expect(sentence.text, equals('测试第一句'));
      expect(sentence.cfi, isNull);

      final fromMap = TtsSentence.fromMap({'text': '测试第二句', 'cfi': 'epubcfi(/6/2)'});
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
    test('speak throws descriptive StateError when model is uninstalled and not initialized', () async {
      final localTts = LocalTts();
      localTts.isInit = false;

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
    test('prev does not throw LateInitializationError when uninitialized', () async {
      final localTts = LocalTts();
      localTts.isInit = false;
      localTts.getPrevTextFunction = null;

      await expectLater(
        localTts.prev(),
        completes,
      );
      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
    });

    test('next does not throw LateInitializationError when uninitialized', () async {
      final localTts = LocalTts();
      localTts.isInit = false;
      localTts.getNextTextFunction = null;

      await expectLater(
        localTts.next(),
        completes,
      );
      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
    });

    test('restart does not throw LateInitializationError when uninitialized', () async {
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

    test('concurrent stop calls deduplicate and avoid reentrancy deadlock', () async {
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
    test('_startPlayer reaches EOF on empty buffer and completes without self-await deadlock', () async {
      final localTts = LocalTts();
      await localTts.stop();

      // Configure player loop to encounter EOF immediately
      localTts.hasReachedEofForTesting = true;
      localTts.updateTtsState(TtsStateEnum.playing);

      // In the previous code, this called await stop(), which awaited _playerCompleter,
      // creating an infinite self-waiting deadlock.
      // With _teardownOnEof(), it exits cleanly and completes the future.
      await localTts
          .startPlayerForTesting()
          .timeout(const Duration(seconds: 2));

      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
      expect(localTts.isPlayerRunningForTesting, isFalse);
      expect(localTts.bufferForTesting, isEmpty);

      // Subsequent external stop must also return immediately
      await localTts.stop().timeout(const Duration(seconds: 2));
    });

    test('_startPlayer completes naturally when buffer contains eofSegment', () async {
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

    test('teardownOnEof directly cleans up resources without deadlock', () async {
      final localTts = LocalTts();
      localTts.updateTtsState(TtsStateEnum.playing);

      await localTts.teardownOnEofForTesting().timeout(const Duration(seconds: 2));

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

    test('speakPreview recovers to stopped state when model uninstalled or on error', () async {
      final localTts = LocalTts();
      await localTts.stop();

      try {
        await localTts.speakPreview('试听语音测试内容');
      } catch (_) {}

      expect(localTts.ttsStateNotifier.value, equals(TtsStateEnum.stopped));
    });
  });
}
