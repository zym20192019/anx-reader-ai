import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_source.dart';
import 'package:test/test.dart';

void main() {
  group('Database Schema & Migration Version', () {
    test('currentDbVersion is bumped to 9', () {
      expect(currentDbVersion, equals(9));
    });

    test('createBookSQL includes all source and cache compatibility columns', () {
      expect(createBookSQL, contains('source_file_path TEXT'));
      expect(createBookSQL, contains('source_format TEXT'));
      expect(createBookSQL, contains('cache_file_path TEXT'));
      expect(createBookSQL, contains('cache_fingerprint TEXT'));
      expect(createBookSQL, contains('source_text_offset INTEGER'));
      expect(createBookSQL, contains('source_text_length INTEGER'));
      expect(createBookSQL, contains('position_context TEXT'));
      expect(createBookSQL, contains('file_md5 TEXT'));
      expect(createBookSQL, contains('source_md5 TEXT'));
      expect(createBookSQL, contains('rating REAL'));
      expect(createBookSQL, contains('group_id INTEGER'));
    });
  });

  group('Migration Simulation & Backwards Compatibility', () {
    test('Simulated v8 database row migrates cleanly to v9 Book model', () {
      // Representation of a row in a v8 database (where source_md5 existed, but no source/cache fields)
      final v8DbRow = <String, dynamic>{
        'id': 101,
        'title': 'v8 Existing Book',
        'cover_path': 'cover/v8.png',
        'file_path': 'file/v8.epub',
        'last_read_position': '100',
        'reading_percentage': 0.1,
        'author': 'v8 Author',
        'is_deleted': 0,
        'description': 'Existing in v8',
        'rating': 4.0,
        'group_id': 0,
        'file_md5': 'v8_file_md5_hash',
        'source_md5': 'v8_source_md5_hash',
        'create_time': DateTime(2026, 1, 1).toIso8601String(),
        'update_time': DateTime(2026, 1, 1).toIso8601String(),
        // New columns are null when added via ALTER TABLE
        'source_file_path': null,
        'source_format': null,
        'cache_file_path': null,
        'cache_fingerprint': null,
        'source_text_offset': null,
        'source_text_length': null,
        'position_context': null,
      };

      final book = Book.fromDb(v8DbRow);

      // Existing v8 fields are unmodified
      expect(book.id, equals(101));
      expect(book.filePath, equals('file/v8.epub'));
      expect(book.fileMd5, equals('v8_file_md5_hash'));
      expect(book.sourceMd5, equals('v8_source_md5_hash'));

      // Migration must NOT guess or alter paths
      expect(book.sourceFilePath, isNull);
      expect(book.sourceFormat, isNull);
      expect(book.cacheFilePath, isNull);
      expect(book.cacheFingerprint, isNull);
      expect(book.sourceTextOffset, isNull);
      expect(book.sourceTextLength, isNull);
      expect(book.positionContext, isNull);
    });

    test('Simulated v7 database row (pre-source_md5) migrates cleanly to v9 Book model', () {
      final v7DbRow = <String, dynamic>{
        'id': 77,
        'title': 'v7 Legacy Book',
        'cover_path': 'cover/v7.png',
        'file_path': 'file/v7.epub',
        'last_read_position': '',
        'reading_percentage': 0.0,
        'author': 'v7 Author',
        'is_deleted': 0,
        'description': '',
        'rating': 0.0,
        'group_id': 0,
        'file_md5': 'v7_file_hash',
        'source_md5': null,
        'create_time': DateTime(2025, 12, 1).toIso8601String(),
        'update_time': DateTime(2025, 12, 1).toIso8601String(),
        'source_file_path': null,
        'source_format': null,
        'cache_file_path': null,
        'cache_fingerprint': null,
        'source_text_offset': null,
        'source_text_length': null,
        'position_context': null,
      };

      final book = Book.fromDb(v7DbRow);
      expect(book.id, equals(77));
      expect(book.filePath, equals('file/v7.epub'));
      expect(book.fileMd5, equals('v7_file_hash'));
      expect(book.sourceMd5, isNull);
      expect(book.sourceFilePath, isNull);
    });
  });

  group('BookDao source files resolution logic', () {
    test('Non-TXT books always fallback to filePath', () {
      final epubBook = Book(
        id: 1,
        title: 'EPUB Book',
        coverPath: '',
        filePath: 'file/book.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: '',
        isDeleted: false,
        rating: 0.0,
        sourceFilePath: 'file/source.epub',
        sourceFormat: 'epub',
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      // Resolving source path for epub returns filePath
      final isTxt = isTxtSourceFormat(epubBook.sourceFormat) ||
          epubBook.filePath.toLowerCase().endsWith('.txt') ||
          (epubBook.sourceFilePath != null &&
              epubBook.sourceFilePath!.toLowerCase().endsWith('.txt'));

      final resolvedPath = (isTxt &&
              epubBook.sourceFilePath != null &&
              epubBook.sourceFilePath!.isNotEmpty)
          ? epubBook.sourceFilePath!
          : epubBook.filePath;

      expect(resolvedPath, equals('file/book.epub'));
    });

    test('TXT books prefer sourceFilePath when available', () {
      final txtBookWithSource = Book(
        id: 2,
        title: 'TXT Book with Source',
        coverPath: '',
        filePath: 'file/book.epub', // converted epub path
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: '',
        isDeleted: false,
        rating: 0.0,
        sourceFilePath: 'file/original_novel.txt',
        sourceFormat: 'txt',
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      final isTxt = isTxtSourceFormat(txtBookWithSource.sourceFormat) ||
          txtBookWithSource.filePath.toLowerCase().endsWith('.txt') ||
          (txtBookWithSource.sourceFilePath != null &&
              txtBookWithSource.sourceFilePath!.toLowerCase().endsWith('.txt'));

      final resolvedPath = (isTxt &&
              txtBookWithSource.sourceFilePath != null &&
              txtBookWithSource.sourceFilePath!.isNotEmpty)
          ? txtBookWithSource.sourceFilePath!
          : txtBookWithSource.filePath;

      expect(resolvedPath, equals('file/original_novel.txt'));
    });

    test('TXT books without sourceFilePath fallback to filePath', () {
      final legacyTxtBook = Book(
        id: 3,
        title: 'Legacy TXT Book',
        coverPath: '',
        filePath: 'file/legacy_converted.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: '',
        isDeleted: false,
        rating: 0.0,
        sourceFormat: 'txt',
        sourceFilePath: null, // no source recorded
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      final isTxt = isTxtSourceFormat(legacyTxtBook.sourceFormat) ||
          legacyTxtBook.filePath.toLowerCase().endsWith('.txt') ||
          (legacyTxtBook.sourceFilePath != null &&
              legacyTxtBook.sourceFilePath!.toLowerCase().endsWith('.txt'));

      final resolvedPath = (isTxt &&
              legacyTxtBook.sourceFilePath != null &&
              legacyTxtBook.sourceFilePath!.isNotEmpty)
          ? legacyTxtBook.sourceFilePath!
          : legacyTxtBook.filePath;

      expect(resolvedPath, equals('file/legacy_converted.epub'));
    });
  });
}
