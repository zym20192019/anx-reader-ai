import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:test/test.dart';

void main() {
  group('Sync Source-File-Only Path Resolution', () {
    final now = DateTime(2026, 9, 12, 10, 0, 0);

    test('resolveBookSyncPath prefers sourceFilePath for TXT book', () {
      final book = Book(
        id: 1,
        title: 'TXT Book with Source',
        coverPath: 'cover/book1.png',
        filePath: 'file/book1_converted.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0.0,
        sourceFilePath: 'file/book1_source.txt',
        sourceFormat: 'txt',
        cacheFilePath: 'cache/txt_epub/book1/generated.epub',
        createTime: now,
        updateTime: now,
      );

      final syncPath = resolveBookSyncPath(book);
      expect(syncPath, equals('file/book1_source.txt'));
      expect(syncPath, isNot(contains('epub')));
      expect(syncPath, isNot(equals(book.cacheFilePath)));
    });

    test('resolveBookSyncPath falls back to filePath for legacy TXT book without sourceFilePath', () {
      final legacyTxtBook = Book(
        id: 2,
        title: 'Legacy TXT Book',
        coverPath: 'cover/legacy.png',
        filePath: 'file/legacy_novel.txt',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0.0,
        sourceFilePath: null,
        sourceFormat: 'txt',
        createTime: now,
        updateTime: now,
      );

      final syncPath = resolveBookSyncPath(legacyTxtBook);
      expect(syncPath, equals('file/legacy_novel.txt'));
    });

    test('resolveBookSyncPath falls back to legacy converted filePath when sourceFilePath is empty', () {
      final legacyConvertedBook = Book(
        id: 3,
        title: 'Legacy Converted Book',
        coverPath: 'cover/legacy_conv.png',
        filePath: 'file/legacy_converted.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0.0,
        sourceFilePath: '   ',
        sourceFormat: 'txt',
        createTime: now,
        updateTime: now,
      );

      final syncPath = resolveBookSyncPath(legacyConvertedBook);
      expect(syncPath, equals('file/legacy_converted.epub'));
    });

    test('resolveBookSyncPath always returns filePath for non-TXT books', () {
      final epubBook = Book(
        id: 4,
        title: 'Native EPUB Book',
        coverPath: 'cover/native.png',
        filePath: 'file/native_book.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0.0,
        sourceFilePath: 'file/source_ignore.epub',
        sourceFormat: 'epub',
        createTime: now,
        updateTime: now,
      );

      final syncPath = resolveBookSyncPath(epubBook);
      expect(syncPath, equals('file/native_book.epub'));
    });

    test('cacheFilePath is never selected as canonical sync path', () {
      final book = Book(
        id: 5,
        title: 'Book with Cache',
        coverPath: 'cover/cached.png',
        filePath: 'file/actual_source.txt',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0.0,
        sourceFilePath: 'file/actual_source.txt',
        sourceFormat: 'txt',
        cacheFilePath: 'cache/txt_epub/fp123/generated.epub',
        createTime: now,
        updateTime: now,
      );

      final syncPath = resolveBookSyncPath(book);
      expect(syncPath, equals('file/actual_source.txt'));
      expect(syncPath, isNot(equals(book.cacheFilePath)));
    });
  });

  group('toRemoteDataPath helper', () {
    test('converts relative file path to remote anx/data/ path', () {
      expect(toRemoteDataPath('file/book.txt'), equals('anx/data/file/book.txt'));
      expect(toRemoteDataPath('cover/book.png'), equals('anx/data/cover/book.png'));
    });

    test('handles backslashes and leading slashes gracefully', () {
      expect(toRemoteDataPath(r'file\book.txt'), equals('anx/data/file/book.txt'));
      expect(toRemoteDataPath('/file/book.txt'), equals('anx/data/file/book.txt'));
      expect(toRemoteDataPath(r'\file\book.txt'), equals('anx/data/file/book.txt'));
    });
  });

  group('Remote Orphan Cleanup Policy (Historical EPUB Preservation)', () {
    test('never prunes remote epub files under file/', () {
      expect(shouldPruneRemoteOrphan('file/historical_book.epub'), isFalse);
      expect(shouldPruneRemoteOrphan('file/converted_cache.epub'), isFalse);
      expect(shouldPruneRemoteOrphan(r'file\legacy.EPUB'), isFalse);
    });

    test('allows pruning remote non-epub orphan files', () {
      expect(shouldPruneRemoteOrphan('file/orphan_deleted.txt'), isTrue);
      expect(shouldPruneRemoteOrphan('file/orphan_deleted.pdf'), isTrue);
      expect(shouldPruneRemoteOrphan('cover/orphan_cover.png'), isTrue);
      expect(shouldPruneRemoteOrphan('cover/orphan_cover.jpg'), isTrue);
    });
  });

  group('Cache Path Deletion Safety Rules', () {
    test('isSafeCachePathToDelete allows safe txt_epub cache paths', () {
      expect(
        isSafeCachePathToDelete(
          'cache/txt_epub/fingerprint_1/generated.epub',
          resolvedSyncPath: 'file/source.txt',
          filePath: 'file/source.txt',
        ),
        isTrue,
      );
      expect(
        isSafeCachePathToDelete(
          r'C:\data\cache\txt_epub\fp\generated.epub',
          resolvedSyncPath: 'file/source.txt',
          filePath: 'file/source.txt',
        ),
        isTrue,
      );
    });

    test('isSafeCachePathToDelete rejects null, empty, or whitespace paths', () {
      expect(
        isSafeCachePathToDelete(
          null,
          resolvedSyncPath: 'file/source.txt',
          filePath: 'file/source.txt',
        ),
        isFalse,
      );
      expect(
        isSafeCachePathToDelete(
          '',
          resolvedSyncPath: 'file/source.txt',
          filePath: 'file/source.txt',
        ),
        isFalse,
      );
      expect(
        isSafeCachePathToDelete(
          '   ',
          resolvedSyncPath: 'file/source.txt',
          filePath: 'file/source.txt',
        ),
        isFalse,
      );
    });

    test('isSafeCachePathToDelete rejects paths identical to syncPath or filePath', () {
      expect(
        isSafeCachePathToDelete(
          'file/source.txt',
          resolvedSyncPath: 'file/source.txt',
          filePath: 'file/book.epub',
        ),
        isFalse,
      );
      expect(
        isSafeCachePathToDelete(
          'file/book.epub',
          resolvedSyncPath: 'file/source.txt',
          filePath: 'file/book.epub',
        ),
        isFalse,
      );
    });

    test('isSafeCachePathToDelete rejects paths that do not contain cache directory markers', () {
      expect(
        isSafeCachePathToDelete(
          'file/other_book.txt',
          resolvedSyncPath: 'file/source.txt',
          filePath: 'file/source.txt',
        ),
        isFalse,
      );
      expect(
        isSafeCachePathToDelete(
          'documents/my_novel.txt',
          resolvedSyncPath: 'file/source.txt',
          filePath: 'file/source.txt',
        ),
        isFalse,
      );
    });
  });
}
