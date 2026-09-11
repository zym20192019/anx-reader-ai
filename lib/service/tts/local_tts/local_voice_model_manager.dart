import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:anx_reader/service/tts/local_tts/local_voice_model.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Exception thrown when downloaded model file SHA-256 does not match expected hash.
class ModelChecksumException implements Exception {
  ModelChecksumException({required this.expected, required this.actual});
  final String expected;
  final String actual;

  @override
  String toString() =>
      'ModelChecksumException: SHA-256 mismatch (expected: $expected, actual: $actual)';
}

/// Exception thrown when extracted package does not contain all required model files.
class ModelIntegrityException implements Exception {
  ModelIntegrityException({required this.missingFiles});
  final List<String> missingFiles;

  @override
  String toString() =>
      'ModelIntegrityException: Missing required files in model package: $missingFiles';
}

/// Exception thrown when an archive contains malicious or invalid entry paths (Zip Slip / Tar Slip).
class ModelSecurityException implements Exception {
  ModelSecurityException(this.message);
  final String message;

  @override
  String toString() => 'ModelSecurityException: $message';
}

/// Manager responsible for local voice model discovery, download, SHA-256 verification,
/// extraction, installation integrity, and deletion.
class LocalVoiceModelManager {
  static final LocalVoiceModelManager _instance =
      LocalVoiceModelManager._internal();

  factory LocalVoiceModelManager() => _instance;

  LocalVoiceModelManager._internal();

  /// Dependency-injected constructor for unit tests.
  LocalVoiceModelManager.withDirs({
    Dio? dio,
    Future<Directory> Function()? getBaseDir,
    Future<Directory> Function()? getTempDir,
  })  : _dio = dio,
        _getBaseDir = getBaseDir,
        _getTempDir = getTempDir;

  Dio? _dio;
  Future<Directory> Function()? _getBaseDir;
  Future<Directory> Function()? _getTempDir;

  final Map<String, ValueNotifier<double>> _progressNotifiers = {};
  final Map<String, ValueNotifier<ModelInstallStatus>> _statusNotifiers = {};
  final Map<String, CancelToken> _activeCancelTokens = {};
  final Map<String, Future<void>> _activeDownloads = {};

  Dio get _client => _dio ??= Dio();

  Future<Directory> _resolveBaseDir() async {
    if (_getBaseDir != null) return await _getBaseDir!();
    return await getApplicationSupportDirectory();
  }

  Future<Directory> _resolveTempDir() async {
    if (_getTempDir != null) return await _getTempDir!();
    return await getTemporaryDirectory();
  }

  /// Returns the persistent directory where [model] is or should be installed.
  Future<Directory> getModelDir(LocalVoiceModel model) async {
    final base = await _resolveBaseDir();
    return Directory(p.join(base.path, 'tts_models', model.id));
  }

