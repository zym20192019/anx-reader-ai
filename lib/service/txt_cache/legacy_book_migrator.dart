import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_source.dart';

/// Categories for classifying books during legacy migration and audit.
enum LegacyBookCategory {
  /// Book has a non-empty [Book.sourceFilePath] and a determinable [Book.sourceFormat].
  sourceBacked,

  /// Book has a non-empty [Book.sourceMd5] but missing [Book.sourceFilePath].
  partialSource,

  /// Book lacks source information or only maintains the legacy [Book.filePath].
  legacy,
}

/// Resolves the canonical source format of a [Book].
///
/// Precedence:
/// 1. Explicit [Book.sourceFormat] if non-empty.
/// 2. Inferred file extension from [Book.sourceFilePath] if present.
///
/// Returns null if format cannot be determined.
String? resolveBookSourceFormat(Book book) {
  final explicit = book.sourceFormat?.trim();
  if (explicit != null && explicit.isNotEmpty) {
    return BookSourceFormat.normalize(explicit);
  }

  final sourcePath = book.sourceFilePath?.trim();
  if (sourcePath != null && sourcePath.isNotEmpty) {
    final normalized = sourcePath.replaceAll('\\', '/');
    final fileName = normalized.split('/').last;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex > 0 && dotIndex < fileName.length - 1) {
      final ext = fileName.substring(dotIndex + 1).trim();
      if (ext.isNotEmpty) {
        return BookSourceFormat.normalize(ext);
      }
    }
  }

  return null;
}

/// Classifies a [Book] into a [LegacyBookCategory].
///
/// Rules:
/// - [LegacyBookCategory.sourceBacked]: [Book.sourceFilePath] is non-empty and
///   [Book.sourceFormat] is non-empty or determinable from the source path.
/// - [LegacyBookCategory.partialSource]: [Book.sourceMd5] is non-empty but
///   [Book.sourceFilePath] is empty or null.
/// - [LegacyBookCategory.legacy]: Neither source-backed nor partial-source
///   (e.g., only legacy [Book.filePath] exists or no source metadata).
///
/// Note: Legacy EPUB files are never guessed to be TXT sources.
LegacyBookCategory classifyBook(Book book) {
  final sourcePath = book.sourceFilePath?.trim();
  final hasSourcePath = sourcePath != null && sourcePath.isNotEmpty;

  if (hasSourcePath) {
    final format = resolveBookSourceFormat(book);
    if (format != null && format.isNotEmpty) {
      return LegacyBookCategory.sourceBacked;
    }
  }

  final sourceMd5 = book.sourceMd5?.trim();
  final hasSourceMd5 = sourceMd5 != null && sourceMd5.isNotEmpty;

  if (hasSourceMd5 && !hasSourcePath) {
    return LegacyBookCategory.partialSource;
  }

  return LegacyBookCategory.legacy;
}

/// Whether the book is classified as [LegacyBookCategory.sourceBacked].
bool isSourceBacked(Book book) =>
    classifyBook(book) == LegacyBookCategory.sourceBacked;

/// Whether the book is classified as [LegacyBookCategory.partialSource].
bool isPartialSource(Book book) =>
    classifyBook(book) == LegacyBookCategory.partialSource;

/// Whether the book is classified as [LegacyBookCategory.legacy].
bool isLegacy(Book book) => classifyBook(book) == LegacyBookCategory.legacy;

/// Whether the book has local cache metadata ([cacheFilePath] or [cacheFingerprint]).
bool isCacheBacked(Book book) {
  final cachePath = book.cacheFilePath?.trim();
  if (cachePath != null && cachePath.isNotEmpty) {
    return true;
  }
  final cacheFingerprint = book.cacheFingerprint?.trim();
  if (cacheFingerprint != null && cacheFingerprint.isNotEmpty) {
    return true;
  }
  return false;
}

