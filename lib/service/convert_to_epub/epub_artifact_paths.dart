import 'dart:io';

import 'package:anx_reader/service/convert_to_epub/txt/txt_title_helper.dart';
import 'package:uuid/uuid.dart';

/// Resolved temporary paths for an EPUB conversion task.
class EpubArtifactPaths {
  const EpubArtifactPaths({
    required this.workingDir,
    required this.outputFile,
  });

  /// Isolated temporary working directory used during EPUB assembly.
  final Directory workingDir;

  /// Temporary target EPUB archive file.
  final File outputFile;
}

/// Generates unique, isolated filesystem paths for EPUB conversion.
///
/// Uses [uniqueId] (defaulting to UUID v4) so concurrent conversions, batch runs,
/// or duplicate titles never collide.
///
/// If [safeTitle] is provided, it is sanitized via [toSafePathComponent] and used
/// only as a human-readable prefix in the final [outputFile] name (`${safeTitle}_$id.epub`).
/// The temporary working directory [workingDir] remains strictly UUID-isolated
/// (`epub_build_$id`) to ensure filesystem safety and avoid nested directory bugs.
EpubArtifactPaths generateEpubArtifactPaths(
  Directory baseDir, {
  String? uniqueId,
  String? safeTitle,
}) {
  final id = uniqueId ?? const Uuid().v4();
  final sanitized = (safeTitle != null && safeTitle.trim().isNotEmpty)
      ? toSafePathComponent(safeTitle)
      : null;
  final fileName = (sanitized != null && sanitized.isNotEmpty)
      ? '${sanitized}_$id.epub'
      : '$id.epub';
  return EpubArtifactPaths(
    workingDir: Directory('${baseDir.path}/epub_build_$id'),
    outputFile: File('${baseDir.path}/$fileName'),
  );
}

/// Cleans up temporary artifacts from an EPUB conversion.
///
/// On success, the working directory is removed and the packaged output file is preserved.
/// On failure, both the working directory and any incomplete output file are deleted.
void cleanupEpubArtifacts({
  required Directory workingDir,
  required File outputFile,
  required bool success,
}) {
  if (workingDir.existsSync()) {
    try {
      workingDir.deleteSync(recursive: true);
    } catch (_) {}
  }
  if (!success && outputFile.existsSync()) {
    try {
      outputFile.deleteSync();
    } catch (_) {}
  }
}
