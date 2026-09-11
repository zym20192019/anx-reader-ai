import 'dart:io';

import 'package:anx_reader/service/prepare_imported_file.dart';
import 'package:test/test.dart';

void main() {
  group('prepareImportedFile', () {
    test('returns converted artifact without owning the original TXT', () async {
      final source = File('/tmp/book.txt');
      final converted = File('/tmp/book.epub');

      final prepared = await prepareImportedFile(
        source,
        convertTxt: (_) async => converted,
      );

      expect(prepared.path, converted.path);
      expect(source.path, '/tmp/book.txt');
    });

    test('does not infer deletion permission from extension', () {
      expect(shouldDeleteImportedInput(File('/tmp/book.txt')), isFalse);
      expect(shouldDeleteImportedInput(File('/tmp/book.epub')), isFalse);
      expect(shouldDeleteImportedInput(File('/tmp/book.pdf')), isFalse);
      expect(shouldDeleteImportedInput(File('/tmp/book.mobi')), isFalse);
      expect(
        shouldDeleteImportedInput(
          File('/tmp/app-created/book.epub'),
          ownsFile: true,
        ),
        isTrue,
      );
      expect(
        shouldDeleteImportedInput(
          File('/tmp/app-created/book.txt'),
          ownsFile: true,
        ),
        isTrue,
      );
      expect(
        shouldDeleteImportedInput(
          File(''),
          ownsFile: true,
        ),
        isFalse,
      );
    });

    test('isTxtSource detects variations of txt extension', () {
      expect(isTxtSource(File('/tmp/book.txt')), isTrue);
      expect(isTxtSource(File('/tmp/book.TXT')), isTrue);
      expect(isTxtSource(File('/tmp/book.Txt')), isTrue);
      expect(isTxtSource(File('/tmp/book.epub')), isFalse);
      expect(isTxtSource(File('/tmp/book.txt.bak')), isFalse);
    });

    test('passes non-TXT files through unchanged', () async {
      final source = File('/tmp/book.epub');

      final prepared = await prepareImportedFile(
        source,
        convertTxt: (_) async => fail('non-TXT files must not be converted'),
      );

      expect(identical(prepared, source), isTrue);
    });

    test('recognizes uppercase TXT extensions', () async {
      final source = File('/tmp/book.TXT');
      final converted = File('/tmp/book.epub');

      final prepared = await prepareImportedFile(
        source,
        convertTxt: (_) async => converted,
      );

      expect(prepared.path, converted.path);
    });
  });
}
