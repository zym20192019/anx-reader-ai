import 'package:anx_reader/models/chapter_split_rule.dart';
import 'package:anx_reader/service/txt_cache/txt_cache_key.dart';
import 'package:test/test.dart';

void main() {
  group('TxtCacheKey fingerprint generation', () {
    const validMd5 = 'd41d8cd98f00b204e9800998ecf8427e';
    const samplePattern = r'^第[0-9一二三四五六七八九十百千]+[章回节]';

    test('generates stable, deterministic fingerprint with valid inputs', () {
      final fp1 = generateTxtCacheFingerprint(
        sourceMd5: validMd5,
        rule: samplePattern,
        parserVersion: '1.0.0',
      );
      final fp2 = generateTxtCacheFingerprint(
        sourceMd5: validMd5,
        rule: samplePattern,
        parserVersion: '1.0.0',
      );

      expect(fp1, isNotNull);
      expect(fp1, isNotEmpty);
      expect(fp1, equals(fp2));
    });

    test('normalizes sourceMd5 case-insensitively and trims whitespace', () {
      final fpLower = generateTxtCacheFingerprint(
        sourceMd5: 'd41d8cd98f00b204e9800998ecf8427e',
        rule: samplePattern,
      );
      final fpUpper = generateTxtCacheFingerprint(
        sourceMd5: '  D41D8CD98F00B204E9800998ECF8427E  ',
        rule: samplePattern,
      );

      expect(fpLower, isNotNull);
      expect(fpUpper, equals(fpLower));
    });

    test('empty or whitespace sourceMd5 produces null fingerprint', () {
      expect(
        generateTxtCacheFingerprint(sourceMd5: '', rule: samplePattern),
        isNull,
      );
      expect(
        generateTxtCacheFingerprint(sourceMd5: '   ', rule: samplePattern),
        isNull,
      );
      expect(
        generateTxtCacheFingerprint(sourceMd5: null, rule: samplePattern),
        isNull,
      );
    });

    test('empty rule produces null fingerprint', () {
      expect(
        generateTxtCacheFingerprint(sourceMd5: validMd5, rule: null),
        isNull,
      );
      expect(
        generateTxtCacheFingerprint(sourceMd5: validMd5, rule: ''),
        isNull,
      );
      expect(
        generateTxtCacheFingerprint(sourceMd5: validMd5, rule: '   '),
        isNull,
      );
      expect(
        generateTxtCacheFingerprint(
          sourceMd5: validMd5,
          rule: const ChapterSplitRule(
            id: 'rule_1',
            name: 'Empty Rule',
            pattern: '   ',
            samples: [],
          ),
        ),
        isNull,
      );
      expect(
        generateTxtCacheFingerprint(sourceMd5: validMd5, rule: <String>[]),
        isNull,
      );
      expect(
        generateTxtCacheFingerprint(
          sourceMd5: validMd5,
          rule: <String, dynamic>{},
        ),
        isNull,
      );
    });

    test('different rules yield different fingerprints', () {
      final fp1 = generateTxtCacheFingerprint(
        sourceMd5: validMd5,
        rule: r'^第[0-9]+章',
      );
      final fp2 = generateTxtCacheFingerprint(
        sourceMd5: validMd5,
        rule: r'^Chapter \d+',
      );

      expect(fp1, isNotNull);
      expect(fp2, isNotNull);
      expect(fp1, isNot(equals(fp2)));
    });

    test('different parser versions yield different fingerprints', () {
      final fpV1 = generateTxtCacheFingerprint(
        sourceMd5: validMd5,
        rule: samplePattern,
        parserVersion: '1.0.0',
      );
      final fpV2 = generateTxtCacheFingerprint(
        sourceMd5: validMd5,
        rule: samplePattern,
        parserVersion: '2.0.0',
      );

      expect(fpV1, isNotNull);
      expect(fpV2, isNotNull);
      expect(fpV1, isNot(equals(fpV2)));
    });

    test('supports ChapterSplitRule and ensures canonical serialization', () {
      const rule1 = ChapterSplitRule(
        id: 'chinese_chapter',
        name: 'Chinese Chapters',
        pattern: samplePattern,
        samples: ['第一章 开始', '第10章 发展'],
        caseSensitive: false,
        multiLine: true,
      );

      const rule2 = ChapterSplitRule(
        id: 'chinese_chapter',
        name: 'Chinese Chapters',
        pattern: samplePattern,
        samples: ['其他样例'],
        caseSensitive: false,
        multiLine: true,
      );

      final fp1 = generateTxtCacheFingerprint(
        sourceMd5: validMd5,
        rule: rule1,
      );
      final fp2 = generateTxtCacheFingerprint(
        sourceMd5: validMd5,
        rule: rule2,
      );

      expect(fp1, isNotNull);
      // Samples do not affect split execution; canonical serialization produces identical fingerprint
      expect(fp1, equals(fp2));
    });

    test('Map rule with different key insertion orders produces identical fingerprint', () {
      final mapA = {'pattern': samplePattern, 'caseSensitive': false, 'multiLine': true};
      final mapB = {'caseSensitive': false, 'multiLine': true, 'pattern': samplePattern};

      final fpA = generateTxtCacheFingerprint(sourceMd5: validMd5, rule: mapA);
      final fpB = generateTxtCacheFingerprint(sourceMd5: validMd5, rule: mapB);

      expect(fpA, isNotNull);
      expect(fpA, equals(fpB));
    });
  });

  group('TxtCacheKey class', () {
    const validMd5 = 'd41d8cd98f00b204e9800998ecf8427e';
    const samplePattern = r'^第[0-9]+章';

    test('valid key has fingerprint and isValid == true', () {
      final key = TxtCacheKey(
        sourceMd5: validMd5,
        rule: samplePattern,
      );

      expect(key.isValid, isTrue);
      expect(key.fingerprint, isNotNull);
      expect(key.canonicalKey, contains(validMd5));
      expect(key.canonicalKey, contains(key.parserVersion));
    });

    test('invalid key has null fingerprint and isValid == false', () {
      final emptyMd5Key = TxtCacheKey(
        sourceMd5: '',
        rule: samplePattern,
      );
      expect(emptyMd5Key.isValid, isFalse);
      expect(emptyMd5Key.fingerprint, isNull);

      final emptyRuleKey = TxtCacheKey(
        sourceMd5: validMd5,
        rule: '   ',
      );
      expect(emptyRuleKey.isValid, isFalse);
      expect(emptyRuleKey.fingerprint, isNull);
    });

    test('supports serialization and deserialization', () {
      final key = TxtCacheKey(
        sourceMd5: validMd5,
        rule: samplePattern,
        parserVersion: '1.2.0',
      );

      final map = key.toMap();
      final restored = TxtCacheKey.fromMap(map);

      expect(restored.isValid, isTrue);
      expect(restored.sourceMd5, equals(key.sourceMd5));
      expect(restored.parserVersion, equals(key.parserVersion));
      expect(restored.fingerprint, equals(key.fingerprint));
      expect(restored, equals(key));
    });
  });
}
