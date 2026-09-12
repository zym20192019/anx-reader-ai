import 'package:anx_reader/models/book.dart';
import 'package:test/test.dart';

void main() {
  group('Book source and cache compatibility fields', () {
    test('default construction leaves new fields null and preserves existing fields', () {
      final now = DateTime(2026, 9, 12, 10, 0, 0);
      final book = Book(
        id: 1,
        title: 'Test Title',
        coverPath: 'cover/test.png',
        filePath: 'file/test.epub',
        lastReadPosition: 'epubcfi(/6/2)',
        readingPercentage: 0.25,
        author: 'Test Author',
        isDeleted: false,
        description: 'Test Description',
        rating: 4.5,
        groupId: 3,
        fileMd5: 'file_md5_abc',
        sourceMd5: 'source_md5_def',
        createTime: now,
        updateTime: now,
      );

      expect(book.sourceFilePath, isNull);
      expect(book.sourceFormat, isNull);
      expect(book.cacheFilePath, isNull);
      expect(book.cacheFingerprint, isNull);
      expect(book.sourceTextOffset, isNull);
      expect(book.sourceTextLength, isNull);
      expect(book.positionContext, isNull);

      // Existing fields preserved
      expect(book.filePath, equals('file/test.epub'));
      expect(book.lastReadPosition, equals('epubcfi(/6/2)'));
      expect(book.fileMd5, equals('file_md5_abc'));
      expect(book.sourceMd5, equals('source_md5_def'));
      expect(book.md5, equals('file_md5_abc'));
    });

    test('constructor accepts all new nullable fields', () {
      final now = DateTime(2026, 9, 12, 10, 0, 0);
      final book = Book(
        id: 2,
        title: 'Full Book',
        coverPath: 'cover/full.png',
        filePath: 'file/full.epub',
        lastReadPosition: '1500',
        readingPercentage: 0.5,
        author: 'Author',
        isDeleted: false,
        rating: 5.0,
        fileMd5: 'file_hash',
        sourceMd5: 'source_hash',
        sourceFilePath: 'file/full.txt',
        sourceFormat: 'txt',
        cacheFilePath: 'cache/full.epub',
        cacheFingerprint: 'fp_xyz123',
        sourceTextOffset: 1200,
        sourceTextLength: 45000,
        positionContext: '{"chapter": "Chapter 1"}',
        createTime: now,
        updateTime: now,
      );

      expect(book.sourceFilePath, equals('file/full.txt'));
      expect(book.sourceFormat, equals('txt'));
      expect(book.cacheFilePath, equals('cache/full.epub'));
      expect(book.cacheFingerprint, equals('fp_xyz123'));
      expect(book.sourceTextOffset, equals(1200));
      expect(book.sourceTextLength, equals(45000));
      expect(book.positionContext, equals('{"chapter": "Chapter 1"}'));
    });

    test('toMap and fromDb roundtrip with all new fields populated', () {
      final now = DateTime(2026, 9, 12, 12, 30, 0);
      final book = Book(
        id: 42,
        title: 'Roundtrip Book',
        coverPath: 'cover/42.png',
        filePath: 'file/42.epub',
        lastReadPosition: 'cfi_pos_42',
        readingPercentage: 0.75,
        author: 'Roundtrip Author',
        isDeleted: false,
        description: 'Roundtrip Desc',
        rating: 3.5,
        groupId: 1,
        fileMd5: 'file_md5_42',
        sourceMd5: 'source_md5_42',
        sourceFilePath: 'file/42.txt',
        sourceFormat: 'txt',
        cacheFilePath: 'cache/42.epub',
        cacheFingerprint: 'fingerprint_42',
        sourceTextOffset: 500,
        sourceTextLength: 20000,
        positionContext: 'context_snippet_42',
        createTime: now,
        updateTime: now,
      );

      final map = book.toMap();

      // Check map keys
      expect(map['title'], equals('Roundtrip Book'));
      expect(map['file_path'], equals('file/42.epub'));
      expect(map['source_md5'], equals('source_md5_42'));
      expect(map['file_md5'], equals('file_md5_42'));
      expect(map['source_file_path'], equals('file/42.txt'));
      expect(map['source_format'], equals('txt'));
      expect(map['cache_file_path'], equals('cache/42.epub'));
      expect(map['cache_fingerprint'], equals('fingerprint_42'));
      expect(map['source_text_offset'], equals(500));
      expect(map['source_text_length'], equals(20000));
      expect(map['position_context'], equals('context_snippet_42'));

      // Reconstruct with fromDb
      final dbMap = Map<String, dynamic>.from(map);
      dbMap['id'] = 42;
      final reconstructed = Book.fromDb(dbMap);

      expect(reconstructed.id, equals(book.id));
      expect(reconstructed.title, equals(book.title));
      expect(reconstructed.filePath, equals(book.filePath));
      expect(reconstructed.lastReadPosition, equals(book.lastReadPosition));
      expect(reconstructed.readingPercentage, equals(book.readingPercentage));
      expect(reconstructed.author, equals(book.author));
      expect(reconstructed.isDeleted, equals(book.isDeleted));
      expect(reconstructed.description, equals(book.description));
      expect(reconstructed.rating, equals(book.rating));
      expect(reconstructed.groupId, equals(book.groupId));
      expect(reconstructed.fileMd5, equals(book.fileMd5));
      expect(reconstructed.sourceMd5, equals(book.sourceMd5));
      expect(reconstructed.sourceFilePath, equals(book.sourceFilePath));
      expect(reconstructed.sourceFormat, equals(book.sourceFormat));
      expect(reconstructed.cacheFilePath, equals(book.cacheFilePath));
      expect(reconstructed.cacheFingerprint, equals(book.cacheFingerprint));
      expect(reconstructed.sourceTextOffset, equals(book.sourceTextOffset));
      expect(reconstructed.sourceTextLength, equals(book.sourceTextLength));
      expect(reconstructed.positionContext, equals(book.positionContext));
      expect(reconstructed.createTime, equals(book.createTime));
      expect(reconstructed.updateTime, equals(book.updateTime));
    });

    test('fromDb handles legacy row where new fields are missing or null', () {
      final legacyRow = <String, dynamic>{
        'id': 10,
        'title': 'Legacy v8 Book',
        'cover_path': 'cover/10.png',
        'file_path': 'file/10.epub',
        'last_read_position': '',
        'reading_percentage': 0.0,
        'author': 'Old Author',
        'is_deleted': 0,
        'description': null,
        'rating': 0.0,
        'group_id': 0,
        'file_md5': 'v8_file_hash',
        'source_md5': 'v8_source_hash',
        'create_time': DateTime.now().toIso8601String(),
        'update_time': DateTime.now().toIso8601String(),
        // New columns not present in the map at all
      };

      final book = Book.fromDb(legacyRow);

      expect(book.id, equals(10));
      expect(book.filePath, equals('file/10.epub'));
      expect(book.fileMd5, equals('v8_file_hash'));
      expect(book.sourceMd5, equals('v8_source_hash'));
      expect(book.sourceFilePath, isNull);
      expect(book.sourceFormat, isNull);
      expect(book.cacheFilePath, isNull);
      expect(book.cacheFingerprint, isNull);
      expect(book.sourceTextOffset, isNull);
      expect(book.sourceTextLength, isNull);
      expect(book.positionContext, isNull);
    });

    test('copyWith works correctly with new fields', () {
      final original = Book(
        id: 1,
        title: 'Original',
        coverPath: '',
        filePath: 'file/orig.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0.0,
        fileMd5: 'file_hash_1',
        sourceMd5: 'source_hash_1',
        sourceFilePath: 'file/orig.txt',
        sourceFormat: 'txt',
        cacheFilePath: 'cache/orig.epub',
        cacheFingerprint: 'fp_1',
        sourceTextOffset: 100,
        sourceTextLength: 1000,
        positionContext: 'ctx_1',
        createTime: DateTime(2026, 1, 1),
        updateTime: DateTime(2026, 1, 1),
      );

      // Partial copyWith updating only some new fields
      final updated = original.copyWith(
        sourceFilePath: 'file/new.txt',
        sourceTextOffset: 250,
        cacheFingerprint: 'fp_2',
      );

      expect(updated.sourceFilePath, equals('file/new.txt'));
      expect(updated.sourceTextOffset, equals(250));
      expect(updated.cacheFingerprint, equals('fp_2'));
      // Untouched new fields remain original
      expect(updated.sourceFormat, equals('txt'));
      expect(updated.cacheFilePath, equals('cache/orig.epub'));
      expect(updated.sourceTextLength, equals(1000));
      expect(updated.positionContext, equals('ctx_1'));
      // Untouched existing fields remain original
      expect(updated.filePath, equals('file/orig.epub'));
      expect(updated.fileMd5, equals('file_hash_1'));
      expect(updated.sourceMd5, equals('source_hash_1'));
    });
  });
}
