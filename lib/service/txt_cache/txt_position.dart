import 'dart:convert';
import 'package:crypto/crypto.dart';

bool _isLeadSurrogate(int codeUnit) =>
    codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

bool _isTrailSurrogate(int codeUnit) =>
    codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

/// Checks if [offset] falls in the middle of a UTF-16 surrogate pair in [text].
bool isInsideSurrogatePair(String text, int offset) {
  if (offset <= 0 || offset >= text.length) {
    return false;
  }
  return _isLeadSurrogate(text.codeUnitAt(offset - 1)) &&
      _isTrailSurrogate(text.codeUnitAt(offset));
}

/// Aligns [offset] to avoid landing between surrogate pairs.
///
/// If [roundForward] is true, advances past the trail surrogate; otherwise,
/// steps back before the lead surrogate.
int alignOffsetToCodeUnitBoundary(
  String text,
  int offset, {
  bool roundForward = false,
}) {
  final clamped = offset.clamp(0, text.length).toInt();
  if (isInsideSurrogatePair(text, clamped)) {
    return roundForward
        ? (clamped + 1).clamp(0, text.length).toInt()
        : (clamped - 1).clamp(0, text.length).toInt();
  }
  return clamped;
}

/// Computes a stable hash for a context window snippet.
String computeContextHash(String contextSnippet) {
  return sha256.convert(utf8.encode(contextSnippet)).toString();
}

/// Extracts a context window snippet around [offset] in [text].
///
/// Ensures boundaries do not tear surrogate pairs.
String extractContextWindow(
  String text,
  int offset, {
  int radius = 20,
  int? leading,
  int? trailing,
}) {
  if (text.isEmpty) {
    return '';
  }

  final leadDist = leading ?? radius;
  final trailDist = trailing ?? radius;
  final safeOffset = offset.clamp(0, text.length).toInt();

  int start = (safeOffset - leadDist).clamp(0, text.length).toInt();
  int end = (safeOffset + trailDist).clamp(0, text.length).toInt();

  if (isInsideSurrogatePair(text, start)) {
    start = (start - 1).clamp(0, text.length).toInt();
  }
  if (isInsideSurrogatePair(text, end)) {
    end = (end + 1).clamp(0, text.length).toInt();
  }

  return text.substring(start, end);
}

/// Extracts context around [offset] and generates its hash.
/// Returns null if [text] is empty.
String? createContextHash(
  String text,
  int offset, {
  int radius = 20,
  int? leading,
  int? trailing,
}) {
  if (text.isEmpty) {
    return null;
  }
  final context = extractContextWindow(
    text,
    offset,
    radius: radius,
    leading: leading,
    trailing: trailing,
  );
  return computeContextHash(context);
}

/// Verifies whether the context window at [offset] in [text] matches [expectedHash].
bool verifyContextHash({
  required String text,
  required int offset,
  required String? expectedHash,
  int radius = 20,
  int? leading,
  int? trailing,
}) {
  if (expectedHash == null || expectedHash.isEmpty || text.isEmpty) {
    return false;
  }
  final currentHash = createContextHash(
    text,
    offset,
    radius: radius,
    leading: leading,
    trailing: trailing,
  );
  return currentHash == expectedHash;
}

/// Verifies whether [position]'s contextHash matches the context around its offset in [text].
bool verifyPositionContext(
  TxtPosition position,
  String text, {
  int radius = 20,
  int? leading,
  int? trailing,
}) {
  return verifyContextHash(
    text: text,
    offset: position.offset,
    expectedHash: position.contextHash,
    radius: radius,
    leading: leading,
    trailing: trailing,
  );
}

/// Pure data contract representing a reading position in a TXT document.
///
/// Coordinates are measured in Dart String UTF-16 code units.
class TxtPosition {
  /// 0-based UTF-16 code-unit offset.
  final int offset;

  /// Total source length in UTF-16 code units.
  final int sourceLength;

  /// Hash of the surrounding text window for anchor verification.
  final String? contextHash;

