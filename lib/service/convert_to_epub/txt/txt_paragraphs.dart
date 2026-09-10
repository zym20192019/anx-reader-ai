/// Reconstructs logical paragraphs from physical TXT lines.
///
/// TXT files commonly contain hard-wrapped lines (sometimes with one blank
/// line after every physical line). A physical newline is therefore not
/// automatically a paragraph boundary. This helper keeps the conversion
/// deterministic and independent from preferences, files, or Flutter state.
final RegExp _chapterHeadingPattern = RegExp(
  r'^(?:(?:第[一二三四五六七八九十零〇百千万两0123456789]+(?:章|节|卷|部|篇|回|集)).*|(?:卷|部|篇)[一二三四五六七八九十零〇百千万两0123456789]+.*|(?:序章|楔子|前言|后记|番外(?:篇)?).*|(?:内容)?简介.*|作者[：:].*|(?:chapter|chap|volume|vol|book|bk)\.?\s+(?:\d+|[ivxlcdm]+)(?:\s*[:：.\-].*|\s+.*)?)$',
  caseSensitive: false,
);

final RegExp _dividerPattern = RegExp(r'^[\-_=*~—·•.＊－＝＿]{3,}$');
final RegExp _soundEffectPattern = RegExp(r'^(?:[哒嗒咚砰呼哈嗯啊唔呜]+[～~…！!。]*)$');
final RegExp _completeQuotedLinePattern = RegExp(
  r'''^[“"‘'「『《〈【（(].*[”"’'」』》〉】）)]$''',
);
final RegExp _metadataLabelPattern = RegExp(
  r'^(?:书名|作者|作家|简介|内容简介|题材|标签|类型|分类|修改|发布|来源|说明|序言|前言)[：:].*$',
  caseSensitive: false,
);
final RegExp _sentenceEndPattern = RegExp(
  r'[。！？!?；;…\.」』”’）》)\]}]+$',
);
final RegExp _latinWordEndPattern = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ0-9]$');
final RegExp _latinWordStartPattern = RegExp(r'^[A-Za-zÀ-ÖØ-öø-ÿ0-9]');
final RegExp _latinPunctuationEndPattern =
    RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ0-9][,;:，、]$');

class _FixedWidthProfile {
  const _FixedWidthProfile({required this.width});

  final int width;
}

String _normalizeLine(String line) {
  return line.replaceFirst('\uFEFF', '').trim();
}

bool _isStandaloneLine(String line) {
  return _chapterHeadingPattern.hasMatch(line) ||
      _dividerPattern.hasMatch(line) ||
      _soundEffectPattern.hasMatch(line) ||
      _completeQuotedLinePattern.hasMatch(line) ||
      _metadataLabelPattern.hasMatch(line);
}

bool _endsLogicalSentence(String line) {
  final trimmed = line.trimRight();
  if (trimmed.isEmpty || trimmed.endsWith('…') || trimmed.endsWith('...')) {
    return false;
  }
  return _sentenceEndPattern.hasMatch(trimmed);
}

bool _needsLatinSpace(String left, String right) {
  if (left.isEmpty || right.isEmpty) {
    return false;
  }

  if (left.endsWith('-') || left.endsWith('‐') || left.endsWith('‑')) {
    return false;
  }

  if (!_latinWordStartPattern.hasMatch(right)) {
    return false;
  }

  return _latinWordEndPattern.hasMatch(left) ||
      _latinPunctuationEndPattern.hasMatch(left);
}

String _joinWrappedLines(String left, String right) {
  if (_needsLatinSpace(left, right)) {
    return '$left $right';
  }
  return '$left$right';
}

_FixedWidthProfile? _detectFixedWidth(List<String> rawLines) {
  final lines = rawLines
      .map(_normalizeLine)
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.length < 4) {
    return null;
  }

  final widthCounts = <int, int>{};
  for (final line in lines) {
    final length = line.length;
    if (length >= 24 && length <= 120) {
      widthCounts[length] = (widthCounts[length] ?? 0) + 1;
    }
  }
  if (widthCounts.isEmpty) {
    return null;
  }

  final dominantWidth = widthCounts.entries.reduce(
    (left, right) => left.value >= right.value ? left : right,
  ).key;
  final nearDominantCount = lines
      .where((line) => (line.length - dominantWidth).abs() <= 1)
      .length;
  final nearDominantShare = nearDominantCount / lines.length;

  var blankGapCount = 0;
  var singleBlankGapCount = 0;
  var blankRun = 0;
  for (final rawLine in rawLines) {
    if (rawLine.trim().isEmpty) {
      blankRun++;
      continue;
    }

    if (blankRun > 0) {
      blankGapCount++;
      if (blankRun == 1) {
        singleBlankGapCount++;
      }
    }
    blankRun = 0;
  }

  final singleBlankShare = blankGapCount == 0
      ? 0.0
      : singleBlankGapCount / blankGapCount;

  // A fixed-width export normally has a single blank after each physical
  // line. Require both signals so ordinary one-paragraph-per-line TXT files
  // are not merged merely because they use similar lengths.
  if (blankGapCount > 0) {
    if (singleBlankShare >= 0.65 && nearDominantShare >= 0.30) {
      return _FixedWidthProfile(width: dominantWidth);
    }
  } else if (nearDominantShare >= 0.60) {
    return _FixedWidthProfile(width: dominantWidth);
  }

  return null;
}

bool _shouldBreakFixedWidthParagraph({
  required String previousLine,
  required _FixedWidthProfile profile,
}) {
  // A short physical line ending in punctuation is usually the final line of
  // a paragraph. Full-width lines stay open because punctuation can occur at
  // a hard-wrap boundary.
  return previousLine.length < profile.width &&
      _endsLogicalSentence(previousLine);
}

/// Returns non-empty logical paragraphs reconstructed from [input].
List<String> reconstructParagraphs(String input) {
  final normalized = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final rawLines = normalized.split('\n');
  final lines = rawLines.map(_normalizeLine).toList(growable: false);
  final fixedWidth = _detectFixedWidth(rawLines);
  final paragraphs = <String>[];
  var buffer = StringBuffer();
  var blankRun = 0;
  String? previousPhysicalLine;

  void flushBuffer() {
    final paragraph = buffer.toString().trim();
    if (paragraph.isNotEmpty) {
      paragraphs.add(paragraph);
    }
    buffer = StringBuffer();
    previousPhysicalLine = null;
  }

  for (final line in lines) {
    if (line.isEmpty) {
      blankRun++;
      continue;
    }

    if (fixedWidth != null) {
      // One blank is a physical-wrap artifact in this document shape; two or
      // more blanks remain an explicit paragraph boundary.
      if (blankRun > 1) {
        flushBuffer();
      }
    } else if (blankRun > 0) {
      // In ordinary TXT files a blank line is an intentional boundary.
      flushBuffer();
    }
    blankRun = 0;

    if (_isStandaloneLine(line)) {
      flushBuffer();
      paragraphs.add(line);
      continue;
    }

    if (buffer.isEmpty) {
      buffer.write(line);
      previousPhysicalLine = line;
      continue;
    }

    final shouldBreak = fixedWidth != null
        ? _shouldBreakFixedWidthParagraph(
            previousLine: previousPhysicalLine ?? buffer.toString(),
            profile: fixedWidth,
          )
        : _endsLogicalSentence(previousPhysicalLine ?? buffer.toString());

    if (shouldBreak) {
      flushBuffer();
      buffer.write(line);
    } else {
      buffer.write(_joinWrappedLines(buffer.toString(), line));
    }
    previousPhysicalLine = line;
  }

  flushBuffer();
  return paragraphs;
}
