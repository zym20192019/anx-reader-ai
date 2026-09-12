import 'dart:async';
import 'dart:io';

import 'package:anx_reader/utils/get_path/get_cache_dir.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

/// Converts a TXT source into an EPUB artifact and returns the generated file.
typedef TxtEpubConverter = Future<File> Function(File source);

/// Manages locally generated EPUB artifacts for TXT source files.
///
/// Cache files are deliberately kept outside the persistent `file/` directory.
/// A sidecar fingerprint makes validity explicit instead of treating the
/// presence of an EPUB file as proof that it matches the current parser rules.
class TxtCacheManager {
  /// Creates a manager under an application cache directory.
  ///
  /// [cacheRoot] is the parent application cache directory. The manager owns
  /// the `txt_epub` child directory so relative paths resolve consistently.
  TxtCacheManager({required Directory cacheRoot})
      : _cacheRoot = cacheRoot.path.endsWith(cacheDirectoryName)
            ? cacheRoot
            : Directory(path.join(cacheRoot.path, cacheDirectoryName));

  final Directory _cacheRoot;
  static const _uuid = Uuid();
  static const cacheDirectoryName = 'txt_epub';
  static const generatedFileName = 'generated.epub';
  static const fingerprintFileName = 'generated.fingerprint';

  /// Creates a manager under the platform application cache directory.
  static Future<TxtCacheManager> create({Directory? cacheRoot}) async {
    final root = cacheRoot ?? await getAnxCacheDir();
    final txtRoot = Directory(path.join(root.path, cacheDirectoryName));
    await txtRoot.create(recursive: true);
    return TxtCacheManager(cacheRoot: root);
  }

  Directory get rootDirectory => _cacheRoot;

  /// Returns the isolated directory for a cache fingerprint.
  Directory directoryFor(String fingerprint) {
    final id = _safeIdentifier(fingerprint);
    return Directory(path.join(_cacheRoot.path, id));
  }

  File cacheFileFor(String fingerprint) {
    return File(path.join(directoryFor(fingerprint).path, generatedFileName));
  }

  File fingerprintFileFor(String fingerprint) {
    return File(path.join(directoryFor(fingerprint).path, fingerprintFileName));
  }

  /// Returns the relative cache path used for database storage.
  /// Uses POSIX '/' separators: `txt_epub/<safe_id>/generated.epub`.
  String relativeCachePathFor(String fingerprint) {
    final id = _safeIdentifier(fingerprint);
    return '$cacheDirectoryName/$id/$generatedFileName';
  }

  /// Resolves a Book's cacheFilePath to a File using the application cache directory.
  static Future<File?> resolveBookCacheFile(
    String? cacheFilePath, {
    Directory? cacheRoot,
  }) async {
    if (cacheFilePath == null || cacheFilePath.isEmpty) {
      return null;
    }
    final manager = await TxtCacheManager.create(cacheRoot: cacheRoot);
    return manager.resolveRelativeCachePath(cacheFilePath);
  }

  /// Resolves a relative cache path stored in the database to a File.
  ///
  /// Only paths produced by [relativeCachePathFor] are accepted. This keeps a
  /// malformed database value from escaping the application cache directory.
  File resolveRelativeCachePath(String relativePath) {
    final normalized = relativePath.trim().replaceAll('\\', '/');
    final prefix = '$cacheDirectoryName/';
    if (!normalized.startsWith(prefix)) {
      throw ArgumentError.value(relativePath, 'relativePath', 'invalid cache path');
    }

    final parts = normalized.substring(prefix.length).split('/');
    if (parts.length != 2 ||
        parts[0].isEmpty ||
        parts[0] == '.' ||
        parts[0] == '..' ||
        parts[0].contains('..') ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(parts[0]) ||
        parts[1] != generatedFileName) {
      throw ArgumentError.value(relativePath, 'relativePath', 'invalid cache path');
    }
    return File(path.join(_cacheRoot.path, parts[0], parts[1]));
  }

  /// Returns true only when both the EPUB and its matching fingerprint exist.
  Future<bool> isValid(String fingerprint) async {
    if (fingerprint.trim().isEmpty) return false;

    final cacheFile = cacheFileFor(fingerprint);
    final markerFile = fingerprintFileFor(fingerprint);
    if (!await cacheFile.exists() || !await markerFile.exists()) return false;

    try {
      if (await cacheFile.length() <= 0) return false;
      final marker = (await markerFile.readAsString()).trim();
      return marker == fingerprint.trim();
    } on FileSystemException {
      return false;
    }
  }

