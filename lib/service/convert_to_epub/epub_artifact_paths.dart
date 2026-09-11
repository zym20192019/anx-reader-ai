import 'dart:io';

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
/// Uses [uniqueId] (defaulting to UUID v4) instead of book title so concurrent
/// conversions, batch runs, or duplicate titles never collide.
EpubArtifactPaths generateEpubArtifactPaths(
  Directory baseDir, {
  String? uniqueId,
}) {
  final id = uniqueId ?? const Uuid().v4();
  return EpubArtifactPaths(
    workingDir: Directory('${baseDir.path}/epub_build_$id'),
    outputFile: File('${baseDir.path}/$id.epub'),
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
