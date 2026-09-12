import 'dart:io';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/txt_cache/txt_cache_manager.dart';
import 'package:anx_reader/service/txt_cache/txt_position.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Directory cacheRootDir;
  late TxtCacheManager cacheManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anx-txt-reading-entry-test-');
    cacheRootDir = Directory('${tempDir.path}${Platform.pathSeparator}cache');
    await cacheRootDir.create(recursive: true);
    cacheManager = TxtCacheManager(cacheRoot: cacheRootDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('TXT reading entry - formal file path preservation', () {
    test('book.filePath remains pointing to the formal TXT source and not the cache EPUB', () async {
      final sourceFile = File('${tempDir.path}${Platform.pathSeparator}source_only.txt');
      await sourceFile.writeAsString('正文内容ABCDEFG');

      final book = Book(
        id: 101,
        title: 'Source Only Book',
        coverPath: '',
        filePath: sourceFile.path,
        sourceFormat: 'txt',
        sourceMd5: 'md5_101',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      final readable = await ensureBookReadableFile(
        book,
        cacheManager: cacheManager,
        converter: (source) async {
          final out = File('${tempDir.path}${Platform.pathSeparator}cache.epub');
          await out.writeAsString('cache-epub');
          return out;
        },
        splitRule: 'rule-test',
      );

      // Cache file returned is the generated EPUB
      expect(readable.path, endsWith('generated.epub'));
      expect(readable.path, contains(TxtCacheManager.cacheDirectoryName));

      // But formal book.filePath is NEVER modified
      expect(book.filePath, equals(sourceFile.path));
      expect(book.filePath, endsWith('.txt'));
      expect(book.cacheFilePath, startsWith('txt_epub/'));
    });

    test('remote-only TXT book throws FileSystemException when source is missing', () async {
      final remoteOnlyBook = Book(
        id: 102,
        title: 'Remote Only TXT',
        coverPath: '',
        filePath: '${tempDir.path}${Platform.pathSeparator}non_existent.txt',
        sourceFormat: 'txt',
        sourceMd5: 'remote_md5',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      // Ensures we do not mistake a missing source TXT as a valid EPUB
      expect(
        () => ensureBookReadableFile(remoteOnlyBook, cacheManager: cacheManager),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('TXT reading progress - updateTxtReadingProgress minimal closed loop', () {
    test('calculates sourceTextOffset, positionContext, and readingPercentage correctly', () async {
      final sourceFile = File('${tempDir.path}${Platform.pathSeparator}progress_test.txt');
      const textContent = '春眠不觉晓，处处闻啼鸟。夜来风雨声，花落知多少。';
      await sourceFile.writeAsString(textContent);

      final book = Book(
        id: 201,
        title: 'Progress Book',
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

      // 50% reading progress
      await updateTxtReadingProgress(
        book: book,
        cfi: 'epubcfi(/6/2[chap1]!/4/2:10)',
        percentage: 0.5,
        sourceFile: sourceFile,
      );

      expect(book.lastReadPosition, equals('epubcfi(/6/2[chap1]!/4/2:10)'));
      expect(book.sourceTextLength, equals(textContent.length));

      final expectedOffset = (textContent.length * 0.5).round();
      expect(book.sourceTextOffset, equals(expectedOffset));
      expect(book.readingPercentage, equals(expectedOffset / textContent.length));

      // positionContext is non-empty context hash around offset
      expect(book.positionContext, isNotNull);
      expect(book.positionContext!.length, equals(64)); // SHA-256 hash length

      // Verify that the context hash matches the text at that offset
      expect(
        verifyContextHash(
          text: textContent,
          offset: book.sourceTextOffset!,
          expectedHash: book.positionContext,
        ),
        isTrue,
      );
    });

    test('clamps boundary percentages safely (0%, 100%, negative, >100%)', () async {
      final sourceFile = File('${tempDir.path}${Platform.pathSeparator}bounds.txt');
      const text = 'abcdefghij'; // 10 code units
      await sourceFile.writeAsString(text);

      final book = Book(
        id: 202,
        title: 'Bounds Book',
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

      // 0%
      await updateTxtReadingProgress(
        book: book,
        cfi: 'cfi_0',
        percentage: 0.0,
        sourceFile: sourceFile,
      );
      expect(book.sourceTextOffset, equals(0));
      expect(book.readingPercentage, equals(0.0));

      // 100%
      await updateTxtReadingProgress(
        book: book,
        cfi: 'cfi_100',
        percentage: 1.0,
        sourceFile: sourceFile,
      );
      expect(book.sourceTextOffset, equals(10));
      expect(book.readingPercentage, equals(1.0));

      // Negative percentage clamps to 0
      await updateTxtReadingProgress(
        book: book,
        cfi: 'cfi_neg',
        percentage: -0.25,
        sourceFile: sourceFile,
      );
      expect(book.sourceTextOffset, equals(0));
      expect(book.readingPercentage, equals(0.0));

      // Overflow percentage clamps to source length
      await updateTxtReadingProgress(
        book: book,
        cfi: 'cfi_over',
        percentage: 1.5,
        sourceFile: sourceFile,
      );
      expect(book.sourceTextOffset, equals(10));
      expect(book.readingPercentage, equals(1.0));
    });

    test('aligns offset to avoid landing inside UTF-16 surrogate pairs', () async {
      final sourceFile = File('${tempDir.path}${Platform.pathSeparator}surrogate.txt');
      // 'A' (offset 0), '🎉' (offsets 1, 2), 'B' (offset 3). Length: 4
      const text = 'A🎉B';
      await sourceFile.writeAsString(text);

      final book = Book(
        id: 203,
        title: 'Surrogate Book',
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

      // 50% of 4 code units is offset 2 (which is in the middle of '🎉')
      await updateTxtReadingProgress(
        book: book,
        cfi: 'cfi_emoji',
        percentage: 0.5,
        sourceFile: sourceFile,
      );

      // Offset should be aligned so it never splits the emoji surrogate pair
      expect(isInsideSurrogatePair(text, book.sourceTextOffset!), isFalse);
      expect(book.positionContext, isNotNull);
    });
  });
}
