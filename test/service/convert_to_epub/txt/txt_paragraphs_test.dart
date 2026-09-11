import 'package:anx_reader/service/convert_to_epub/txt/txt_paragraphs.dart';
import 'package:test/test.dart';

void main() {
  group('TXT paragraph reconstruction', () {
    test('joins fixed-width Chinese wraps until a real paragraph boundary', () {
      const source = '''
这是一个被固定宽度截断的句
子，后面仍然属于同一段。
这里是第二段的开头，内容在
下一行结束。
''';

      expect(
        reconstructParagraphs(source),
        equals([
          '这是一个被固定宽度截断的句子，后面仍然属于同一段。',
          '这里是第二段的开头，内容在下一行结束。',
        ]),
      );
    });

    test('keeps blank-line paragraph boundaries without empty paragraphs', () {
      const source = '第一段第一句。\n第一段第二句。\n\n\n第二段内容。\n';

      expect(
        reconstructParagraphs(source),
        equals([
          '第一段第一句。',
          '第一段第二句。',
          '第二段内容。',
        ]),
      );
    });

    test('does not merge already paragraphized dialogue and prose lines', () {
      const source = '''
第一章
“咳咳……”
波涛滚滚，冲刷着一望无际的沙滩。
呛得他一阵剧烈的咳嗽。
“什么情况？”
''';

      expect(
        reconstructParagraphs(source),
        equals([
          '第一章',
          '“咳咳……”',
          '波涛滚滚，冲刷着一望无际的沙滩。',
          '呛得他一阵剧烈的咳嗽。',
          '“什么情况？”',
        ]),
      );
    });

    test('joins CJK without a space and Latin words with a space', () {
      const source = '这是一段被截\n断的中文。\nThis is a wrapped\nsentence.';

      expect(
        reconstructParagraphs(source),
        equals([
          '这是一段被截断的中文。',
          'This is a wrapped sentence.',
        ]),
      );
    });

    test('keeps headings and divider lines as standalone blocks', () {
      const source = '第一章\n正文内容。\n--------------------\n第二章\n更多内容。';

      expect(
        reconstructParagraphs(source),
        equals([
          '第一章',
          '正文内容。',
          '--------------------',
          '第二章',
          '更多内容。',
        ]),
      );
    });

    test('preserves a longer blank run as a paragraph boundary', () {
      const source =
          '第一句没有结束所以\n继续同一段。\n\n\n下一段从这里开始。';

      expect(
        reconstructParagraphs(source),
        equals(['第一句没有结束所以继续同一段。', '下一段从这里开始。']),
      );
    });

    test('keeps ordinary one-line paragraphs separate', () {
      const source = '第一句。\n第二句。\n第三句。';

      expect(
        reconstructParagraphs(source),
        equals(['第一句。', '第二句。', '第三句。']),
      );
    });

    test('keeps long complete lines separate inside fixed-width-shaped text', () {
      const source = '''
这是一个固定宽度的短行内容，结尾继续。
这是一个超过检测宽度很多的完整段落，它本来就已经是完整的一段文字，不应该因为后面还有一个空行就和下一段拼接起来。

下一段从这里开始。''';

      expect(
        reconstructParagraphs(source),
        equals([
          '这是一个固定宽度的短行内容，结尾继续。',
          '这是一个超过检测宽度很多的完整段落，它本来就已经是完整的一段文字，不应该因为后面还有一个空行就和下一段拼接起来。',
          '下一段从这里开始。',
        ]),
      );
    });

    test('recognizes English chapter headings', () {
      const source = 'Chapter 1: Beginning\n正文内容。\nBook 2 - Next';

      expect(
        reconstructParagraphs(source),
        equals(['Chapter 1: Beginning', '正文内容。', 'Book 2 - Next']),
      );
    });

    test('keeps complete quoted dialogue separate from following prose', () {
      const source = '“咳咳……”\n波涛滚滚，冲刷着一望无际的沙滩。';

      expect(
        reconstructParagraphs(source),
        equals([
          '“咳咳……”',
          '波涛滚滚，冲刷着一望无际的沙滩。',
        ]),
      );
    });

    test('keeps metadata labels separate from their following value', () {
      const source = '题材：校园\n标签：成长\n简介：这是简介。';

      expect(
        reconstructParagraphs(source),
        equals(['题材：校园', '标签：成长', '简介：这是简介。']),
      );
    });

    test('joins a short hard-wrapped tail instead of creating a new block', () {
      const source = '这一段在固定宽度处被截断了所\n以这里是短尾。';

      expect(
        reconstructParagraphs(source),
        equals(['这一段在固定宽度处被截断了所以这里是短尾。']),
      );
    });

    test('joins 3+ consecutive hard-wrapped Chinese lines without exponential duplication', () {
      const source = '''
这是第一行没有标点的文本内容
这是第二行紧接着第一行的文本
这是第三行继续延展的文本内容
这是第四行最后在句号结束。''';

      expect(
        reconstructParagraphs(source),
        equals([
          '这是第一行没有标点的文本内容这是第二行紧接着第一行的文本这是第三行继续延展的文本内容这是第四行最后在句号结束。',
        ]),
      );
    });

    test('joins 3+ consecutive hard-wrapped English lines with single spaces', () {
      const source = '''
This is the first physical line
and this is the second line
and this is the third line
finishing the paragraph here.''';

      expect(
        reconstructParagraphs(source),
        equals([
          'This is the first physical line and this is the second line and this is the third line finishing the paragraph here.',
        ]),
      );
    });

    test('joins 3+ consecutive hard-wrapped lines with hyphenation without extra space', () {
      const source = '''
This represents an inter-
national organi-
zation in modern times.''';

      expect(
        reconstructParagraphs(source),
        equals([
          'This represents an inter-national organi-zation in modern times.',
        ]),
      );
    });
  });
}