  /// Returns the temporary downloads directory.
  Future<Directory> getTempDownloadsDir() async {
    final temp = await _resolveTempDir();
    final dir = Directory(p.join(temp.path, 'tts_downloads'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Gets or creates a ValueNotifier tracking download progress (0.0 - 1.0) for [model].
  ValueNotifier<double> getDownloadProgress(LocalVoiceModel model) {
    return _progressNotifiers.putIfAbsent(
      model.id,
      () => ValueNotifier<double>(0.0),
    );
  }

  /// Gets or creates a ValueNotifier tracking installation status for [model].
  ValueNotifier<ModelInstallStatus> getStatusNotifier(LocalVoiceModel model) {
    return _statusNotifiers.putIfAbsent(
      model.id,
      () => ValueNotifier<ModelInstallStatus>(ModelInstallStatus.notDownloaded),
    );
  }

  /// Checks if [model] is fully and validly installed in persistent storage.
  Future<bool> isModelInstalled(LocalVoiceModel model) async {
    final dir = await getModelDir(model);
    if (!dir.existsSync()) return false;

    for (final filename in model.requiredFiles) {
      final file = File(p.join(dir.path, filename));
      if (!file.existsSync() || file.lengthSync() == 0) {
        return false;
      }
    }
    return true;
  }

  /// Gets the current status of [model], updating the status notifier.
  Future<ModelInstallStatus> getModelStatus(LocalVoiceModel model) async {
    final notifier = getStatusNotifier(model);
    if (_activeDownloads.containsKey(model.id)) {
      notifier.value = ModelInstallStatus.downloading;
      return ModelInstallStatus.downloading;
    }

    final installed = await isModelInstalled(model);
    final status = installed
        ? ModelInstallStatus.installed
        : ModelInstallStatus.notDownloaded;
    notifier.value = status;
    return status;
  }

  /// Downloads [model] streamed to a temporary file via Dio, verifies SHA-256 checksum,
  /// extracts to staging with boundary checks, validates required files integrity, and atomically installs.
  Future<void> downloadAndInstall(
    LocalVoiceModel model, {
    void Function(int received, int total)? onProgress,
  }) async {
    // If download is already in progress, join the existing future
    if (_activeDownloads.containsKey(model.id)) {
      return await _activeDownloads[model.id]!;
    }

    final completer = Completer<void>();
    _activeDownloads[model.id] = completer.future;

    final statusNotifier = getStatusNotifier(model);
    final progressNotifier = getDownloadProgress(model);

    statusNotifier.value = ModelInstallStatus.downloading;
    progressNotifier.value = 0.0;

    final tempDir = await getTempDownloadsDir();
    final tempArchive = File(p.join(tempDir.path, '${model.id}.download.tmp'));
    final stagingDir = Directory(p.join(tempDir.path, '${model.id}_staging'));
    final cancelToken = CancelToken();
    _activeCancelTokens[model.id] = cancelToken;

    try {
      // 1. Clean previous partial downloads or staging
      if (tempArchive.existsSync()) {
        try {
          tempArchive.deleteSync();
        } catch (_) {}
      }
      if (stagingDir.existsSync()) {
        try {
          stagingDir.deleteSync(recursive: true);
        } catch (_) {}
      }

      // 2. Stream download with Dio directly to tempArchive file (avoids 60MB in-memory buffer)
      AnxLog.info('Starting download for TTS model ${model.id} from ${model.downloadUrl}');

      await _client.download(
        model.downloadUrl,
        tempArchive.path,
        cancelToken: cancelToken,
        deleteOnError: false,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            progressNotifier.value = progress.clamp(0.0, 1.0);
          }
          if (onProgress != null) {
            onProgress(received, total);
          }
        },
      );

      // 3. SHA-256 verification (streamed from file)
      AnxLog.info('Verifying SHA-256 checksum for ${model.id}');
      final digest = await sha256.bind(tempArchive.openRead()).first;
      final actualSha256 = digest.toString().toLowerCase();
      final expectedSha256 = model.sha256.trim().toLowerCase();

      if (actualSha256 != expectedSha256) {
        throw ModelChecksumException(
          expected: expectedSha256,
          actual: actualSha256,
        );
      }

      // 4. Extraction to staging with strict Zip Slip / Tar Slip security checks
      // Note on memory: Download is streamed directly to disk via Dio.download
      // to avoid holding the compressed archive in memory during network transfer.
      // For extraction, Dart's archive library (especially BZip2Decoder/TarDecoder)
      // operates in-memory on the archive buffer. Redundant copies of file byte arrays
      // are avoided, though complete streaming extraction is constrained by the archive package API.
      stagingDir.createSync(recursive: true);
      final archiveBytes = await tempArchive.readAsBytes();
      await _extractArchive(archiveBytes, stagingDir, model);

      // Flatten subfolder if archive wrapped files inside a folder
      _flattenSubfoldersIfNeeded(stagingDir, model);

      // 5. Integrity check
      final missingFiles = <String>[];
      for (final reqFile in model.requiredFiles) {
        final f = File(p.join(stagingDir.path, reqFile));
        if (!f.existsSync() || f.lengthSync() == 0) {
          missingFiles.add(reqFile);
        }
      }

      if (missingFiles.isNotEmpty) {
        throw ModelIntegrityException(missingFiles: missingFiles);
      }

      // 6. Atomic move to target
      final targetDir = await getModelDir(model);
      if (targetDir.existsSync()) {
        targetDir.deleteSync(recursive: true);
      }
      targetDir.parent.createSync(recursive: true);

      try {
        stagingDir.renameSync(targetDir.path);
      } catch (e) {
        // Fallback: copy files across filesystem boundary
        _copyDirectorySync(stagingDir, targetDir);
        stagingDir.deleteSync(recursive: true);
      }

      // 7. Cleanup temp archive
      if (tempArchive.existsSync()) {
        try {
          tempArchive.deleteSync();
        } catch (_) {}
      }

      statusNotifier.value = ModelInstallStatus.installed;
      progressNotifier.value = 1.0;
      AnxLog.info('Successfully installed TTS model ${model.id}');
      completer.complete();
    } catch (e) {
      final isCancelled = cancelToken.isCancelled ||
          (e is DioException && CancelToken.isCancel(e)) ||
          e.toString().toLowerCase().contains('cancel');

      if (isCancelled) {
        AnxLog.info('Download cancelled for TTS model ${model.id}');
        statusNotifier.value = ModelInstallStatus.notDownloaded;
        progressNotifier.value = 0.0;
      } else {
        AnxLog.severe('Failed to download/install TTS model ${model.id}: $e');
        statusNotifier.value = ModelInstallStatus.error;
      }

      // Ensure cleanup of partial artifacts
      if (tempArchive.existsSync()) {
        try {
          tempArchive.deleteSync();
        } catch (_) {}
      }
      if (stagingDir.existsSync()) {
        try {
          stagingDir.deleteSync(recursive: true);
        } catch (_) {}
      }

      if (!completer.isCompleted) {
        completer.completeError(e);
      }
      rethrow;
    } finally {
      // Clean up maps only if this invocation still owns the active task entry
      if (identical(_activeDownloads[model.id], completer.future)) {
        _activeDownloads.remove(model.id);
      }
      if (identical(_activeCancelTokens[model.id], cancelToken)) {
        _activeCancelTokens.remove(model.id);
      }
    }
  }

  /// Cancels an ongoing download for [model] and resets status.
  /// Does not prematurely remove from active maps so the active task cleans up safely.
  void cancelDownload(LocalVoiceModel model) {
    final token = _activeCancelTokens[model.id];
    if (token != null && !token.isCancelled) {
      token.cancel('User cancelled download');
    }

    final statusNotifier = getStatusNotifier(model);
    statusNotifier.value = ModelInstallStatus.notDownloaded;
    getDownloadProgress(model).value = 0.0;
  }

  /// Deletes an installed model directory and updates status.
  Future<void> deleteModel(LocalVoiceModel model) async {
    final dir = await getModelDir(model);
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (e) {
        AnxLog.warning('Failed to delete model dir: $e');
      }
    }
    final statusNotifier = getStatusNotifier(model);
    statusNotifier.value = ModelInstallStatus.notDownloaded;
    getDownloadProgress(model).value = 0.0;
  }

