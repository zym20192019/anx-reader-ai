/// Flutter integration tests for TXT file reading and encoding detection (`convert_from_txt.dart`).
///
/// Tests real file I/O, multi-encoding decoding (UTF-8, UTF-8 with BOM, GBK, Latin-1),
/// and error handling for corrupt binary files via `readFileWithEncoding`.
///
/// Test environment note:
/// Requires Flutter test runtime (`flutter test`) because `convert_from_txt.dart`
/// transitively imports Flutter UI and preferences (`shared_preference_provider.dart`, `AnxLog`).
/// Full end-to-end `convertFromTxt` execution in tests additionally requires Flutter binding
/// and platform channel mocks for `SharedPreferences` and `path_provider`.
///
/// Note: Tests are not claimed to have run locally because flutter and dart binaries
/// are not installed in this environment.
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/convert_to_epub/txt/convert_from_txt.dart';
import 'package:charset/charset.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('anx_txt_encoding_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('readFileWithEncoding (Flutter integration)', () {
    test('reads standard UTF-8 text', () {
      final file = File('${tempDir.path}/utf8.txt');
      file.writeAsStringSync('这是一段标准的UTF-8文本，包含中文和English。', encoding: utf8);

      final content = readFileWithEncoding(file);
      expect(content, equals('这是一段标准的UTF-8文本，包含中文和English。'));
    });

    test('reads UTF-8 text with BOM', () {
      final file = File('${tempDir.path}/utf8_bom.txt');
      final bom = [0xEF, 0xBB, 0xBF];
      final textBytes = utf8.encode('带BOM标记的文本');
      file.writeAsBytesSync([...bom, ...textBytes]);

      final content = readFileWithEncoding(file);
      expect(content, contains('带BOM标记的文本'));
    });

    test('reads GBK encoded Chinese text', () {
      final file = File('${tempDir.path}/gbk.txt');
      const original = '这是GBK编码的中文字符串，包含古典名句：有朋自远方来，不亦乐乎。';
      final gbkBytes = gbk.encode(original);
      file.writeAsBytesSync(gbkBytes);

      final content = readFileWithEncoding(file);
      expect(content, equals(original));
    });

    test('reads Latin-1 encoded text', () {
      final file = File('${tempDir.path}/latin1.txt');
      const original = 'Café résumé naïve façade';
      file.writeAsStringSync(original, encoding: latin1);

      final content = readFileWithEncoding(file);
      expect(content, equals(original));
    });

    test('throws Exception when file bytes cannot be decoded to meaningful text', () {
      final file = File('${tempDir.path}/corrupt.txt');
      final badBytes = List<int>.generate(600, (i) => (i % 256));
      file.writeAsBytesSync(badBytes);

      expect(() => readFileWithEncoding(file), throwsA(isA<Exception>()));
    });
  });
}
