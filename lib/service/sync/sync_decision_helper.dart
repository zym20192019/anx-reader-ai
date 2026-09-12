import 'package:anx_reader/enums/sync_direction.dart';

/// Exception thrown when an explicit download is requested but remote database does not exist.
class RemoteBackupNotFoundException implements Exception {
  final String message;
  const RemoteBackupNotFoundException(
      [this.message = 'Remote database backup not found']);

  @override
  String toString() => message;
}

/// Helper for sync decision making and control flow.
class SyncDecisionHelper {
  /// Determines sync direction when remote database does not exist.
  ///
  /// For explicit download, retains download so it can fail with an explicit
  /// "no remote backup" error instead of unexpectedly uploading local data.
  /// For upload or both, initiates upload.
  static SyncDirection resolveDirectionForEmptyRemote(
      SyncDirection requestedDirection) {
    if (requestedDirection == SyncDirection.download) {
      return SyncDirection.download;
    }
    return SyncDirection.upload;
  }

  /// Whether empty local data (0 books, 0 covers) should abort the sync flow.
  ///
  /// Upload direction should NEVER be aborted just because local library is empty.
  static bool shouldInterceptEmptyCurrent(SyncDirection direction) {
    return direction != SyncDirection.upload;
  }

  /// Evaluates file sync action based on whether there are current files to sync.
  ///
  /// If empty, file sync is a normal no-op and should NOT show aborted dialog.
  static bool canSkipFileSync(List<String> totalCurrentFiles) {
    return totalCurrentFiles.isEmpty;
  }
}
