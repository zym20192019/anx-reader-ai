import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:anx_reader/service/tts/local_tts/local_voice_model.dart';
import 'package:anx_reader/service/tts/local_tts/local_voice_model_manager.dart';
import 'package:anx_reader/service/tts/local_tts/wav_encoder.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  group('LocalVoiceModel Definition & Integrity', () {
    test('defaultChineseModel has verified official metadata, CC0 license, and non-empty requiredFiles', () {
      final model = LocalVoiceModel.defaultChineseModel;

      expect(model.id, equals('zh-piper-chaowen-medium'));
      expect(model.displayName, equals('标准中文（超文）'));
      expect(model.locale, equals('zh-CN'));
      expect(model.gender, equals('male'));
      expect(model.sampleRate, equals(22050));
      expect(model.downloadSizeBytes, equals(60443846));
      expect(model.sha256, equals('1b69bdcf10bb6331c7f8a7591940febeb175c6bb86caa3802d96531f8e4ad211'));
      expect(model.license, equals('CC0'));
      expect(model.datasetSource, contains('voice-datasets'));
      expect(model.onnxFileName, equals('zh_CN-chaowen-medium.onnx'));
      expect(model.tokensFileName, equals('tokens.txt'));
      expect(model.lexiconFileName, equals('lexicon.txt'));
      expect(model.ruleFsts, containsAll(['phone.fst', 'date.fst', 'number.fst']));
      expect(model.requiredFiles, containsAll([
        'zh_CN-chaowen-medium.onnx',
        'tokens.txt',
        'lexicon.txt',
        'phone.fst',
        'date.fst',
        'number.fst',
      ]));
      expect(model.formattedSize, equals('57.6 MB'));
    });
  });

  group('WavEncoder & MIME Detection', () {
    test('encodes float32 samples into valid 16-bit mono PCM WAV bytes', () {
      final samples = Float32List.fromList([0.0, 0.5, -0.5, 1.0, -1.0]);
      final wavBytes = WavEncoder.encodeToWav(
        samples: samples,
        sampleRate: 22050,
        numChannels: 1,
      );

      expect(wavBytes.length, equals(44 + 5 * 2));

      // RIFF identifier
      expect(String.fromCharCodes(wavBytes.sublist(0, 4)), equals('RIFF'));
      // WAVE identifier
      expect(String.fromCharCodes(wavBytes.sublist(8, 12)), equals('WAVE'));
      // fmt chunk
      expect(String.fromCharCodes(wavBytes.sublist(12, 16)), equals('fmt '));

      final byteData = ByteData.sublistView(wavBytes);
      // AudioFormat == 1 (PCM)
      expect(byteData.getUint16(20, Endian.little), equals(1));
      // NumChannels == 1
      expect(byteData.getUint16(22, Endian.little), equals(1));
      // SampleRate == 22050
      expect(byteData.getUint32(24, Endian.little), equals(22050));
      // BitsPerSample == 16
      expect(byteData.getUint16(34, Endian.little), equals(16));
      // data chunk identifier
      expect(String.fromCharCodes(wavBytes.sublist(36, 40)), equals('data'));
      // Data size == 10 bytes
      expect(byteData.getUint32(40, Endian.little), equals(10));
    });

    test('isWav correctly identifies WAV header and detectAudioMimeType selects audio/wav', () {
      final samples = Float32List.fromList([0.1, -0.1]);
      final wav = WavEncoder.encodeToWav(samples: samples, sampleRate: 16000);
      final mp3Header = Uint8List.fromList([0x49, 0x44, 0x33, 0x03, 0x00]); // ID3

      expect(WavEncoder.isWav(wav), isTrue);
      expect(WavEncoder.isWav(mp3Header), isFalse);

      expect(WavEncoder.detectAudioMimeType(wav), equals('audio/wav'));
      expect(WavEncoder.detectAudioMimeType(mp3Header), equals('audio/mp3'));
    });
  });

  group('LocalVoiceModelManager Tests with Filesystem Isolation', () {
    late Directory tempRootDir;
    late Directory baseDir;
    late Directory tempDownloadDir;

    setUp(() {
      tempRootDir = Directory.systemTemp.createTempSync('anx_tts_test_');
      baseDir = Directory('${tempRootDir.path}/app_support')..createSync(recursive: true);
      tempDownloadDir = Directory('${tempRootDir.path}/app_temp')..createSync(recursive: true);
    });

    tearDown(() {
      if (tempRootDir.existsSync()) {
        tempRootDir.deleteSync(recursive: true);
      }
    });

    /// Helper to create a valid mock tar.bz2 archive containing required model files
    Uint8List createMockArchive(LocalVoiceModel model) {
      final archive = Archive();
      for (final reqFile in model.requiredFiles) {
        final content = utf8.encode('mock content for $reqFile');
        archive.addFile(ArchiveFile(
          '${model.id}/$reqFile',
          content.length,
          content,
        ));
      }
      final tarBytes = TarEncoder().encode(archive);
      final bz2Bytes = BZip2Encoder().encode(tarBytes);
      return Uint8List.fromList(bz2Bytes);
    }

    /// Helper to create an archive containing malicious paths (Zip Slip / Tar Slip)
    Uint8List createMaliciousArchive(String maliciousPath) {
      final archive = Archive();
      final content = utf8.encode('malicious content');
      archive.addFile(ArchiveFile(
        maliciousPath,
        content.length,
        content,
      ));
      final tarBytes = TarEncoder().encode(archive);
      final bz2Bytes = BZip2Encoder().encode(tarBytes);
      return Uint8List.fromList(bz2Bytes);
    }

    test('isModelInstalled returns false when model dir is empty or missing files', () async {
      final manager = LocalVoiceModelManager.withDirs(
        getBaseDir: () async => baseDir,
        getTempDir: () async => tempDownloadDir,
      );

      expect(await manager.isModelInstalled(LocalVoiceModel.defaultChineseModel), isFalse);

      final modelDir = await manager.getModelDir(LocalVoiceModel.defaultChineseModel);
      modelDir.createSync(recursive: true);
      expect(await manager.isModelInstalled(LocalVoiceModel.defaultChineseModel), isFalse);

      File('${modelDir.path}/tokens.txt').writeAsStringSync('token');
      expect(await manager.isModelInstalled(LocalVoiceModel.defaultChineseModel), isFalse);
    });

    test('downloadAndInstall verifies SHA-256 and atomically installs model on match via streaming', () async {
      final model = LocalVoiceModel.defaultChineseModel;
      final mockArchiveBytes = createMockArchive(model);
      final actualSha256 = sha256.convert(mockArchiveBytes).toString();

      final testModel = LocalVoiceModel(
        id: 'test-model',
        displayName: '测试语音',
        locale: 'zh-CN',
        gender: 'female',
        sampleRate: 22050,
        downloadSizeBytes: mockArchiveBytes.length,
        downloadUrl: 'https://example.com/test-model.tar.bz2',
        sha256: actualSha256,
        license: 'CC0',
        datasetSource: 'https://example.com',
        onnxFileName: model.onnxFileName,
        tokensFileName: model.tokensFileName,
        lexiconFileName: model.lexiconFileName,
        ruleFsts: model.ruleFsts,
        requiredFiles: model.requiredFiles,
      );

      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: ResponseBody.fromBytes(
              mockArchiveBytes,
              200,
              headers: {
                Headers.contentLengthHeader: [mockArchiveBytes.length.toString()],
              },
            ),
            statusCode: 200,
          ));
        },
      ));

      final manager = LocalVoiceModelManager.withDirs(
        dio: dio,
        getBaseDir: () async => baseDir,
        getTempDir: () async => tempDownloadDir,
      );

      expect(await manager.isModelInstalled(testModel), isFalse);

      await manager.downloadAndInstall(testModel);

      expect(await manager.isModelInstalled(testModel), isTrue);
      final modelDir = await manager.getModelDir(testModel);
      for (final reqFile in testModel.requiredFiles) {
        final f = File('${modelDir.path}/$reqFile');
        expect(f.existsSync(), isTrue, reason: '$reqFile must exist after install');
        expect(f.lengthSync(), greaterThan(0));
      }

      final tempDownloads = Directory('${tempDownloadDir.path}/tts_downloads');
      if (tempDownloads.existsSync()) {
        final tempFiles = tempDownloads.listSync();
        expect(tempFiles.where((f) => f.path.contains(testModel.id)), isEmpty);
      }
    });

    test('downloadAndInstall rejects malicious Zip Slip / Tar Slip paths and cleans up', () async {
      for (final badPath in [
        '../../evil.txt',
        '/tmp/evil_absolute.txt',
        'sub/../../escaped.txt',
      ]) {
        final maliciousBytes = createMaliciousArchive(badPath);
        final maliciousSha256 = sha256.convert(maliciousBytes).toString();

        final maliciousModel = LocalVoiceModel(
          id: 'malicious-model',
          displayName: '恶意模型',
          locale: 'zh-CN',
          gender: 'male',
          sampleRate: 22050,
          downloadSizeBytes: maliciousBytes.length,
          downloadUrl: 'https://example.com/malicious.tar.bz2',
          sha256: maliciousSha256,
          license: 'CC0',
          datasetSource: 'https://example.com',
          onnxFileName: 'model.onnx',
          tokensFileName: 'tokens.txt',
          lexiconFileName: 'lexicon.txt',
          ruleFsts: [],
          requiredFiles: ['model.onnx'],
        );

        final dio = Dio();
        dio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(Response(
              requestOptions: options,
              data: ResponseBody.fromBytes(
                maliciousBytes,
                200,
                headers: {
                  Headers.contentLengthHeader: [maliciousBytes.length.toString()],
                },
              ),
              statusCode: 200,
            ));
          },
        ));

        final manager = LocalVoiceModelManager.withDirs(
          dio: dio,
          getBaseDir: () async => baseDir,
          getTempDir: () async => tempDownloadDir,
        );

        expect(
          () async => await manager.downloadAndInstall(maliciousModel),
          throwsA(isA<ModelSecurityException>()),
        );

        // Verify malicious file was not written outside target directory
        final outsideFile = File('${tempRootDir.path}/evil.txt');
        expect(outsideFile.existsSync(), isFalse);
      }
    });

    test('downloadAndInstall fails and cleans up temporary files when SHA-256 mismatches', () async {
      final model = LocalVoiceModel.defaultChineseModel;
      final corruptedBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      final testModel = LocalVoiceModel(
        id: 'corrupt-model',
        displayName: '损坏模型',
        locale: 'zh-CN',
        gender: 'female',
        sampleRate: 22050,
        downloadSizeBytes: corruptedBytes.length,
        downloadUrl: 'https://example.com/corrupt.tar.bz2',
        sha256: '0000000000000000000000000000000000000000000000000000000000000000',
        license: 'CC0',
        datasetSource: 'https://example.com',
        onnxFileName: model.onnxFileName,
        tokensFileName: model.tokensFileName,
        lexiconFileName: model.lexiconFileName,
        ruleFsts: model.ruleFsts,
        requiredFiles: model.requiredFiles,
      );

      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: ResponseBody.fromBytes(
              corruptedBytes,
              200,
              headers: {
                Headers.contentLengthHeader: [corruptedBytes.length.toString()],
              },
            ),
            statusCode: 200,
          ));
        },
      ));

      final manager = LocalVoiceModelManager.withDirs(
        dio: dio,
        getBaseDir: () async => baseDir,
        getTempDir: () async => tempDownloadDir,
      );

      expect(
        () async => await manager.downloadAndInstall(testModel),
        throwsA(isA<ModelChecksumException>()),
      );

      expect(await manager.isModelInstalled(testModel), isFalse);

      final tempDownloads = Directory('${tempDownloadDir.path}/tts_downloads');
      if (tempDownloads.existsSync()) {
        final remaining = tempDownloads.listSync().where((f) => f.path.contains(testModel.id));
        expect(remaining, isEmpty);
      }
    });

    test('cancelDownload marks status notDownloaded rather than error and allows clean retry', () async {
      final model = LocalVoiceModel.defaultChineseModel;

      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Emulate slow stream download that can be cancelled
          final controller = StreamController<List<int>>();
          options.cancelToken?.whenCancel.then((_) {
            controller.addError(
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
                error: 'User cancelled download',
              ),
            );
            controller.close();
          });

          handler.resolve(Response(
            requestOptions: options,
            data: ResponseBody(
              controller.stream,
              200,
              headers: {
                Headers.contentLengthHeader: ['1000000'],
              },
            ),
            statusCode: 200,
          ));
        },
      ));

      final manager = LocalVoiceModelManager.withDirs(
        dio: dio,
        getBaseDir: () async => baseDir,
        getTempDir: () async => tempDownloadDir,
      );

      final downloadFuture = manager.downloadAndInstall(model);
      await Future.delayed(const Duration(milliseconds: 20));

      manager.cancelDownload(model);

      try {
        await downloadFuture;
      } catch (_) {}

      // Cancellation must result in notDownloaded, NOT error!
      final statusNotifier = manager.getStatusNotifier(model);
      expect(statusNotifier.value, equals(ModelInstallStatus.notDownloaded));
      expect(manager.getDownloadProgress(model).value, equals(0.0));
    });

    test('deleteModel removes installed directory and resets status', () async {
      final model = LocalVoiceModel.defaultChineseModel;
      final manager = LocalVoiceModelManager.withDirs(
        getBaseDir: () async => baseDir,
        getTempDir: () async => tempDownloadDir,
      );

      final modelDir = await manager.getModelDir(model);
      modelDir.createSync(recursive: true);
      for (final reqFile in model.requiredFiles) {
        File('${modelDir.path}/$reqFile').writeAsStringSync('content');
      }

      expect(await manager.isModelInstalled(model), isTrue);

      await manager.deleteModel(model);

      expect(await manager.isModelInstalled(model), isFalse);
      expect(modelDir.existsSync(), isFalse);
      expect(await manager.getModelStatus(model), equals(ModelInstallStatus.notDownloaded));
    });
  });

  group('TtsService and TtsFactory Integration', () {
    test('TtsService includes local and correctly reports online/local flags', () {
      expect(TtsService.values.contains(TtsService.local), isTrue);

      expect(TtsService.local.isOnline, isFalse);
      expect(TtsService.local.isLocal, isTrue);

      expect(getTtsService('local'), equals(TtsService.local));
      expect(getTtsService('system'), equals(TtsService.system));
      expect(getTtsService('unknown'), equals(TtsService.system));
    });
  });
}
