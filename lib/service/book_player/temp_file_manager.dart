import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart' as shelf;
import 'package:uuid/uuid.dart';

/// In-memory entry tracking a temporary file and its registration timestamp.
class TempFileEntry {
  final File file;
  final DateTime createdAt;

  TempFileEntry(this.file, [DateTime? createdAt])
      : createdAt = createdAt ?? DateTime.now();
}

/// Thread-safe manager for temporary files served by BookPlayerServer.
///
/// Maps unique, unguessable tokens to [File] instances so concurrent
/// operations (such as metadata extraction for multiple EPUBs) do not
/// collide or overwrite each other.
class TempFileManager {
  final Map<String, TempFileEntry> _tempFiles = <String, TempFileEntry>{};
  DateTime Function() _now;

  TempFileManager({DateTime Function()? nowProvider})
      : _now = nowProvider ?? DateTime.now;

  /// Injected clock for deterministic testing of expiration and eviction.
  @visibleForTesting
  set nowProvider(DateTime Function() provider) {
    _now = provider;
  }

  /// Current clock provider.
  @visibleForTesting
  DateTime Function() get nowProvider => _now;

  /// Validates that a token is a safe, single-segment identifier
  /// without path traversal or unsafe characters.
  static bool isValidToken(String token) {
    if (token.isEmpty || token.length > 256) return false;
    if (token.contains('/') || token.contains('\\') || token.contains('..')) {
      return false;
    }
    return RegExp(r'^[a-zA-Z0-9_\-\.]+$').hasMatch(token);
  }

  /// Registers [file] with a unique token and returns the generated token/filename.
  ///
  /// If [token] is provided, it is validated and used directly.
  /// Otherwise, a unique token is generated using a millisecond timestamp
  /// and UUID v4 to guarantee uniqueness across same-millisecond calls.
  String setTempFile(File file, {String? token}) {
    String effectiveToken;
    if (token != null && token.isNotEmpty) {
      if (!isValidToken(token)) {
        throw ArgumentError('Invalid temp token: $token');
      }
      effectiveToken = token;
    } else {
      final ext = path.extension(file.path);
      final safeExt =
          (ext.isNotEmpty && RegExp(r'^\.[a-zA-Z0-9]+$').hasMatch(ext))
              ? ext
              : '.epub';
      final id = const Uuid().v4();
      effectiveToken = '${_now().millisecondsSinceEpoch}_$id$safeExt';
    }

    _tempFiles[effectiveToken] = TempFileEntry(file, _now());
    pruneExpired();
    return effectiveToken;
  }

  /// Releases the temporary file mapping for [token].
  ///
  /// Returns `true` if removed, `false` if not found.
  /// This only removes the server route mapping; it does NOT delete the file on disk.
  bool releaseTempFile(String token) {
    return _tempFiles.remove(token) != null;
  }

  /// Clears all temporary file mappings.
  void clear() {
    _tempFiles.clear();
  }

  /// Checks if [token] is currently registered.
  bool has(String token) => _tempFiles.containsKey(token);

  /// Returns the current number of registered temporary files.
  int get count => _tempFiles.length;

  /// Retrieves the registered file for [token], or `null` if not found.
  File? getFile(String token) => _tempFiles[token]?.file;

  /// Prunes entries older than [maxAge], and limits total entries to [maxCount].
  ///
  /// Strictly removes excess entries only when `_tempFiles.length > maxCount`,
  /// removing exactly `_tempFiles.length - maxCount` oldest entries.
  void pruneExpired({
    Duration maxAge = const Duration(minutes: 30),
    int maxCount = 100,
  }) {
    final now = _now();
    _tempFiles.removeWhere((_, entry) => now.difference(entry.createdAt) > maxAge);
    if (maxCount >= 0 && _tempFiles.length > maxCount) {
      final sortedKeys = _tempFiles.keys.toList()
        ..sort((a, b) => _tempFiles[a]!.createdAt.compareTo(_tempFiles[b]!.createdAt));
      final toRemove = sortedKeys.take(_tempFiles.length - maxCount);
      for (final key in toRemove) {
        _tempFiles.remove(key);
      }
    }
  }

  /// Handles an incoming shelf request if it targets a temporary file.
  ///
  /// Routing evaluation:
  /// - Only single-segment paths matching [isValidToken] (e.g. `/$token`) are handled here.
  /// - Multi-segment paths (e.g. `/book/...`, `/js/...`, `/fonts/...`, `/foliate-js/...`,
  ///   `/bgimg/...`) contain `/` and return `null`, allowing BookPlayerServer handlers to process them.
  /// - Unknown or released single-segment tokens return 404 ('Temp file not found') because
  ///   tokens at root are dedicated temp file resources.
  shelf.Response? handleRequest(shelf.Request request) {
    final uriPath = request.requestedUri.path;
    final token = uriPath.startsWith('/') ? uriPath.substring(1) : uriPath;
    if (token.isEmpty || token.contains('/') || token.contains('\\')) {
      return null;
    }
    if (!isValidToken(token)) {
      return null;
    }
    final entry = _tempFiles[token];
    if (entry != null) {
      if (entry.file.existsSync()) {
        return shelf.Response.ok(
          entry.file.openRead(),
          headers: {
            'Content-Type': 'application/epub+zip',
            'Access-Control-Allow-Origin': '*',
          },
        );
      } else {
        return shelf.Response.notFound('Temp file not found on disk');
      }
    }
    return shelf.Response.notFound('Temp file not found');
  }
}
