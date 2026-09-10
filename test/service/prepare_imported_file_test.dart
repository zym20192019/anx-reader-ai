import 'dart:io';

import 'package:anx_reader/service/prepare_imported_file.dart';
import 'package:test/test.dart';

void main() {
  group('prepareImportedFile', () {
    test('keeps the original TXT path and returns the converted artifact', () async {
      final source = File('/tmp/book.txt');
      final converted = File('/tmp/book.epub');

      final prepared = await prepareImportedFile(
        source,
        convertTxt: (_) async => converted,
      );

      expect(prepared.path, converted.path);
      expect(source.path, '/tmp/book.txt');
    });

    test('keeps TXT sources eligible for future re-conversion', () {
      expect(isTxtSource(File('/tmp/book.txt')), isTrue);
      expect(isTxtSource(File('/tmp/book.TXT')), isTrue);
      expect(shouldDeleteImportedInput(File('/tmp/book.txt')), isFalse);
      expect(shouldDeleteImportedInput(File('/tmp/book.epub')), isTrue);
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
