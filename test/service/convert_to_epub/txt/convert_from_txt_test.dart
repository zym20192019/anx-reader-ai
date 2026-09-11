import 'package:anx_reader/models/chapter_split_presets.dart';
import 'package:test/test.dart';

void main() {
  group('default chapter split pattern', () {
    final pattern = getDefaultChapterSplitRule().buildRegExp();

    test('matches headings with trailing ASCII whitespace', () {
      expect(pattern.hasMatch('第一章 '), isTrue);
      expect(pattern.hasMatch('第二章  '), isTrue);
    });

    test('matches headings with trailing ideographic whitespace', () {
      expect(pattern.hasMatch('第三章　'), isTrue);
    });

    test('matches traditional Chinese chapter numbering', () {
      expect(pattern.hasMatch('第一百二十三章 风起云涌'), isTrue);
      expect(pattern.hasMatch('第一回 甄士隐梦幻识通灵'), isTrue);
      expect(pattern.hasMatch('第1章 新的开始'), isTrue);
    });

    test('matches English chapter numbering', () {
      expect(pattern.hasMatch('Chapter 12: The Journey'), isTrue);
      expect(pattern.hasMatch('chap 3. another life'), isTrue);
      expect(pattern.hasMatch('Book 1 - Dawn of Era'), isTrue);
      expect(pattern.hasMatch('Vol.2 A new world'), isTrue);
      expect(pattern.hasMatch('bk 4 - outside sample'), isTrue);
    });

    test('rejects non-heading regular text lines', () {
      expect(pattern.hasMatch('这是正文里的第一句话，不是章节标题。'), isFalse);
      expect(pattern.hasMatch('今天天气很好，阳光明媚。'), isFalse);
    });
  });
}