  const TxtPosition({
    required this.offset,
    required this.sourceLength,
    this.contextHash,
  });

  /// Factory that constructs a [TxtPosition] ensuring [offset] is clamped.
  factory TxtPosition.clamped({
    required int offset,
    required int sourceLength,
    String? contextHash,
  }) {
    final safeLength = sourceLength >= 0 ? sourceLength : 0;
    final clampedOffset = offset.clamp(0, safeLength).toInt();
    return TxtPosition(
      offset: clampedOffset,
      sourceLength: safeLength,
      contextHash: contextHash,
    );
  }

  /// Constructs a [TxtPosition] from a percentage (0.0 to 1.0) and [sourceLength].
  factory TxtPosition.fromPercentage({
    required double percentage,
    required int sourceLength,
    String? contextHash,
  }) {
    final safeLength = sourceLength >= 0 ? sourceLength : 0;
    final safePct = percentage.clamp(0.0, 1.0).toDouble();
    final calculatedOffset = (safePct * safeLength).round();
    return TxtPosition(
      offset: calculatedOffset,
      sourceLength: safeLength,
      contextHash: contextHash,
    );
  }

  /// Constructs a [TxtPosition] directly from text content and an offset.
  factory TxtPosition.fromText(
    String text,
    int offset, {
    int contextRadius = 20,
    int? sourceLength,
  }) {
    final len = sourceLength ?? text.length;
    final safeOffset = offset.clamp(0, text.length).toInt();
    final hash = createContextHash(text, safeOffset, radius: contextRadius);
    return TxtPosition(
      offset: safeOffset,
      sourceLength: len,
      contextHash: hash,
    );
  }

  /// Percentage progress through the source document in range [0.0, 1.0].
  double get percentage {
    if (sourceLength <= 0) {
      return 0.0;
    }
    return (offset / sourceLength).clamp(0.0, 1.0);
  }

  /// Whether [offset] is within valid bounds [0, sourceLength].
  bool get isClamped =>
      sourceLength >= 0 && offset >= 0 && offset <= sourceLength;

  /// Returns a new [TxtPosition] with clamped offset and non-negative sourceLength.
  TxtPosition clamp() {
    final safeLength = sourceLength >= 0 ? sourceLength : 0;
    final clampedOffset = offset.clamp(0, safeLength).toInt();
    if (clampedOffset == offset && safeLength == sourceLength) {
      return this;
    }
    return TxtPosition(
      offset: clampedOffset,
      sourceLength: safeLength,
      contextHash: contextHash,
    );
  }

  /// Verifies if the context around this position in [text] matches [contextHash].
  bool verifyContext(
    String text, {
    int radius = 20,
    int? leading,
    int? trailing,
  }) {
    return verifyPositionContext(
      this,
      text,
      radius: radius,
      leading: leading,
      trailing: trailing,
    );
  }

  TxtPosition copyWith({
    int? offset,
    int? sourceLength,
    String? contextHash,
  }) {
    return TxtPosition(
      offset: offset ?? this.offset,
      sourceLength: sourceLength ?? this.sourceLength,
      contextHash: contextHash ?? this.contextHash,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'offset': offset,
      'sourceLength': sourceLength,
      if (contextHash != null) 'contextHash': contextHash,
    };
  }

  factory TxtPosition.fromMap(Map<String, dynamic> map) {
    return TxtPosition(
      offset: map['offset'] as int? ?? 0,
      sourceLength: map['sourceLength'] as int? ?? 0,
      contextHash: map['contextHash'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TxtPosition &&
          runtimeType == other.runtimeType &&
          offset == other.offset &&
          sourceLength == other.sourceLength &&
          contextHash == other.contextHash;

  @override
  int get hashCode => Object.hash(offset, sourceLength, contextHash);

  @override
  String toString() {
    return 'TxtPosition(offset: $offset, sourceLength: $sourceLength, contextHash: $contextHash)';
  }
}