  /// Returns the current cache file when it is valid, otherwise null.
  Future<File?> existingValidCache(String fingerprint) async {
    return await isValid(fingerprint) ? cacheFileFor(fingerprint) : null;
  }

  /// Creates a cache from [source] if needed and returns its stable path.
  ///
  /// The converter runs before the existing cache is touched. If conversion
  /// fails, the previous valid cache remains available. Replacement is done by
  /// moving a completed temporary file into place and then updating the marker.
  Future<File> ensureCache({
    required File source,
    required String fingerprint,
    required TxtEpubConverter converter,
    Future<void> Function(File marker, String content)? markerWriter,
    Future<void> Function(File source, String newPath)? fileReplacer,
  }) async {
    final normalizedFingerprint = fingerprint.trim();
    if (normalizedFingerprint.isEmpty) {
      throw ArgumentError.value(fingerprint, 'fingerprint', 'must not be empty');
    }

    final targetDirectory = directoryFor(normalizedFingerprint);
    await targetDirectory.create(recursive: true);
    final target = cacheFileFor(normalizedFingerprint);
    final marker = fingerprintFileFor(normalizedFingerprint);

    if (await isValid(normalizedFingerprint)) return target;

    final tempPath = path.join(
      targetDirectory.path,
      '.generated-${_uuid.v4()}.tmp.epub',
    );
    final temp = File(tempPath);
    File? backupTarget;
    File? backupMarker;
    String? oldMarkerContent;

    try {
      final generated = await converter(source);
      if (!await generated.exists() || await generated.length() <= 0) {
        throw StateError('TXT converter returned an empty EPUB artifact');
      }
      await generated.copy(temp.path);

      if (await target.exists()) {
        backupTarget = File(path.join(
          targetDirectory.path,
          '.generated-${_uuid.v4()}.backup.epub',
        ));
        await target.rename(backupTarget.path);
      }

      if (await marker.exists()) {
        try {
          oldMarkerContent = await marker.readAsString();
        } catch (_) {
          // If reading fails, oldMarkerContent is null
        }
        backupMarker = File(path.join(
          targetDirectory.path,
          '.generated-${_uuid.v4()}.backup.fingerprint',
        ));
        await marker.rename(backupMarker.path);
      }

      try {
        if (fileReplacer != null) {
          await fileReplacer(temp, target.path);
        } else {
          await temp.rename(target.path);
        }

        if (markerWriter != null) {
          await markerWriter(marker, normalizedFingerprint);
        } else {
          await marker.writeAsString(normalizedFingerprint, flush: true);
        }
      } catch (innerError) {
        // Rollback target and marker
        if (await target.exists()) {
          await target.delete();
        }
        if (backupTarget != null && await backupTarget.exists()) {
          await backupTarget.rename(target.path);
          backupTarget = null;
        }

        if (await marker.exists()) {
          await marker.delete();
        }
        if (backupMarker != null && await backupMarker.exists()) {
          await backupMarker.rename(marker.path);
          backupMarker = null;
        } else if (oldMarkerContent != null) {
          try {
            await marker.writeAsString(oldMarkerContent, flush: true);
          } catch (_) {}
        }
        rethrow;
      }

      if (backupTarget != null && await backupTarget.exists()) {
        await backupTarget.delete();
      }
      if (backupMarker != null && await backupMarker.exists()) {
        await backupMarker.delete();
      }
      return target;
    } catch (_) {
      if (await temp.exists()) {
        await temp.delete();
      }
      if (backupTarget != null && await backupTarget.exists()) {
        if (await target.exists()) {
          await target.delete();
        }
        await backupTarget.rename(target.path);
      }
      if (backupMarker != null && await backupMarker.exists()) {
        if (await marker.exists()) {
          await marker.delete();
        }
        await backupMarker.rename(marker.path);
      }
      rethrow;
    }
  }

  Future<void> removeCache(String fingerprint) async {
    final directory = directoryFor(fingerprint);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  String _safeIdentifier(String fingerprint) {
    final normalized = fingerprint.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(fingerprint, 'fingerprint', 'must not be empty');
    }
    final safe = normalized.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe.isEmpty || safe == '.' || safe == '..' || safe.contains('..')) {
      throw ArgumentError.value(fingerprint, 'fingerprint', 'invalid cache identifier');
    }
    return safe;
  }
}
