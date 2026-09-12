import 'dart:convert';
import 'package:anx_reader/models/chapter_split_rule.dart';
import 'package:crypto/crypto.dart';

/// Default parser version for TXT chapter parsing and caching.
const String kTxtParserVersion = '1.0.0';

/// Stably serializes a chapter split rule into a canonical string.
/// Returns null if the rule is empty or invalid.
String? serializeRuleStably(dynamic rule) {
  if (rule == null) {
    return null;
  }

  if (rule is String) {
    final trimmed = rule.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  if (rule is ChapterSplitRule) {
    final trimmedPattern = rule.pattern.trim();
    if (trimmedPattern.isEmpty) {
      return null;
    }
    final canonicalMap = {
      'caseSensitive': rule.caseSensitive,
      'multiLine': rule.multiLine,
      'pattern': trimmedPattern,
    };
    return jsonEncode(canonicalMap);
  }

  if (rule is Map) {
    if (rule.isEmpty) {
      return null;
    }
    final sortedMap = _canonicalizeMap(rule);
    if (sortedMap.isEmpty) {
      return null;
    }
    return jsonEncode(sortedMap);
  }

  if (rule is Iterable) {
    if (rule.isEmpty) {
      return null;
    }
    final items = <dynamic>[];
    for (final item in rule) {
      final serializedItem = serializeRuleStably(item);
      if (serializedItem != null) {
        items.add(jsonDecode(serializedItem));
      }
    }
    if (items.isEmpty) {
      return null;
    }
    return jsonEncode(items);
  }

  try {
    final dynamic map = (rule as dynamic).toMap?.call() ??
        (rule as dynamic).toJson?.call();
    if (map != null) {
      return serializeRuleStably(map);
    }
  } catch (_) {
    // If reflection-like dynamic calls fail, fall back to toString
  }

  final fallback = rule.toString().trim();
  return fallback.isEmpty ? null : fallback;
}

Map<String, dynamic> _canonicalizeMap(Map map) {
  final sortedKeys = map.keys.map((k) => k.toString()).toList()..sort();
  final result = <String, dynamic>{};
  for (final key in sortedKeys) {
    final value = map[key];
    if (value is Map) {
      result[key] = _canonicalizeMap(value);
    } else if (value is Iterable) {
      result[key] = value.toList();
    } else {
      result[key] = value;
    }
  }
  return result;
}

/// Generates a deterministic cache fingerprint for a TXT document.
///
/// Requires a non-empty [sourceMd5] and a valid [rule].
/// Returns null if [sourceMd5] is empty/whitespace or if [rule] is invalid/empty.
String? generateTxtCacheFingerprint({
  required String? sourceMd5,
  required dynamic rule,
  String parserVersion = kTxtParserVersion,
}) {
  if (sourceMd5 == null) {
    return null;
  }
  final normalizedMd5 = sourceMd5.trim().toLowerCase();
  if (normalizedMd5.isEmpty) {
    return null;
  }

  final serializedRule = serializeRuleStably(rule);
  if (serializedRule == null || serializedRule.trim().isEmpty) {
    return null;
  }

  final canonicalPayload =
      'v=$parserVersion|md5=$normalizedMd5|rule=$serializedRule';
  return sha256.convert(utf8.encode(canonicalPayload)).toString();
}

/// Pure data contract representing a validated TXT cache key.
class TxtCacheKey {
  final String sourceMd5;
  final dynamic rule;
  final String parserVersion;
  final String? serializedRule;
  final bool isValid;
  final String? fingerprint;
  final String? canonicalKey;

  TxtCacheKey({
    required this.sourceMd5,
    required this.rule,
    this.parserVersion = kTxtParserVersion,
  })  : serializedRule = serializeRuleStably(rule),
        isValid = (sourceMd5.trim().isNotEmpty &&
            serializeRuleStably(rule) != null &&
            serializeRuleStably(rule)!.trim().isNotEmpty),
        fingerprint = generateTxtCacheFingerprint(
          sourceMd5: sourceMd5,
          rule: rule,
          parserVersion: parserVersion,
        ),
        canonicalKey = (sourceMd5.trim().isNotEmpty &&
                serializeRuleStably(rule) != null)
            ? 'v=$parserVersion|md5=${sourceMd5.trim().toLowerCase()}|rule=${serializeRuleStably(rule)}'
            : null;

  Map<String, dynamic> toMap() {
    return {
      'sourceMd5': sourceMd5,
      'rule': serializedRule,
      'parserVersion': parserVersion,
      'fingerprint': fingerprint,
      'isValid': isValid,
    };
  }

  factory TxtCacheKey.fromMap(Map<String, dynamic> map) {
    return TxtCacheKey(
      sourceMd5: map['sourceMd5'] as String? ?? '',
      rule: map['rule'],
      parserVersion: map['parserVersion'] as String? ?? kTxtParserVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TxtCacheKey &&
          runtimeType == other.runtimeType &&
          sourceMd5.trim().toLowerCase() ==
              other.sourceMd5.trim().toLowerCase() &&
          serializedRule == other.serializedRule &&
          parserVersion == other.parserVersion;

  @override
  int get hashCode => Object.hash(
        sourceMd5.trim().toLowerCase(),
        serializedRule,
        parserVersion,
      );

  @override
  String toString() {
    return 'TxtCacheKey(sourceMd5: $sourceMd5, parserVersion: $parserVersion, fingerprint: $fingerprint, isValid: $isValid)';
  }
}
