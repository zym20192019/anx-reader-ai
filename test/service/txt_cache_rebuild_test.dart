import 'dart:io';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/chapter_split_rule.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/md5_service.dart';
import 'package:anx_reader/service/txt_cache/txt_cache_manager.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Directory cacheRootDir;
  late TxtCacheManager cacheManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anx-txt-rebuild-test-');
    cacheRootDir = Directory('${tempDir.path}${Platform.pathSeparator}cache');
    await cacheRootDir.create(recursive: true);
    cacheManager = TxtCacheManager(cacheRoot: cacheRootDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ensureBookReadableFile - non-TXT & legacy EPUB behavior', () {
    test('returns fileFullPath for existing EPUB without calling cacheManager or converter', () async {
      final epubFile = File('${tempDir.path}${Platform.pathSeparator}test.epub');
      await epubFile.writeAsString('fake-epub-content');

      final legacyBook = Book(
        id: 1,
        title: 'Legacy Book',
        coverPath: '',
        filePath: epubFile.path,
        lastReadPosition: 'epubcfi(/6/2[chapter1]!/4/1:0)',
        readingPercentage: 0.1,
        author: 'Author',
        isDeleted: false,
        rating: 0,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      var converterCalled = false;
      final result = await ensureBookReadableFile(
        legacyBook,
        cacheManager: cacheManager,
        converter: (source) async {
          converterCalled = true;
          return source;
        },
      );

      expect(result.path, equals(epubFile.path));
      expect(converterCalled, isFalse);
      expect(legacyBook.filePath, equals(epubFile.path));
      expect(legacyBook.cacheFilePath, isNull);
    });

    test('throws FileSystemException if non-TXT file does not exist', () async {
      final nonExistentBook = Book(
        id: 2,
        title: 'Missing EPUB',
        coverPath: '',
        filePath: '${tempDir.path}${Platform.pathSeparator}missing.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      expect(
        () => ensureBookReadableFile(nonExistentBook, cacheManager: cacheManager),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('ensureBookReadableFile - TXT cache check and lazy rebuild', () {
    test('throws FileSystemException when source TXT file does not exist', () async {
      final missingTxtBook = Book(
        id: 3,
        title: 'Missing TXT',
        coverPath: '',
        filePath: '${tempDir.path}${Platform.pathSeparator}missing.txt',
        sourceFormat: 'txt',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      expect(
        () => ensureBookReadableFile(missingTxtBook, cacheManager: cacheManager),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('lazily creates cache on first read and reuses valid cache on second read', () async {
      final sourceFile = File('${tempDir.path}${Platform.pathSeparator}novel.txt');
      await sourceFile.writeAsString('第一章 故事开始\n这是正文内容。\n第二章 故事高潮\n精彩纷呈。');
      final sourceMd5 = await MD5Service.calculateFileMd5(sourceFile.path);

      final splitRule = ChapterSplitRule(
        name: 'Default',
        pattern: r'第[0-9一二三四五六七八九十百千]+章',
      );

      final txtBook = Book(
        id: 10,
        title: 'Novel',
        coverPath: '',
        filePath: sourceFile.path,
        sourceFormat: 'txt',
        sourceMd5: sourceMd5,
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      var conversionCount = 0;
      Future<File> mockConverter(File source) async {
        conversionCount++;
        final generated = File('${tempDir.path}${Platform.pathSeparator}gen-$conversionCount.epub');
        await generated.writeAsString('epub-data-$conversionCount');
        return generated;
      }

      // First call: cache does not exist -> rebuilds
      final firstReadable = await ensureBookReadableFile(
        txtBook,
        cacheManager: cacheManager,
        converter: mockConverter,
        splitRule: splitRule,
      );

      expect(conversionCount, equals(1));
      expect(await firstReadable.exists(), isTrue);
      expect(await firstReadable.readAsString(), equals('epub-data-1'));
      expect(txtBook.cacheFingerprint, isNotNull);
      expect(txtBook.cacheFilePath, startsWith('txt_epub/'));
      expect(txtBook.cacheFilePath, endsWith('generated.epub'));
      // Formal book.filePath must remain pointing to the source TXT file!
      expect(txtBook.filePath, equals(sourceFile.path));
      expect(txtBook.cacheFilePath, isNot(contains('file/')));

      // Second call: cache is valid -> reuses without converter
      final secondReadable = await ensureBookReadableFile(
        txtBook,
        cacheManager: cacheManager,
        converter: mockConverter,
        splitRule: splitRule,
      );

      expect(conversionCount, equals(1)); // Converter was NOT called again
      expect(secondReadable.path, equals(firstReadable.path));
      expect(await secondReadable.readAsString(), equals('epub-data-1'));
    });

    test('rebuilds cache when active chapter split rule changes', () async {
      final sourceFile = File('${tempDir.path}${Platform.pathSeparator}rule_change.txt');
      await sourceFile.writeAsString('第一章 开始\n正文\nSection 2 Next\n正文2');
      final sourceMd5 = await MD5Service.calculateFileMd5(sourceFile.path);

      final rule1 = ChapterSplitRule(name: 'Rule 1', pattern: r'第[0-9]+章');
      final rule2 = ChapterSplitRule(name: 'Rule 2', pattern: r'Section\s+[0-9]+');

      final txtBook = Book(
        id: 11,
        title: 'Rule Change Book',
        coverPath: '',
        filePath: sourceFile.path,
        sourceFormat: 'txt',
        sourceMd5: sourceMd5,
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      var conversionCount = 0;
      Future<File> mockConverter(File source) async {
        conversionCount++;
        final generated = File('${tempDir.path}${Platform.pathSeparator}rebuild-$conversionCount.epub');
        await generated.writeAsString('rebuild-data-$conversionCount');
        return generated;
      }

      // Read with rule1
      final readable1 = await ensureBookReadableFile(
        txtBook,
        cacheManager: cacheManager,
        converter: mockConverter,
        splitRule: rule1,
      );
      final fingerprint1 = txtBook.cacheFingerprint;
      expect(conversionCount, equals(1));

      // Read with rule2 -> fingerprint changes, triggers rebuild
      final readable2 = await ensureBookReadableFile(
        txtBook,
        cacheManager: cacheManager,
        converter: mockConverter,
        splitRule: rule2,
      );
      final fingerprint2 = txtBook.cacheFingerprint;

      expect(conversionCount, equals(2));
      expect(fingerprint2, isNot(equals(fingerprint1)));
      expect(readable2.path, isNot(equals(readable1.path)));
      expect(await readable2.readAsString(), equals('rebuild-data-2'));
      // Still preserves formal filePath
      expect(txtBook.filePath, equals(sourceFile.path));
    });

    test('auto-computes sourceMd5, fileMd5, and sourceTextLength if missing', () async {
      final sourceFile = File('${tempDir.path}${Platform.pathSeparator}no_md5.txt');
      const textContent = '这是测试文本，用于验证 MD5 和文本长度自动计算。';
      await sourceFile.writeAsString(textContent);

      final txtBook = Book(
        id: 12,
        title: 'Auto MD5 Book',
        coverPath: '',
        filePath: sourceFile.path,
        sourceFormat: 'txt',
        sourceMd5: null, // intentionally null
        fileMd5: null,   // intentionally null
        sourceTextLength: null,
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      final readable = await ensureBookReadableFile(
        txtBook,
        cacheManager: cacheManager,
        converter: (source) async {
          final out = File('${tempDir.path}${Platform.pathSeparator}auto.epub');
          await out.writeAsString('auto-epub');
          return out;
        },
        splitRule: 'default-rule',
      );

      expect(await readable.exists(), isTrue);
      expect(txtBook.sourceMd5, isNotNull);
      expect(txtBook.fileMd5, equals(txtBook.sourceMd5));
      expect(txtBook.sourceTextLength, equals(textContent.length));
    });

    test('propagates exception when converter fails', () async {
      final sourceFile = File('${tempDir.path}${Platform.pathSeparator}failing.txt');
      await sourceFile.writeAsString('内容');

      final txtBook = Book(
        id: 13,
        title: 'Failing Book',
        coverPath: '',
        filePath: sourceFile.path,
        sourceFormat: 'txt',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      expect(
        () => ensureBookReadableFile(
          txtBook,
          cacheManager: cacheManager,
          converter: (source) async => throw Exception('EPUB generation error'),
          splitRule: 'rule',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
