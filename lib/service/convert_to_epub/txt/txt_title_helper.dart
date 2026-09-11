/// Pure helpers for extracting display titles and authors from TXT filenames,
/// and producing safe filesystem path components.

/// Known modifier tags commonly found in web novel TXT filenames.
const Set<String> _knownModifierWords = {
  '精校',
  '精校版',
  '校对',
  '校对版',
  '完本',
  '完结',
  '完结版',
  '全本',
  '全集',
  '无错',
  '无错版',
  '精排',
  '精排版',
  '排版',
  '整理',
  '整理版',
  '修正',
  '修正版',
  '未删减',
  '未删减版',
  '无删减',
  '无删减版',
  '精编',
  '定稿',
  '手打',
  '手打版',
  '全本精校',
  '精校全本',
  '完本精校',
  '完结精校',
  '校对全本',
  'txt',
  'TXT',
};

/// Returns true if [content] is a known modifier/packaging tag rather than a title.
bool isModifierTag(String content) {
  final trimmed = content.trim();
  return _knownModifierWords.contains(trimmed) ||
      _knownModifierWords.contains(trimmed.toLowerCase());
}

/// Strips known bracketed modifier tags like `【精校】`, `[完本]`, `(精校版)`.
///
/// Brackets that contain actual book titles (e.g. `【诡秘之主】`) are preserved.
String stripModifierTags(String text) {
  final bracketPattern = RegExp(r'[【\[(（]([^【】\[\]()（）]+)[】\])）]');
  return text.replaceAllMapped(bracketPattern, (match) {
    final inner = match.group(1)?.trim() ?? '';
    if (isModifierTag(inner)) {
      return '';
    }
    return match.group(0)!;
  });
}

/// Strips empty bracket pairs (e.g. `《》`, `【】`, `[]`, `()`, `（）` and whitespace-only equivalents).
String stripEmptyBrackets(String text) {
  final emptyBracketPattern = RegExp(
    r'《[\s\u3000]*》|【[\s\u3000]*】|\[[\s\u3000]*\]|\([\s\u3000]*\)|（[\s\u3000]*）',
  );
  var result = text;
  while (emptyBracketPattern.hasMatch(result)) {
    result = result.replaceAll(emptyBracketPattern, '');
  }
  return result;
}

/// Extracts a clean display title from a raw TXT filename.
///
/// Retains authentic title semantics (such as Chinese colons, hyphens, and subtitles).
/// Recognizes explicit patterns:
/// - `《书名》`
/// - `【书名】`
/// - `[书名]`
/// - Strips leading `书名：` / `书名:` prefix
/// - Strips known packaging/modifier tags (`【精校】`, `[完本]`, etc.)
/// - Strips empty brackets (`《》`, `【】`, `[]`, etc.)
/// - Strips trailing author markers (`作者：XXX`, `原著：XXX`, `著：XXX`, including tightly attached)
String extractDisplayTitle(String rawFilename) {
  final trimmed = rawFilename.trim();
  if (trimmed.isEmpty) {
    return 'Unknown';
  }

  if (stripEmptyBrackets(trimmed).trim().isEmpty) {
    return 'Unknown';
  }

  // 1. Look for explicit 《书名》
  final titleMarkMatch = RegExp(r'《([^》]+)》').firstMatch(trimmed);
  if (titleMarkMatch != null) {
    var inner = titleMarkMatch.group(1)!.trim();
    inner = inner.replaceFirst(RegExp(r'^书名[：:]\s*'), '').trim();
    final cleanedInner = stripEmptyBrackets(stripModifierTags(inner)).trim();
    if (cleanedInner.isNotEmpty) {
      return cleanedInner;
    }
    if (inner.isNotEmpty && stripEmptyBrackets(inner).trim().isNotEmpty) {
      return inner;
    }
  }

  // 2. Strip known modifier tags and empty brackets from candidate string
  var candidate = stripModifierTags(trimmed).trim();
  candidate = stripEmptyBrackets(candidate).trim();
  if (candidate.isEmpty) {
    return 'Unknown';
  }

  // 3. Strip leading explicit "书名：" or "书名:"
  candidate = candidate.replaceFirst(RegExp(r'^书名[：:]\s*'), '').trim();

  // 4. Look for 【书名】 where the inner text is not a modifier tag
  final blackBracketMatch = RegExp(r'【([^】]+)】').firstMatch(candidate);
  if (blackBracketMatch != null) {
    final inner = blackBracketMatch.group(1)!.trim();
    if (inner.isNotEmpty &&
        !isModifierTag(inner) &&
        stripEmptyBrackets(inner).trim().isNotEmpty) {
      return inner;
    }
  }

  // 5. Look for [书名] where the inner text is not a modifier tag
  final squareBracketMatch = RegExp(r'\[([^\]]+)\]').firstMatch(candidate);
  if (squareBracketMatch != null) {
    final inner = squareBracketMatch.group(1)!.trim();
    if (inner.isNotEmpty &&
        !isModifierTag(inner) &&
        stripEmptyBrackets(inner).trim().isNotEmpty) {
      return inner;
    }
  }

  // 6. Strip trailing author segment if present (e.g. "雪中悍刀行 作者：烽火戏诸侯", "凡人修仙传作者：忘语", "凡人修仙传原著：忘语")
  // Allows tight author/原著/著 markers while preventing deletion of valid title compounds like "名著/专著/巨著/论著"
  candidate = candidate
      .replaceAll(
        RegExp(r'(?:[\s_]*(?:作者|原著|(?<![名专论巨原])著)\s*[：:].*)$'),
        '',
      )
      .trim();

  candidate = stripEmptyBrackets(candidate).trim();

  if (candidate.isNotEmpty) {
    return candidate;
  }

  return 'Unknown';
}

