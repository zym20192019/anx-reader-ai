import 'dart:io';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/service/txt_cache/txt_cache_key.dart';
import 'package:anx_reader/service/txt_cache/txt_cache_manager.dart';
import 'package:test/test.dart';

void main() {
  group('TXT Cache Rebuild & Sync Decoupling', () {
    late Directory tempDir;
    late TxtCacheManager cacheManager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anx-sync-txt-cache-test-');
      cacheManager = TxtCacheManager(cacheRoot: tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('rebuilding local TXT cache does not alter canonical sync path', () async {
      // 1. Arrange a TXT source file
      final sourceFile = File('${tempDir.path}${Platform.pathSeparator}source.txt')
        ..writeAsStringSync('Chapter 1\nHello World\nChapter 2\nContinuation');

      final sourceMd5 = 'd41d8cd98f00b204e9800998ecf8427e';
      final fingerprint = generateTxtCacheFingerprint(
        sourceMd5: sourceMd5,
        rule: r'^Chapter [0-9]+',
      )!;

      // 2. Build initial cache
      final initialCache = await cacheManager.ensureCache(
        source: sourceFile,
        fingerprint: fingerprint,
        converter: (src) async {
          final out = File('${tempDir.path}${Platform.pathSeparator}generated_initial.epub');
          await out.writeAsString('initial-epub-content');
          return out;
        },
      );

      final book = Book(
        id: 10,
        title: 'Story',
        coverPath: 'cover/story.png',
        filePath: 'file/legacy_story.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Writer',
        isDeleted: false,
        rating: 0.0,
        sourceFilePath: 'file/story.txt',
        sourceFormat: 'txt',
        cacheFilePath: initialCache.path,
        cacheFingerprint: fingerprint,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      // Verify canonical sync path points to the source TXT, never the cache EPUB
      expect(resolveBookSyncPath(book), equals('file/story.txt'));

      // 3. Simulate cache rebuild (e.g. parser rule changed or cache cleared)
      final newFingerprint = generateTxtCacheFingerprint(
        sourceMd5: sourceMd5,
        rule: r'^Chapter [0-9]+: .*', // updated rule
      )!;

      final rebuiltCache = await cacheManager.ensureCache(
        source: sourceFile,
        fingerprint: newFingerprint,
        converter: (src) async {
          final out = File('${tempDir.path}${Platform.pathSeparator}generated_v2.epub');
          await out.writeAsString('v2-epub-content');
          return out;
        },
      );

      final updatedBook = book.copyWith(
        cacheFilePath: rebuiltCache.path,
        cacheFingerprint: newFingerprint,
      );

      // Rebuilt cache changes cacheFilePath, but canonical sync path remains constant source TXT
      expect(resolveBookSyncPath(updatedBook), equals('file/story.txt'));
      expect(resolveBookSyncPath(updatedBook), isNot(equals(updatedBook.cacheFilePath)));
    });

    test('missing or invalid cache does not prevent sync path resolution or throw', () {
      final bookMissingCache = Book(
        id: 11,
        title: 'Book without Cache',
        coverPath: 'cover/book11.png',
        filePath: 'file/book11_old.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Writer',
        isDeleted: false,
        rating: 0.0,
        sourceFilePath: 'file/book11.txt',
        sourceFormat: 'txt',
        cacheFilePath: null,
        cacheFingerprint: null,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      expect(resolveBookSyncPath(bookMissingCache), equals('file/book11.txt'));
      expect(toRemoteDataPath(resolveBookSyncPath(bookMissingCache)), equals('anx/data/file/book11.txt'));
    });

    test('releaseBook cache safety check prevents accidental deletion of source TXT', () {
      final book = Book(
        id: 12,
        title: 'Safety Test Book',
        coverPath: 'cover/safe.png',
        filePath: 'file/safe_book.txt',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Writer',
        isDeleted: false,
        rating: 0.0,
        sourceFilePath: 'file/safe_book.txt',
        sourceFormat: 'txt',
        cacheFilePath: 'file/safe_book.txt', // Malicious or corrupted cache path pointing to source
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      final syncPath = resolveBookSyncPath(book);
      final isSafe = isSafeCachePathToDelete(
        book.cacheFilePath,
        resolvedSyncPath: syncPath,
        filePath: book.filePath,
      );

      // Must be false: prevent deleting source as cache!
      expect(isSafe, isFalse);
    });

    test('releaseBook resolves cache via TxtCacheManager without touching document/file source', () async {
      final cacheRelative = 'txt_epub/fp123/generated.epub';
      final resolvedCacheFile = cacheManager.resolveRelativeCachePath(cacheRelative);
      await resolvedCacheFile.parent.create(recursive: true);
      await resolvedCacheFile.writeAsString('dummy cache epub');

      final sourceFile = File('${tempDir.path}${Platform.pathSeparator}source.txt')
        ..writeAsStringSync('dummy source txt');

      final book = Book(
        id: 13,
        title: 'Cache Resolution Test',
        coverPath: 'cover/book.png',
        filePath: 'file/book.txt',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Writer',
        isDeleted: false,
        rating: 0.0,
        sourceFilePath: 'file/book.txt',
        sourceFormat: 'txt',
        cacheFilePath: cacheRelative,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      // Verify safety check allows txt_epub cache path
      final syncPath = resolveBookSyncPath(book);
      expect(
        isSafeCachePathToDelete(
          book.cacheFilePath,
          resolvedSyncPath: syncPath,
          filePath: book.filePath,
        ),
        isTrue,
      );

      // Verify TxtCacheManager resolves correctly under cacheRoot
      final targetFile = await TxtCacheManager.resolveBookCacheFile(
        book.cacheFilePath,
        cacheRoot: tempDir,
      );
      expect(targetFile, isNotNull);
      expect(targetFile!.path, equals(resolvedCacheFile.path));
      expect(await targetFile.exists(), isTrue);

      // Simulate cache deletion
      await targetFile.delete();
      expect(await targetFile.exists(), isFalse);
      // Source file must remain completely untouched
      expect(await sourceFile.exists(), isTrue);
    });
  });
}