/// Determines if [book] is a TXT source book.
///
/// Checks [sourceFormat] and [sourceFilePath] first. For legacy records without
/// source metadata, falls back to checking [filePath], but strictly never treats
/// `.epub` files as TXT sources even if the file name contains 'txt'.
bool isTxtSource(Book book) {
  final explicit = book.sourceFormat?.trim();
  if (explicit != null && explicit.isNotEmpty) {
    return BookSourceFormat.isTxt(explicit);
  }

  final sourcePath = book.sourceFilePath?.trim();
  if (sourcePath != null && sourcePath.isNotEmpty) {
    final normalized = sourcePath.replaceAll('\\', '/');
    final fileName = normalized.split('/').last.toLowerCase();
    return fileName.endsWith('.txt');
  }

  // Legacy fallback: Never guess TXT from an EPUB filename.
  final filePath = book.filePath.trim().replaceAll('\\', '/');
  final lowerFile = filePath.toLowerCase();
  if (lowerFile.endsWith('.epub')) {
    return false;
  }
  return lowerFile.endsWith('.txt');
}

/// Pure filter function that normalizes paths to forward slashes and returns
/// all paths matching `file/*.epub` (case-insensitive).
///
/// Does not delete or mutate any remote files.
List<String> listHistoricalRemoteEpubs(Iterable<String> paths) {
  final matches = <String>[];
  for (final rawPath in paths) {
    var normalized = rawPath.trim().replaceAll('\\', '/');
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    final lower = normalized.toLowerCase();
    if (lower.startsWith('file/') && lower.endsWith('.epub')) {
      matches.add(normalized);
    }
  }
  return List.unmodifiable(matches);
}

/// Immutable audit report summarizing book classification counts and IDs.
class LegacyBookAuditReport {
  final List<int> sourceBackedIds;
  final List<int> partialSourceIds;
  final List<int> legacyIds;
  final List<int> cacheBackedIds;
  final List<int> txtSourceIds;
  final int totalBooks;

  LegacyBookAuditReport({
    required List<int> sourceBackedIds,
    required List<int> partialSourceIds,
    required List<int> legacyIds,
    required List<int> cacheBackedIds,
    required List<int> txtSourceIds,
    int? totalBooks,
  })  : sourceBackedIds = List.unmodifiable(sourceBackedIds),
        partialSourceIds = List.unmodifiable(partialSourceIds),
        legacyIds = List.unmodifiable(legacyIds),
        cacheBackedIds = List.unmodifiable(cacheBackedIds),
        txtSourceIds = List.unmodifiable(txtSourceIds),
        totalBooks = totalBooks ??
            (sourceBackedIds.length +
                partialSourceIds.length +
                legacyIds.length);

  /// Creates an empty audit report.
  factory LegacyBookAuditReport.empty() {
    return LegacyBookAuditReport(
      sourceBackedIds: const [],
      partialSourceIds: const [],
      legacyIds: const [],
      cacheBackedIds: const [],
      txtSourceIds: const [],
      totalBooks: 0,
    );
  }

  /// Audits an iterable of [Book] models and produces a report.
  factory LegacyBookAuditReport.fromBooks(Iterable<Book> books) {
    final sourceBacked = <int>[];
    final partialSource = <int>[];
    final legacy = <int>[];
    final cacheBacked = <int>[];
    final txtSource = <int>[];
    int count = 0;

    for (final book in books) {
      count++;
      final category = classifyBook(book);
      switch (category) {
        case LegacyBookCategory.sourceBacked:
          sourceBacked.add(book.id);
          break;
        case LegacyBookCategory.partialSource:
          partialSource.add(book.id);
          break;
        case LegacyBookCategory.legacy:
          legacy.add(book.id);
          break;
      }

      if (isCacheBacked(book)) {
        cacheBacked.add(book.id);
      }

      if (isTxtSource(book)) {
        txtSource.add(book.id);
      }
    }

    return LegacyBookAuditReport(
      sourceBackedIds: sourceBacked,
      partialSourceIds: partialSource,
      legacyIds: legacy,
      cacheBackedIds: cacheBacked,
      txtSourceIds: txtSource,
      totalBooks: count,
    );
  }

