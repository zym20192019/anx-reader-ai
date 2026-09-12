/// Pure filename allocator for book files.
///
/// Features:
/// - Pure Dart, no file I/O.
/// - Sanitizes illegal Windows characters `<>:"/\|?*`, line breaks, and whitespace.
/// - Stable fallback for empty titles or 'Unknown' (case-insensitive).
/// - Conflict resolution follows `Title.ext`, `Title (1).ext`, `Title (2).ext`.
/// - Extension case does not affect conflict detection.
/// - Respects maxBaseNameLength without ever truncating the extension or collision suffix.
/// - No timestamps or UUIDs.

const String kDefaultFallbackTitle = 'book';
const int kDefaultMaxBaseNameLength = 60;

/// Cleans [rawTitle] by stripping illegal filename characters, line breaks,
/// control characters, and trimming surrounding whitespace and trailing dots/spaces.
/// If the cleaned title is empty or equals 'Unknown' (case-insensitive),
/// returns [fallback].
String sanitizeFilenameBase(
  String rawTitle, {
  String fallback = kDefaultFallbackTitle,
}) {
  final trimmed = rawTitle.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'unknown') {
    return fallback;
  }

  // Remove Windows invalid filename characters (<>:"/\|?*) and control chars
  var cleaned = trimmed.replaceAll(
    RegExp(r'[<>:"/\\|?*\x00-\x1F\x7F]'),
    '',
  );

  // Normalize internal whitespace (e.g. multiple spaces, tabs) to single spaces
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

  // Windows file names cannot end with a period or space
  cleaned = cleaned.replaceAll(RegExp(r'[\s.]+$'), '');
  cleaned = cleaned.replaceAll(RegExp(r'^[\s.]+'), '');

  if (cleaned.isEmpty || cleaned.toLowerCase() == 'unknown') {
    return fallback;
  }

  return cleaned;
}

/// Allocates the first available, safe, canonical filename for a book.
///
/// - [title]: raw book title or file base name.
/// - [extension]: file extension, e.g. 'txt', '.txt', 'epub'.
/// - [existingPaths]: collection of already allocated filenames or paths (relative or absolute).
/// - [maxBaseNameLength]: maximum character length allowed for the base name before extension.
///   When appending collision suffix `(n)`, the total base name length is capped within this limit.
String allocateBookFilename({
  required String title,
  required String extension,
  required Iterable<String> existingPaths,
  int maxBaseNameLength = kDefaultMaxBaseNameLength,
  String fallback = kDefaultFallbackTitle,
}) {
  return const BookFilenameAllocator().allocate(
    title: title,
    extension: extension,
    existingPaths: existingPaths,
    maxBaseNameLength: maxBaseNameLength,
    fallback: fallback,
  );
}

/// Class-based pure filename allocator.
class BookFilenameAllocator {
  final int defaultMaxBaseNameLength;
  final String defaultFallback;

  const BookFilenameAllocator({
    this.defaultMaxBaseNameLength = kDefaultMaxBaseNameLength,
    this.defaultFallback = kDefaultFallbackTitle,
  });

  /// Extracts the simple filename from [rawPath], supporting both Windows and POSIX separators.
  static String extractBasename(String rawPath) {
    if (rawPath.isEmpty) return '';
    final normalized = rawPath.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index >= 0 ? normalized.substring(index + 1) : normalized;
  }

  /// Normalizes an extension (removes leading dot, trims whitespace, lowercases).
  static String normalizeExtension(String extension) {
    var ext = extension.trim();
    if (ext.startsWith('.')) {
      ext = ext.substring(1).trim();
    }
    return ext.toLowerCase();
  }

  /// Allocates the first available safe filename.
  String allocate({
    required String title,
    required String extension,
    required Iterable<String> existingPaths,
    int? maxBaseNameLength,
    String? fallback,
  }) {
    final effectiveMaxBaseLength = maxBaseNameLength ?? defaultMaxBaseNameLength;
    final effectiveFallback = fallback ?? defaultFallback;

    final sanitizedBase = sanitizeFilenameBase(
      title,
      fallback: effectiveFallback,
    );

    final normalizedExt = normalizeExtension(extension);
    final extSuffix = normalizedExt.isNotEmpty ? '.$normalizedExt' : '';

    // Collect existing filenames in lower case for case-insensitive collision check
    final existingFilenamesLower = <String>{};
    for (final p in existingPaths) {
      final base = extractBasename(p).trim().toLowerCase();
      if (base.isNotEmpty) {
        existingFilenamesLower.add(base);
      }
    }

    // Candidate generation:
    // First candidate: index 0 -> without collision suffix `(n)`
    // Subsequent candidates: index 1, 2, ... -> with suffix ` (1)`, ` (2)`, ...
    for (int counter = 0;; counter++) {
      final collisionSuffix = counter == 0 ? '' : ' ($counter)';

      // Calculate maximum allowed characters for the sanitized title prefix
      // so that sanitizedPrefix + collisionSuffix <= effectiveMaxBaseLength
      final allowedPrefixLength = effectiveMaxBaseLength - collisionSuffix.length;

      final String candidateBase;
      if (allowedPrefixLength <= 0) {
        // Edge case: if maxBaseNameLength is extremely small, use suffix or fallback
        candidateBase = collisionSuffix.trim();
      } else {
        var baseToUse = sanitizedBase;
        final runes = baseToUse.runes.toList();
        if (runes.length > allowedPrefixLength) {
          baseToUse = String.fromCharCodes(runes.take(allowedPrefixLength));
          // Strip any trailing spaces or dots left by truncation
          baseToUse = baseToUse.replaceAll(RegExp(r'[\s.]+$'), '');
          if (baseToUse.isEmpty) {
            baseToUse = effectiveFallback;
          }
        }
        candidateBase = '$baseToUse$collisionSuffix';
      }

      final candidateFilename = '$candidateBase$extSuffix';
      final candidateLower = candidateFilename.toLowerCase();

      if (!existingFilenamesLower.contains(candidateLower)) {
        return candidateFilename;
      }
    }
  }
}
