import 'package:anx_reader/service/convert_to_epub/generate_toc.dart';
import 'package:anx_reader/service/convert_to_epub/section.dart';
import 'package:test/test.dart';

void main() {
  group('formatTocFallbackTitle', () {
    test('truncates long first non-empty line to maxLength with ellipsis', () {
      const longContent = '''

天地不仁，以万物为刍狗；圣人不仁，以百姓为刍狗。此乃自古相传之天地大智慧也，其后更有无穷奥妙不可言说。
这是第二行正文内容。''';

      final fallback = formatTocFallbackTitle(longContent, maxLength: 30);
      expect(fallback.endsWith('...'), isTrue);
      // 30 characters plus '...'
      expect(fallback.runes.length, equals(33));
      expect(
        fallback,
        equals('天地不仁，以万物为刍狗；圣人不仁，以百姓为刍狗。此乃自古相传...'),
      );
    });

    test('does not truncate first line when within maxLength', () {
      const content = '前言与导读\n正文开始第一句。';
      final fallback = formatTocFallbackTitle(content, maxLength: 30);
      expect(fallback, equals('前言与导读'));
      expect(fallback.endsWith('...'), isFalse);
    });

    test('collapses consecutive whitespace and fullwidth spaces', () {
      const content = '   　　序言 　  背景与设定   \n正文内容';
      final fallback = formatTocFallbackTitle(content);
      expect(fallback, equals('序言 背景与设定'));
    });

    test('falls back to Section N for empty or whitespace-only content', () {
      expect(formatTocFallbackTitle('', index: 0), equals('Section 1'));
      expect(
        formatTocFallbackTitle('   \n\n  　　\n', index: 3),
        equals('Section 4'),
      );
      expect(formatTocFallbackTitle(''), equals('Section 1'));
    });
  });

  group('resolveTocTitle', () {
    test('preserves explicit chapter title without truncation even if long', () {
      const longExplicitTitle =
          '第一百二十章 这是一个极其极其极其极其极其极其极其极其极其极其极其极其长的正式章节标题';
      final section = Section(longExplicitTitle, '短正文', 1);

      final title = resolveTocTitle(section, 0, maxLength: 30);
      expect(title, equals(longExplicitTitle));
      expect(title.runes.length, greaterThan(30));
    });

    test('uses truncated fallback title when section title is empty', () {
      const longContent = '天地不仁，以万物为刍狗；圣人不仁，以百姓为刍狗。此乃自古相传之天地大智慧也。';
      final section = Section('', longContent, 1);

      final title = resolveTocTitle(section, 0, maxLength: 30);
      expect(title.endsWith('...'), isTrue);
      expect(
        title,
        equals('天地不仁，以万物为刍狗；圣人不仁，以百姓为刍狗。此乃自古相传...'),
      );
    });

    test('uses truncated fallback title when section title is only whitespace', () {
      const longContent = '天地不仁，以万物为刍狗；圣人不仁，以百姓为刍狗。此乃自古相传之天地大智慧也。';
      final section = Section('   　　 ', longContent, 1);

      final title = resolveTocTitle(section, 0, maxLength: 30);
      expect(title.endsWith('...'), isTrue);
      expect(
        title,
        equals('天地不仁，以万物为刍狗；圣人不仁，以百姓为刍狗。此乃自古相传...'),
      );
    });
  });

  group('generateNestedToc with fallback titles', () {
    test('formats nested TOC correctly with truncated fallback titles', () {
      final sections = [
        Section('', '第一行引言内容特别长，需要被截断成合理长度以保持目录整洁美观。\n第二行', 1),
        Section('第一章 破晓', '正文内容', 1),
      ];

      final toc = generateNestedToc(sections);
      expect(toc.contains('第一章 破晓'), isTrue);
      expect(toc.contains('第一行引言内容特别长，需要被截断成合理长度以保持目录整洁...'), isTrue);
      expect(toc.contains('<navPoint id="navPoint-0" playOrder="1">'), isTrue);
      expect(toc.contains('<navPoint id="navPoint-1" playOrder="2">'), isTrue);
    });
  });
}
