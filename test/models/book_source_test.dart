import 'package:anx_reader/models/book_source.dart';
import 'package:test/test.dart';

void main() {
  group('BookSourceFormat and isTxtSourceFormat', () {
    test('standard format constants are stable strings', () {
      expect(BookSourceFormat.txt, equals('txt'));
      expect(BookSourceFormat.epub, equals('epub'));
      expect(BookSourceFormat.pdf, equals('pdf'));
      expect(BookSourceFormat.mobi, equals('mobi'));
      expect(BookSourceFormat.azw3, equals('azw3'));
      expect(BookSourceFormat.fb2, equals('fb2'));
    });

    test('isTxtSourceFormat recognizes txt variations case-insensitively', () {
      expect(isTxtSourceFormat('txt'), isTrue);
      expect(isTxtSourceFormat('TXT'), isTrue);
      expect(isTxtSourceFormat('Txt'), isTrue);
      expect(isTxtSourceFormat('tXt'), isTrue);
      expect(isTxtSourceFormat('  txt  '), isTrue);
      expect(isTxtSourceFormat('.txt'), isTrue);
      expect(isTxtSourceFormat('.TXT'), isTrue);
      expect(isTxtSourceFormat('  .Txt  '), isTrue);
    });

    test('isTxtSourceFormat rejects non-txt formats, null, and empty strings', () {
      expect(isTxtSourceFormat(null), isFalse);
      expect(isTxtSourceFormat(''), isFalse);
      expect(isTxtSourceFormat('   '), isFalse);
      expect(isTxtSourceFormat('.'), isFalse);
      expect(isTxtSourceFormat('epub'), isFalse);
      expect(isTxtSourceFormat('EPUB'), isFalse);
      expect(isTxtSourceFormat('.pdf'), isFalse);
      expect(isTxtSourceFormat('mobi'), isFalse);
      expect(isTxtSourceFormat('text'), isFalse);
    });

    test('BookSourceFormat.normalize cleans and lowercases formats', () {
      expect(BookSourceFormat.normalize('TXT'), equals('txt'));
      expect(BookSourceFormat.normalize(' .EPUB '), equals('epub'));
      expect(BookSourceFormat.normalize('.pdf'), equals('pdf'));
      expect(BookSourceFormat.normalize(''), equals(''));
      expect(BookSourceFormat.normalize(null), equals(''));
      expect(BookSourceFormat.normalize('   '), equals(''));
    });
  });

  group('BookSource model', () {
    test('creates BookSource with required and optional fields', () {
      const source = BookSource(
        filePath: '/data/books/sample.txt',
        format: 'TXT',
        sourceMd5: 'd41d8cd98f00b204e9800998ecf8427e',
        length: 1024,
        encoding: 'utf-8',
      );

      expect(source.filePath, equals('/data/books/sample.txt'));
      expect(source.format, equals('TXT'));
      expect(source.sourceMd5, equals('d41d8cd98f00b204e9800998ecf8427e'));
      expect(source.length, equals(1024));
      expect(source.encoding, equals('utf-8'));
      expect(source.isTxt, isTrue);
      expect(source.normalizedFormat, equals('txt'));
    });

    test('BookSource.fromFilePath infers format and handles edge cases', () {
      final txtSource = BookSource.fromFilePath('/path/to/novel.TXT');
      expect(txtSource.isTxt, isTrue);
      expect(txtSource.normalizedFormat, equals('txt'));

      final epubSource = BookSource.fromFilePath('/path/to/novel.epub');
      expect(epubSource.isTxt, isFalse);
      expect(epubSource.normalizedFormat, equals('epub'));

      final overrideSource = BookSource.fromFilePath(
        '/path/to/novel.unknown',
        format: 'txt',
        sourceMd5: 'abc',
      );
      expect(overrideSource.isTxt, isTrue);
      expect(overrideSource.sourceMd5, equals('abc'));

      final noExtSource = BookSource.fromFilePath('/path/to/noextension');
      expect(noExtSource.format, equals(''));
      expect(noExtSource.isTxt, isFalse);
    });

    test('serialization toMap and fromMap roundtrip preserves data', () {
      final source = BookSource(
        filePath: 'C:/books/test.txt',
        format: 'txt',
        sourceMd5: '5d41402abc4b2a76b9719d911017c592',
        length: 2048,
        encoding: 'gbk',
      );

      final map = source.toMap();
      final restored = BookSource.fromMap(map);

      expect(restored, equals(source));
      expect(restored.filePath, equals(source.filePath));
      expect(restored.format, equals(source.format));
      expect(restored.sourceMd5, equals(source.sourceMd5));
      expect(restored.length, equals(source.length));
      expect(restored.encoding, equals(source.encoding));
    });

    test('copyWith updates specified fields only', () {
      const source = BookSource(
        filePath: '/original.txt',
        format: 'txt',
        sourceMd5: '123',
      );

      final updated = source.copyWith(
        filePath: '/updated.txt',
        length: 500,
      );

      expect(updated.filePath, equals('/updated.txt'));
      expect(updated.format, equals('txt'));
      expect(updated.sourceMd5, equals('123'));
      expect(updated.length, equals(500));
    });

    test('value equality and hashCode work correctly', () {
      const source1 = BookSource(
        filePath: '/a.txt',
        format: 'txt',
        sourceMd5: 'md5_1',
      );
      const source2 = BookSource(
        filePath: '/a.txt',
        format: 'TXT',
        sourceMd5: 'md5_1',
      );
      const source3 = BookSource(
        filePath: '/b.txt',
        format: 'txt',
        sourceMd5: 'md5_1',
      );

      expect(source1, equals(source2));
      expect(source1.hashCode, equals(source2.hashCode));
      expect(source1, isNot(equals(source3)));
    });
  });
}