  /// Extracts [archiveBytes] into [targetDir] supporting .tar.bz2, .zip, and .tar.gz.
  /// Strictly sanitizes every archive entry to prevent Zip Slip / Tar Slip vulnerabilities.
  Future<void> _extractArchive(
    Uint8List archiveBytes,
    Directory targetDir,
    LocalVoiceModel model,
  ) async {
    Archive archive;
    if (model.downloadUrl.endsWith('.tar.bz2') || _isBzip2(archiveBytes)) {
      final tarBytes = BZip2Decoder().decodeBytes(archiveBytes);
      archive = TarDecoder().decodeBytes(tarBytes);
    } else if (model.downloadUrl.endsWith('.zip') || _isZip(archiveBytes)) {
      archive = ZipDecoder().decodeBytes(archiveBytes);
    } else if (model.downloadUrl.endsWith('.tar.gz') || _isGzip(archiveBytes)) {
      final tarBytes = GZipDecoder().decodeBytes(archiveBytes);
      archive = TarDecoder().decodeBytes(tarBytes);
    } else {
      archive = TarDecoder().decodeBytes(archiveBytes);
    }

    final canonicalTargetDir = p.canonicalize(targetDir.path);

    for (final file in archive.files) {
      if (file.isSymbolicLink) {
        throw ModelSecurityException(
            'Symbolic links are not allowed in model archive: ${file.name}');
      }

      if (file.isFile) {
        final name = file.name;
        if (name.isEmpty || name.contains('\x00')) {
          throw ModelSecurityException('Invalid archive entry name: $name');
        }

        if (p.isAbsolute(name) || name.startsWith('/') || name.startsWith('\\')) {
          throw ModelSecurityException(
              'Absolute paths in archive entry are not allowed: $name');
        }

        final normalized = p.normalize(name);
        if (normalized == '..' ||
            normalized.startsWith('../') ||
            normalized.startsWith(r'..\') ||
            normalized.contains('/../') ||
            normalized.contains(r'\..\')) {
          throw ModelSecurityException(
              'Directory traversal detected in archive entry: $name');
        }

        final resolvedPath =
            p.canonicalize(p.join(canonicalTargetDir, normalized));
        if (!p.isWithin(canonicalTargetDir, resolvedPath) &&
            resolvedPath != canonicalTargetDir) {
          throw ModelSecurityException(
              'Archive entry path escapes target directory: $name');
        }

        final outFile = File(resolvedPath);
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(file.content as List<int>);
      }
    }
  }

  /// If archive extracted files into a nested directory (e.g. `vits-piper-zh_CN-chaowen-medium/model.onnx`),
  /// flattens that directory up into [stagingDir].
  void _flattenSubfoldersIfNeeded(Directory stagingDir, LocalVoiceModel model) {
    final directOnnx = File(p.join(stagingDir.path, model.onnxFileName));
    if (directOnnx.existsSync()) return;

    // Search inside first level of subdirectories
    final entities = stagingDir.listSync();
    for (final entity in entities) {
      if (entity is Directory) {
        final nestedOnnx = File(p.join(entity.path, model.onnxFileName));
        if (nestedOnnx.existsSync()) {
          // Found nested model files in this subdirectory, move them up
          for (final subFile in entity.listSync(recursive: true)) {
            if (subFile is File) {
              final relative = p.relative(subFile.path, from: entity.path);
              final destFile = File(p.join(stagingDir.path, relative));
              destFile.parent.createSync(recursive: true);
              subFile.copySync(destFile.path);
            }
          }
          entity.deleteSync(recursive: true);
          break;
        }
      }
    }
  }

  bool _isBzip2(Uint8List bytes) {
    return bytes.length >= 3 &&
        bytes[0] == 0x42 &&
        bytes[1] == 0x5A &&
        bytes[2] == 0x68; // BZh
  }

  bool _isZip(Uint8List bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04; // PK..
  }

  bool _isGzip(Uint8List bytes) {
    return bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B;
  }

  void _copyDirectorySync(Directory source, Directory destination) {
    destination.createSync(recursive: true);
    for (final entity in source.listSync(recursive: false)) {
      if (entity is Directory) {
        final newDir =
            Directory(p.join(destination.path, p.basename(entity.path)));
        _copyDirectorySync(entity, newDir);
      } else if (entity is File) {
        entity.copySync(p.join(destination.path, p.basename(entity.path)));
      }
    }
  }
}
