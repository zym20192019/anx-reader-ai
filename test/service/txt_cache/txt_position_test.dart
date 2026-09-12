import 'package:anx_reader/service/txt_cache/txt_position.dart';
import 'package:test/test.dart';

void main() {
  group('TxtPosition data model and clamping', () {
    test('constructs TxtPosition and calculates percentage correctly', () {
      const pos = TxtPosition(
        offset: 50,
        sourceLength: 100,
        contextHash: 'hash_123',
      );

      expect(pos.offset, equals(50));
      expect(pos.sourceLength, equals(100));
      expect(pos.contextHash, equals('hash_123'));
      expect(pos.percentage, equals(0.5));
      expect(pos.isClamped, isTrue);
    });

    test('percentage handles boundaries and zero/negative length safely', () {
      expect(
        const TxtPosition(offset: 0, sourceLength: 100).percentage,
        equals(0.0),
      );
      expect(
        const TxtPosition(offset: 100, sourceLength: 100).percentage,
        equals(1.0),
      );
      expect(
        const TxtPosition(offset: 150, sourceLength: 100).percentage,
        equals(1.0),
      );
      expect(
        const TxtPosition(offset: -10, sourceLength: 100).percentage,
        equals(0.0),
      );
      expect(
        const TxtPosition(offset: 10, sourceLength: 0).percentage,
        equals(0.0),
      );
      expect(
        const TxtPosition(offset: 10, sourceLength: -5).percentage,
        equals(0.0),
      );
    });

    test('clamp adjusts out-of-bound offsets', () {
      const underflow = TxtPosition(offset: -10, sourceLength: 100);
      expect(underflow.clamp().offset, equals(0));
      expect(underflow.isClamped, isFalse);
      expect(underflow.clamp().isClamped, isTrue);

      const overflow = TxtPosition(offset: 150, sourceLength: 100);
      expect(overflow.clamp().offset, equals(100));
      expect(overflow.isClamped, isFalse);
      expect(overflow.clamp().isClamped, isTrue);

      const zeroLength = TxtPosition(offset: 5, sourceLength: 0);
      expect(zeroLength.clamp().offset, equals(0));
      expect(zeroLength.clamp().sourceLength, equals(0));
    });

    test('TxtPosition.fromPercentage constructs clamped offset', () {
      final posMid = TxtPosition.fromPercentage(
        percentage: 0.5,
        sourceLength: 200,
      );
      expect(posMid.offset, equals(100));
      expect(posMid.percentage, equals(0.5));

      final posUnder = TxtPosition.fromPercentage(
        percentage: -0.2,
        sourceLength: 200,
      );
      expect(posUnder.offset, equals(0));

      final posOver = TxtPosition.fromPercentage(
        percentage: 1.5,
        sourceLength: 200,
      );
      expect(posOver.offset, equals(200));
    });

    test('serialization toMap and fromMap roundtrip', () {
      const pos = TxtPosition(
        offset: 1234,
        sourceLength: 5678,
        contextHash: 'abcd1234efgh',
      );

      final map = pos.toMap();
      final restored = TxtPosition.fromMap(map);

      expect(restored, equals(pos));
      expect(restored.offset, equals(1234));
      expect(restored.sourceLength, equals(5678));
      expect(restored.contextHash, equals('abcd1234efgh'));
    });
  });

  group('UTF-16 code units, CJK, and emoji surrogate handling', () {
    test('CJK characters count 1 UTF-16 code unit per character', () {
      const text = '第一章 开始阅读';
      // 8 CJK characters including space
      expect(text.length, equals(8));
      expect(text.codeUnits.length, equals(8));

      final pos = TxtPosition.fromText(text, 4);
      expect(pos.offset, equals(4));
      expect(pos.sourceLength, equals(8));
      expect(pos.percentage, equals(0.5));
    });

    test('emoji surrogate pairs count as 2 UTF-16 code units', () {
      // '📖' is \uD83D\uDC56 (2 code units)
      const text = '书📖本';
      // '书' (1) + '📖' (2) + '本' (1) = 4 code units
      expect(text.length, equals(4));
      expect(text.codeUnits.length, equals(4));

      // Offset after '书' is 1
      expect(text.substring(0, 1), equals('书'));
      // Offset after '📖' is 3
      expect(text.substring(1, 3), equals('📖'));
      // Offset after '本' is 4
      expect(text.substring(3, 4), equals('本'));

      final posAtEmojiEnd = TxtPosition.fromText(text, 3);
      expect(posAtEmojiEnd.offset, equals(3));
      expect(posAtEmojiEnd.sourceLength, equals(4));
      expect(posAtEmojiEnd.percentage, equals(0.75));
    });

    test('detects and safely aligns offsets inside surrogate pairs', () {
      const text = 'A😀B';
      // 'A' (offset 0), '😀' (offsets 1, 2), 'B' (offset 3). Length: 4
      expect(isInsideSurrogatePair(text, 0), isFalse);
      expect(isInsideSurrogatePair(text, 1), isFalse);
      expect(isInsideSurrogatePair(text, 2), isTrue); // Inside the emoji
      expect(isInsideSurrogatePair(text, 3), isFalse);
      expect(isInsideSurrogatePair(text, 4), isFalse);

      // Align backward
      expect(alignOffsetToCodeUnitBoundary(text, 2, roundForward: false), equals(1));
      // Align forward
      expect(alignOffsetToCodeUnitBoundary(text, 2, roundForward: true), equals(3));
      // Normal offsets remain untouched
      expect(alignOffsetToCodeUnitBoundary(text, 1), equals(1));
      expect(alignOffsetToCodeUnitBoundary(text, 3), equals(3));
    });
  });

  group('Context window and context hash verification', () {
    const sampleText = '床前明月光，疑是地上霜。举头望明月，低头思故乡。';

    test('extracts context window around offset with radius clamping', () {
      // offset 0 (start)
      final startContext = extractContextWindow(sampleText, 0, radius: 5);
      expect(startContext, equals('床前明月光'));

      // offset at end
      final endContext = extractContextWindow(sampleText, sampleText.length, radius: 5);
      expect(endContext, equals('低头思故乡。'));

      // offset in middle
      final midOffset = 12; // '霜'
      final midContext = extractContextWindow(sampleText, midOffset, radius: 3);
      expect(midContext, equals('地上霜。举'));
    });

    test('extractContextWindow does not split surrogate pairs at boundaries', () {
      const emojiText = '开头😀中间🎉结尾';
      // '开头' (0..2), '😀' (2..4), '中间' (4..6), '🎉' (6..8), '结尾' (8..10)
      // Radius 1 around offset 3 would naively start at 2 and end at 4, spanning '😀'
      final context = extractContextWindow(emojiText, 3, radius: 1);
      expect(context, equals('😀'));
    });

    test('computeContextHash and verifyContextHash correctly validate matching text', () {
      const text = '白日依山尽，黄河入海流。欲穷千里目，更上一层楼。';
      final pos = TxtPosition.fromText(text, 10, contextRadius: 6);

      expect(pos.contextHash, isNotNull);
      expect(pos.verifyContext(text, radius: 6), isTrue);
      expect(
        verifyPositionContext(pos, text, radius: 6),
        isTrue,
      );
    });

    test('verifyContext fails when context does not match or has drifted', () {
      const originalText = '天地玄黄，宇宙洪荒。';
      const modifiedText = '天翻地覆，宇宙洪荒。';

      final pos = TxtPosition.fromText(originalText, 2, contextRadius: 4);

      expect(pos.verifyContext(originalText, radius: 4), isTrue);
      // At offset 2, modified text has '天翻地覆' instead of '天地玄黄'
      expect(pos.verifyContext(modifiedText, radius: 4), isFalse);
    });

    test('verifyContext handles empty text, null hash, and out of bounds', () {
      const posNoHash = TxtPosition(offset: 5, sourceLength: 20);
      expect(posNoHash.verifyContext('some random text here'), isFalse);

      const posWithHash = TxtPosition(offset: 5, sourceLength: 20, contextHash: 'fake');
      expect(posWithHash.verifyContext(''), isFalse);
    });
  });
}
