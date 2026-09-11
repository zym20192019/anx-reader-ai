import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/book.dart';
import 'package:test/test.dart';

/// Regression and verification suite for source_md5 and file_md5 logic.
///
/// NOTE:
/// Full end-to-end [importBook] and live [BookDao] execution depend on Flutter engine
/// runtime bindings, WebView bridges, and platform-channel sqflite databases.
/// As documented in the test plan, this test suite directly exercises real production
/// pure helper functions ([resolveBookMd5OnSave], [resolveBookMd5OnReplace]) and
/// model serialization ([Book.fromDb], [Book.toMap], [Book.copyWith]), without
/// creating fake in-memory DAO algorithms or asserting on source strings.
void main() {
  group('Database Schema Constants', () {
    test('currentDbVersion is bumped to 8 for source_md5 migration', () {
      expect(currentDbVersion, 8);
    });
  });

  group('resolveBookMd5OnSave (Production Helper)', () {
    test('New book import writes prepared fileMd5 and sourceMd5', () {
      final resolution = resolveBookMd5OnSave(
        isExistingBook: false,
        effectiveFileMd5: 'converted_epub_hash_111',
        effectiveSourceMd5: 'txt_source_hash_222',
        provideBook: null,
      );

      expect(resolution.fileMd5, 'converted_epub_hash_111');
      expect(resolution.sourceMd5, 'txt_source_hash_222');
    });

    test('Existing book hit preserves provideBook.fileMd5 and does NOT write temp prepared fileMd5', () {
      final existingBook = Book(
        id: 42,
        title: 'Existing Book',
        coverPath: 'cover/existing.png',
        filePath: 'file/existing.epub',
        lastReadPosition: '',
        readingPercentage: 0.1,
        author: 'Author',
        isDeleted: false,
        rating: 0.0,
        fileMd5: 'canonical_library_file_hash',
        sourceMd5: 'canonical_source_hash',
        createTime: DateTime(2026, 1, 1),
        updateTime: DateTime(2026, 1, 1),
      );

      final resolution = resolveBookMd5OnSave(
        isExistingBook: true,
        effectiveFileMd5: 'temp_unpersisted_epub_hash_999',
        effectiveSourceMd5: 'canonical_source_hash',
        provideBook: existingBook,
      );

      // fileMd5 MUST remain existing canonical file hash, never the unpersisted temp hash
      expect(resolution.fileMd5, 'canonical_library_file_hash');
      // sourceMd5 remains intact
      expect(resolution.sourceMd5, 'canonical_source_hash');
    });

    test('Legacy existing book without sourceMd5 adopts effectiveSourceMd5 on re-import while keeping fileMd5', () {
      final legacyBook = Book(
        id: 7,
        title: 'Legacy Book',
        coverPath: '',
        filePath: 'file/legacy.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Old Author',
        isDeleted: false,
        rating: 0.0,
        fileMd5: 'legacy_original_file_hash',
        sourceMd5: null, // Legacy v7 book
        createTime: DateTime(2025, 1, 1),
        updateTime: DateTime(2025, 1, 1),
      );

      final resolution = resolveBookMd5OnSave(
        isExistingBook: true,
        effectiveFileMd5: 'temp_epub_hash_reimport',
        effectiveSourceMd5: 'reimported_source_txt_hash',
        provideBook: legacyBook,
      );

      expect(resolution.fileMd5, 'legacy_original_file_hash');
      expect(resolution.sourceMd5, 'reimported_source_txt_hash');
    });

    test('Existing book keeps old sourceMd5 if effectiveSourceMd5 is null or empty', () {
      final existingBook = Book(
        id: 12,
        title: 'Book 12',
        coverPath: '',
        filePath: 'file/12.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0.0,
        fileMd5: 'file_hash_12',
        sourceMd5: 'source_hash_12',
        createTime: DateTime(2026, 1, 1),
        updateTime: DateTime(2026, 1, 1),
      );

      final resolutionNull = resolveBookMd5OnSave(
        isExistingBook: true,
        effectiveFileMd5: 'temp_file_hash',
        effectiveSourceMd5: null,
        provideBook: existingBook,
      );
      expect(resolutionNull.fileMd5, 'file_hash_12');
      expect(resolutionNull.sourceMd5, 'source_hash_12');

      final resolutionEmpty = resolveBookMd5OnSave(
        isExistingBook: true,
        effectiveFileMd5: 'temp_file_hash',
        effectiveSourceMd5: '',
        provideBook: existingBook,
      );
      expect(resolutionEmpty.fileMd5, 'file_hash_12');
      expect(resolutionEmpty.sourceMd5, 'source_hash_12');
    });
  });

  group('resolveBookMd5OnReplace (Production Helper)', () {
    test('Replacing with TXT file sets converted EPUB fileMd5 and new TXT sourceMd5', () {
      final resolution = resolveBookMd5OnReplace(
        isTxt: true,
        newSourceFileMd5: 'new_txt_hash_aaa',
        newProcessedFileMd5: 'converted_epub_hash_bbb',
      );

      expect(resolution.fileMd5, 'converted_epub_hash_bbb');
      expect(resolution.sourceMd5, 'new_txt_hash_aaa');
    });

    test('Replacing with non-TXT file sets both fileMd5 and sourceMd5 to the new file hash', () {
      final resolution = resolveBookMd5OnReplace(
        isTxt: false,
        newSourceFileMd5: 'new_epub_hash_ccc',
        newProcessedFileMd5: 'new_epub_hash_ccc',
      );

      expect(resolution.fileMd5, 'new_epub_hash_ccc');
      expect(resolution.sourceMd5, 'new_epub_hash_ccc');
    });
  });

  group('Book Model Serialization & copyWith', () {
    test('fromDb parses v7 legacy row with null source_md5', () {
      final v7Row = <String, dynamic>{
        'id': 100,
        'title': 'Legacy v7 Book',
        'cover_path': 'cover/100.png',
        'file_path': 'file/100.epub',
        'last_read_position': '',
        'reading_percentage': 0.0,
        'author': 'Author',
        'is_deleted': 0,
        'description': '',
        'rating': 0.0,
        'group_id': 0,
        'file_md5': 'v7_file_hash',
        'source_md5': null,
        'create_time': DateTime.now().toIso8601String(),
        'update_time': DateTime.now().toIso8601String(),
      };

      final book = Book.fromDb(v7Row);
      expect(book.fileMd5, 'v7_file_hash');
      expect(book.md5, 'v7_file_hash');
      expect(book.sourceMd5, isNull);
    });

    test('fromDb and toMap roundtrip with distinct fileMd5 and sourceMd5', () {
      final book = Book(
        id: 50,
        title: 'V8 Book',
        coverPath: 'cover/50.png',
        filePath: 'file/50.epub',
        lastReadPosition: 'pos',
        readingPercentage: 0.5,
        author: 'Author',
        isDeleted: false,
        rating: 4.5,
        groupId: 2,
        fileMd5: 'epub_disk_hash',
        sourceMd5: 'original_source_hash',
        createTime: DateTime(2026, 5, 1),
        updateTime: DateTime(2026, 5, 2),
      );

      final map = book.toMap();
      expect(map['file_md5'], 'epub_disk_hash');
      expect(map['source_md5'], 'original_source_hash');

      final reconstructed = Book.fromDb(map);
      expect(reconstructed.id, 50);
      expect(reconstructed.fileMd5, 'epub_disk_hash');
      expect(reconstructed.sourceMd5, 'original_source_hash');
    });

    test('copyWith updating fileMd5 retains sourceMd5', () {
      final book = Book(
        id: 1,
        title: 'Original',
        coverPath: '',
        filePath: 'file/1.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0.0,
        fileMd5: 'initial_file_md5',
        sourceMd5: 'initial_source_md5',
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      final updated = book.copyWith(fileMd5: 'new_file_md5');
      expect(updated.fileMd5, 'new_file_md5');
      expect(updated.sourceMd5, 'initial_source_md5');
    });

    test('copyWith can update sourceMd5 explicitly', () {
      final book = Book(
        id: 1,
        title: 'Original',
        coverPath: '',
        filePath: 'file/1.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0.0,
        fileMd5: 'file_md5',
        sourceMd5: 'old_source_md5',
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      final updated = book.copyWith(sourceMd5: 'new_source_md5');
      expect(updated.sourceMd5, 'new_source_md5');
      expect(updated.fileMd5, 'file_md5');
    });

    test('backward compatibility: md5 constructor argument sets fileMd5', () {
      final book = Book(
        id: 2,
        title: 'Compat',
        coverPath: '',
        filePath: 'file/compat.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Author',
        isDeleted: false,
        rating: 0.0,
        md5: 'legacy_call_hash',
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      expect(book.fileMd5, 'legacy_call_hash');
      expect(book.md5, 'legacy_call_hash');
      expect(book.sourceMd5, isNull);
    });
  });
}
