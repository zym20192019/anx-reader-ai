import 'dart:math' as math;

import 'package:anx_reader/service/convert_to_epub/section.dart';

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

String _indent(int level) => '  ' * (level + 1);

/// Formats a fallback TOC title from section content.
///
/// Takes the first non-empty line of [content], collapses consecutive whitespace
/// (including ideographic fullwidth spaces), trims, and truncates to [maxLength]
/// Unicode characters (appending '...' if truncated).
///
/// Returns 'Section ${index + 1}' if the content contains no non-empty text.
String formatTocFallbackTitle(
  String content, {
  int? index,
  int maxLength = 30,
}) {
  final firstLine = content.split('\n').firstWhere(
        (line) => line.trim().isNotEmpty,
        orElse: () => '',
      );

  final normalized = firstLine.replaceAll(RegExp(r'[\s\u3000]+'), ' ').trim();
  if (normalized.isEmpty) {
    return 'Section ${index != null ? index + 1 : 1}';
  }

  final runes = normalized.runes.toList();
  if (runes.length <= maxLength) {
    return normalized;
  }

  return '${String.fromCharCodes(runes.take(maxLength))}...';
}

/// Resolves the title for a TOC entry.
///
/// If [section.title] is present and non-empty, it is used without truncation
/// to preserve authentic chapter titles.
/// If [section.title] is empty or whitespace-only, a fallback title is derived
/// from [section.content] via [formatTocFallbackTitle].
String resolveTocTitle(
  Section section,
  int index, {
  int maxLength = 30,
}) {
  final explicitTitle = section.title.trim();
  if (explicitTitle.isNotEmpty) {
    return explicitTitle;
  }
  return formatTocFallbackTitle(
    section.content,
    index: index,
    maxLength: maxLength,
  );
}

String generateNestedToc(List<Section> sections) {
  if (sections.isEmpty) {
    return '';
  }

  final tocItems = List.generate(sections.length, (index) {
    final section = sections[index];
    final title = resolveTocTitle(section, index);
    final level = section.level < 1 ? 1 : section.level;

    return _TocItem(title: title, index: index, level: level);
  });

  final positiveLevels = tocItems
      .where((item) => item.level > 0)
      .map((item) => item.level)
      .toList();

  if (positiveLevels.isNotEmpty) {
    final baseLevel = positiveLevels.reduce(math.min);
    for (final item in tocItems) {
      item.level = item.level - baseLevel + 1;
    }
  } else {
    for (final item in tocItems) {
      item.level = 1;
    }
  }

  final buffer = StringBuffer();
  final levelStack = <int>[];
  var playOrder = 1;

  for (final item in tocItems) {
    final level = item.level.clamp(1, 6);

    while (levelStack.isNotEmpty && level <= levelStack.last) {
      final closingLevel = levelStack.removeLast();
      buffer.writeln('${_indent(closingLevel)}</navPoint>');
    }

    buffer.write(_indent(level));
    buffer.writeln(
        '<navPoint id="navPoint-${item.index}" playOrder="$playOrder">');
    buffer.write(_indent(level));
    buffer.writeln(
        '  <navLabel><text>${_escapeXml(item.title)}</text></navLabel>');
    buffer.write(_indent(level));
    buffer.writeln('  <content src="xhtml/${item.index}.xhtml"/>');
    levelStack.add(level);
    playOrder += 1;
  }

  while (levelStack.isNotEmpty) {
    final closingLevel = levelStack.removeLast();
    buffer.writeln('${_indent(closingLevel)}</navPoint>');
  }

  return buffer.toString();
}

class _TocItem {
  _TocItem({
    required this.title,
    required this.index,
    required this.level,
  });

  final String title;
  final int index;
  int level;
}