  int get sourceBackedCount => sourceBackedIds.length;
  int get partialSourceCount => partialSourceIds.length;
  int get legacyCount => legacyIds.length;
  int get cacheBackedCount => cacheBackedIds.length;
  int get txtSourceCount => txtSourceIds.length;
  int get totalCount => totalBooks;

  List<int> get sourceBackedBookIds => sourceBackedIds;
  List<int> get partialSourceBookIds => partialSourceIds;
  List<int> get legacyBookIds => legacyIds;
  List<int> get cacheBackedBookIds => cacheBackedIds;
  List<int> get txtSourceBookIds => txtSourceIds;

  Map<String, dynamic> toMap() {
    return {
      'totalBooks': totalBooks,
      'sourceBackedCount': sourceBackedCount,
      'partialSourceCount': partialSourceCount,
      'legacyCount': legacyCount,
      'cacheBackedCount': cacheBackedCount,
      'txtSourceCount': txtSourceCount,
      'sourceBackedIds': sourceBackedIds,
      'partialSourceIds': partialSourceIds,
      'legacyIds': legacyIds,
      'cacheBackedIds': cacheBackedIds,
      'txtSourceIds': txtSourceIds,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LegacyBookAuditReport &&
          runtimeType == other.runtimeType &&
          totalBooks == other.totalBooks &&
          _listEquals(sourceBackedIds, other.sourceBackedIds) &&
          _listEquals(partialSourceIds, other.partialSourceIds) &&
          _listEquals(legacyIds, other.legacyIds) &&
          _listEquals(cacheBackedIds, other.cacheBackedIds) &&
          _listEquals(txtSourceIds, other.txtSourceIds);

  @override
  int get hashCode => Object.hash(
        totalBooks,
        Object.hashAll(sourceBackedIds),
        Object.hashAll(partialSourceIds),
        Object.hashAll(legacyIds),
        Object.hashAll(cacheBackedIds),
        Object.hashAll(txtSourceIds),
      );

  @override
  String toString() {
    return 'LegacyBookAuditReport(total: $totalBooks, sourceBacked: $sourceBackedCount, partialSource: $partialSourceCount, legacy: $legacyCount, cacheBacked: $cacheBackedCount, txtSource: $txtSourceCount)';
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Utility entrypoint for legacy book audit and migration inspections.
class LegacyBookMigrator {
  const LegacyBookMigrator._();

  /// Audits an iterable of [books] and returns an immutable [LegacyBookAuditReport].
  static LegacyBookAuditReport audit(Iterable<Book> books) =>
      LegacyBookAuditReport.fromBooks(books);

  /// Classifies [book] into a [LegacyBookCategory].
  static LegacyBookCategory classify(Book book) => classifyBook(book);

  /// Resolves the source format for [book], or null if indeterminable.
  static String? resolveFormat(Book book) => resolveBookSourceFormat(book);

  /// Checks if [book] is backed by a valid source file and determinable format.
  static bool isSourceBackedBook(Book book) => isSourceBacked(book);

  /// Checks if [book] is partially migrated (has sourceMd5 but missing sourceFilePath).
  static bool isPartialSourceBook(Book book) => isPartialSource(book);

  /// Checks if [book] is a legacy record (neither sourceBacked nor partialSource).
  static bool isLegacyBook(Book book) => isLegacy(book);

  /// Checks if [book] has cache metadata.
  static bool isCacheBackedBook(Book book) => isCacheBacked(book);

  /// Checks if [book] is a TXT source book without guessing from EPUB filenames.
  static bool isTxtSourceBook(Book book) => isTxtSource(book);

  /// Filters historical remote EPUB paths (`file/*.epub`, case-insensitive) with normalized slashes.
  static List<String> listHistoricalRemoteEpubs(Iterable<String> paths) =>
      legacyListHistoricalRemoteEpubs(paths);
}

/// Pure function alias for [listHistoricalRemoteEpubs].
List<String> legacyListHistoricalRemoteEpubs(Iterable<String> paths) =>
    listHistoricalRemoteEpubs(paths);

/// Pure function alias for auditing books.
LegacyBookAuditReport auditBooks(Iterable<Book> books) =>
    LegacyBookAuditReport.fromBooks(books);