/// Extracts author name from a filename if present.
///
/// Recognizes `作者：XXX`, `作者: XXX`, `原著：XXX`, `原著: XXX`, `著：XXX`, `著: XXX`.
/// Trims trailing modifier tags or delimiters.
String extractAuthor(String filename) {
  final match = RegExp(
    r'(?:作者|原著|(?<![名专论巨原])著)[：:]\s*(.+?)(?:[\s_]*[\[【(（]|\s+(?:书名|出品)|$)',
  ).firstMatch(filename);

  if (match != null) {
    final author = match.group(1)?.trim() ?? '';
    final cleaned = stripModifierTags(author).trim();
    if (cleaned.isNotEmpty) {
      return cleaned;
    }
  }

  return 'Unknown';
}

/// Converts a title to a safe path component for filesystems.
///
/// - Replaces invalid path characters `/ \ : * ? " < > |` and control chars.
/// - Replaces Chinese fullwidth equivalent characters (`：？“”＂＜＞／＼｜＊`).
/// - Collapses consecutive whitespace and underscores.
/// - Trims leading/trailing periods, spaces, and underscores.
/// - Falls back to [fallback] if empty.
/// - Limits length to [maxLength] Unicode characters safely.
String toSafePathComponent(
  String title, {
  int maxLength = 50,
  String fallback = 'book',
}) {
  final trimmed = title.trim();
  if (trimmed.isEmpty) {
    return fallback;
  }

  // Replace illegal ASCII characters, control codes, and fullwidth equivalents
  var cleaned = trimmed.replaceAll(
    RegExp(r'[/\\:*?"<>|\x00-\x1F\x7F：？“”＂＜＞／＼｜＊]'),
    '_',
  );

  // Collapse consecutive whitespace and underscores into a single underscore
  cleaned = cleaned.replaceAll(RegExp(r'[\s_]+'), '_');

  // Strip leading and trailing underscores and dots (invalid on Windows)
  cleaned = cleaned.replaceAll(RegExp(r'^[_.]+|[_.]+$'), '');

  if (cleaned.isEmpty) {
    return fallback;
  }

  // Safely limit Unicode character length
  final runes = cleaned.runes.toList();
  if (runes.length > maxLength) {
    cleaned = String.fromCharCodes(runes.take(maxLength));
    cleaned = cleaned.replaceAll(RegExp(r'[_.]+$'), '');
    if (cleaned.isEmpty) {
      return fallback;
    }
  }

  return cleaned;
}
