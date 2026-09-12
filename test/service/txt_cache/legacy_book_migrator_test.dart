import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/txt_cache/legacy_book_migrator.dart';
import 'package:test/test.dart';

void main() {
  final testTimestamp = DateTime(2026, 9, 12, 12, 0, 0);

  Book createTestBook({
    required int id,
    String title = 'Test Book',
    String filePath = 'file/test.epub',
    String? sourceFilePath,
    String? sourceFormat,
    String? sourceMd5,
    String? cacheFilePath,
    String? cacheFingerprint,
  }) {
    return Book(
      id: id,
      title: title,
      coverPath: 'cover/test.png',
      filePath: filePath,
      lastReadPosition: '',
      readingPercentage: 0.0,
      author: 'Test Author',
      isDeleted: false,
      rating: 0.0,
      sourceFilePath: sourceFilePath,
      sourceFormat: sourceFormat,
      sourceMd5: sourceMd5,
      cacheFilePath: cacheFilePath,
      cacheFingerprint: cacheFingerprint,
      createTime: testTimestamp,
      updateTime: testTimestamp,
    );
  }

  group('LegacyBookMigrator - Classification', () {
    test('classifies books with sourceFilePath and explicit sourceFormat as sourceBacked', () {
      final book = createTestBook(
        id: 1,
        sourceFilePath: 'file/novel.txt',
        sourceFormat: 'txt',
        sourceMd5: 'md5_1',
      );

      expect(classifyBook(book), equals(LegacyBookCategory.sourceBacked));
      expect(isSourceBacked(book), isTrue);
      expect(isPartialSource(book), isFalse);
      expect(isLegacy(book), isFalse);
      expect(isTxtSource(book), isTrue);
      expect(LegacyBookMigrator.resolveFormat(book), equals('txt'));
    });

    test('classifies books with sourceFilePath and inferrable extension as sourceBacked', () {
      final txtBook = createTestBook(
        id: 2,
        sourceFilePath: 'file/novel.txt',
        sourceFormat: null,
      );
      final epubBook = createTestBook(
        id: 3,
        sourceFilePath: 'file/manual.epub',
        sourceFormat: null,
      );
      final pdfBook = createTestBook(
        id: 4,
        sourceFilePath: r'file\document.PDF',
        sourceFormat: '',
      );

      expect(classifyBook(txtBook), equals(LegacyBookCategory.sourceBacked));
      expect(isTxtSource(txtBook), isTrue);
      expect(resolveBookSourceFormat(txtBook), equals('txt'));

      expect(classifyBook(epubBook), equals(LegacyBookCategory.sourceBacked));
      expect(isTxtSource(epubBook), isFalse);
      expect(resolveBookSourceFormat(epubBook), equals('epub'));

      expect(classifyBook(pdfBook), equals(LegacyBookCategory.sourceBacked));
      expect(isTxtSource(pdfBook), isFalse);
      expect(resolveBookSourceFormat(pdfBook), equals('pdf'));
    });

    test('classifies books with sourceMd5 but missing/empty sourceFilePath as partialSource', () {
      final partial1 = createTestBook(
        id: 10,
        sourceFilePath: null,
        sourceMd5: 'abc123md5',
        filePath: 'file/converted_cache.epub',
      );
      final partial2 = createTestBook(
        id: 11,
        sourceFilePath: '   ',
        sourceMd5: 'def456md5',
        filePath: 'file/legacy_record.epub',
      );

      expect(classifyBook(partial1), equals(LegacyBookCategory.partialSource));
      expect(isPartialSource(partial1), isTrue);
      expect(isSourceBacked(partial1), isFalse);
      expect(isLegacy(partial1), isFalse);

      expect(classifyBook(partial2), equals(LegacyBookCategory.partialSource));
      expect(isPartialSource(partial2), isTrue);
    });

    test('classifies books without sourceFilePath and sourceMd5 as legacy', () {
      final legacyBook = createTestBook(
        id: 20,
        filePath: 'file/legacy_epub.epub',
        sourceFilePath: null,
        sourceMd5: null,
        sourceFormat: null,
      );

      expect(classifyBook(legacyBook), equals(LegacyBookCategory.legacy));
      expect(isLegacy(legacyBook), isTrue);
      expect(isSourceBacked(legacyBook), isFalse);
      expect(isPartialSource(legacyBook), isFalse);
    });

    test('classifies books with indeterminable format and no extension as legacy', () {
      final unformatted = createTestBook(
        id: 21,
        sourceFilePath: 'file/blob_without_extension',
        sourceFormat: null,
        sourceMd5: null,
      );

      expect(classifyBook(unformatted), equals(LegacyBookCategory.legacy));
      expect(isLegacy(unformatted), isTrue);
    });
  });

  group('LegacyBookMigrator - TXT source detection & never guessing from EPUB', () {
    test('never guesses TXT from legacy EPUB file paths even if name has txt', () {
      final legacyEpub = createTestBook(
        id: 30,
        filePath: 'file/my_txt_notes.epub',
        sourceFilePath: null,
        sourceFormat: null,
      );
      final upperLegacyEpub = createTestBook(
        id: 31,
        filePath: r'file\NOVEL.EPUB',
        sourceFilePath: null,
        sourceFormat: null,
      );

      expect(isTxtSource(legacyEpub), isFalse);
      expect(isTxtSource(upperLegacyEpub), isFalse);
    });

    test('identifies TXT correctly from legacy record when filePath is directly .txt', () {
      final directTxt = createTestBook(
        id: 32,
        filePath: 'file/direct_book.txt',
        sourceFilePath: null,
        sourceFormat: null,
      );

      expect(isTxtSource(directTxt), isTrue);
    });

    test('identifies TXT when sourceFormat is explicitly txt (case and dot normalized)', () {
      final bookWithDot = createTestBook(
        id: 33,
        sourceFilePath: 'file/book_raw',
        sourceFormat: '.TXT',
      );

      expect(isTxtSource(bookWithDot), isTrue);
      expect(resolveBookSourceFormat(bookWithDot), equals('txt'));
    });
  });

  group('LegacyBookMigrator - Cache Backed Detection', () {
    test('detects cacheBacked by cacheFilePath or cacheFingerprint', () {
      final cachedByPath = createTestBook(
        id: 40,
        cacheFilePath: 'cache/txt_epub/hash1/generated.epub',
      );
      final cachedByFingerprint = createTestBook(
        id: 41,
        cacheFingerprint: 'sha256_fingerprint_value',
      );
      final noCache = createTestBook(
        id: 42,
        cacheFilePath: null,
        cacheFingerprint: '   ',
      );

      expect(isCacheBacked(cachedByPath), isTrue);
      expect(isCacheBacked(cachedByFingerprint), isTrue);
      expect(isCacheBacked(noCache), isFalse);
    });
  });

  group('LegacyBookMigrator - LegacyBookAuditReport', () {
    test('generates accurate immutable report for mixed book library', () {
      final books = [
        // Book 1: Source-backed TXT with cache
        createTestBook(
          id: 101,
          sourceFilePath: 'file/book1.txt',
          sourceFormat: 'txt',
          sourceMd5: 'md5_1',
          cacheFilePath: 'cache/txt_epub/h1/generated.epub',
          cacheFingerprint: 'fp1',
        ),
        // Book 2: Source-backed EPUB without cache
        createTestBook(
          id: 102,
          sourceFilePath: 'file/book2.epub',
          sourceFormat: 'epub',
          sourceMd5: 'md5_2',
        ),
        // Book 3: Partial-source book (has sourceMd5, no sourceFilePath)
        createTestBook(
          id: 103,
          sourceFilePath: null,
          sourceMd5: 'md5_3',
          filePath: 'file/converted_3.epub',
        ),
        // Book 4: Legacy EPUB book (no sourceFilePath, no sourceMd5)
        createTestBook(
          id: 104,
          filePath: 'file/legacy_4.epub',
          sourceFilePath: null,
          sourceMd5: null,
        ),
        // Book 5: Legacy TXT book (direct .txt filePath)
        createTestBook(
          id: 105,
          filePath: 'file/legacy_5.txt',
          sourceFilePath: null,
          sourceMd5: null,
        ),
      ];

      final report = LegacyBookMigrator.audit(books);

      expect(report.totalBooks, equals(5));
      expect(report.totalCount, equals(5));

      expect(report.sourceBackedCount, equals(2));
      expect(report.sourceBackedIds, equals([101, 102]));
      expect(report.sourceBackedBookIds, equals([101, 102]));

      expect(report.partialSourceCount, equals(1));
      expect(report.partialSourceIds, equals([103]));
      expect(report.partialSourceBookIds, equals([103]));

      expect(report.legacyCount, equals(2));
      expect(report.legacyIds, equals([104, 105]));
      expect(report.legacyBookIds, equals([104, 105]));

      expect(report.cacheBackedCount, equals(1));
      expect(report.cacheBackedIds, equals([101]));

      // TXT sources: Book 101 (sourceFilePath: txt) and Book 105 (filePath: txt).
      // Book 104 is an EPUB legacy and must NOT be counted as TXT.
      expect(report.txtSourceCount, equals(2));
      expect(report.txtSourceIds, equals([101, 105]));
    });

    test('audit report collections are strictly unmodifiable', () {
      final report = LegacyBookAuditReport.fromBooks([
        createTestBook(id: 1, sourceFilePath: 'file/a.txt', sourceFormat: 'txt'),
      ]);

      expect(() => report.sourceBackedIds.add(999), throwsUnsupportedError);
      expect(() => report.partialSourceIds.add(999), throwsUnsupportedError);
      expect(() => report.legacyIds.add(999), throwsUnsupportedError);
      expect(() => report.cacheBackedIds.add(999), throwsUnsupportedError);
      expect(() => report.txtSourceIds.add(999), throwsUnsupportedError);
    });

    test('empty factory creates zeroed report', () {
      final empty = LegacyBookAuditReport.empty();
      expect(empty.totalCount, equals(0));
      expect(empty.sourceBackedCount, equals(0));
      expect(empty.partialSourceCount, equals(0));
      expect(empty.legacyCount, equals(0));
      expect(empty.cacheBackedCount, equals(0));
      expect(empty.txtSourceCount, equals(0));
      expect(empty.sourceBackedIds, isEmpty);
      expect(empty.partialSourceIds, isEmpty);
      expect(empty.legacyIds, isEmpty);
      expect(empty.cacheBackedIds, isEmpty);
      expect(empty.txtSourceIds, isEmpty);
    });

    test('toMap provides diagnostic payload with counts and IDs', () {
      final report = LegacyBookMigrator.audit([
        createTestBook(id: 7, sourceFilePath: 'file/a.txt', sourceFormat: 'txt'),
      ]);
      final map = report.toMap();

      expect(map['totalBooks'], equals(1));
      expect(map['sourceBackedCount'], equals(1));
      expect(map['partialSourceCount'], equals(0));
      expect(map['legacyCount'], equals(0));
      expect(map['txtSourceCount'], equals(1));
      expect(map['sourceBackedIds'], equals([7]));
      expect(map['partialSourceIds'], isEmpty);
      expect(map['legacyIds'], isEmpty);
      expect(map['txtSourceIds'], equals([7]));
    });

    test('supports equality and toString', () {
      final bookA = createTestBook(id: 1, sourceFilePath: 'file/a.txt', sourceFormat: 'txt');
      final report1 = LegacyBookAuditReport.fromBooks([bookA]);
      final report2 = LegacyBookAuditReport.fromBooks([bookA]);

      expect(report1, equals(report2));
      expect(report1.hashCode, equals(report2.hashCode));
      expect(report1.toString(), contains('sourceBacked: 1'));
    });
  });

  group('listHistoricalRemoteEpubs', () {
    test('filters and normalizes paths under file/ with .epub extension', () {
      final remotePaths = [
        'file/history_1.epub',
        r'file\history_2.EPUB',
        '/file/history_3.epub',
        r'\file\history_4.Epub',
        '   file/history_5.epub   ',
        'file/current.txt',
        'file/data.pdf',
        'cover/history.epub',
        'cache/txt_epub/hash/generated.epub',
        'file/',
        '',
        '   ',
      ];

      final epubs = listHistoricalRemoteEpubs(remotePaths);

      expect(epubs, equals([
        'file/history_1.epub',
        'file/history_2.EPUB',
        'file/history_3.epub',
        'file/history_4.Epub',
        'file/history_5.epub',
      ]));
    });

    test('returns unmodifiable list and handles empty input', () {
      final result = listHistoricalRemoteEpubs([]);
      expect(result, isEmpty);
      expect(() => result.add('file/fail.epub'), throwsUnsupportedError);
    });

    test('static alias LegacyBookMigrator.listHistoricalRemoteEpubs matches pure function', () {
      final inputs = ['file/sample.epub', 'file/sample.txt'];
      expect(
        LegacyBookMigrator.listHistoricalRemoteEpubs(inputs),
        equals(listHistoricalRemoteEpubs(inputs)),
      );
    });
  });
}
