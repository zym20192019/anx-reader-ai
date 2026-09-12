import 'dart:async';
import 'dart:io' as io;
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_source.dart';
import 'package:anx_reader/models/remote_file.dart';
import 'package:anx_reader/models/sync_state_model.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/service/database_sync_manager.dart';
import 'package:anx_reader/service/txt_cache/txt_cache_manager.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/utils/get_path/databases_path.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sync.g.dart';

/// Helper to resolve the canonical sync file path for a [Book].
///
/// For TXT books (determined by [Book.sourceFormat], file extension, etc.),
/// this returns [Book.sourceFilePath] if available and non-empty;
/// otherwise it falls back to [Book.filePath] to support legacy unmigrated records.
/// For non-TXT books, it always returns [Book.filePath].
/// Cached EPUB paths ([Book.cacheFilePath]) must NEVER be returned as canonical sync files.
String resolveBookSyncPath(Book book) {
  final isTxt = isTxtSourceFormat(book.sourceFormat) ||
      book.filePath.toLowerCase().endsWith('.txt') ||
      (book.sourceFilePath != null &&
          book.sourceFilePath!.toLowerCase().endsWith('.txt'));

  if (isTxt &&
      book.sourceFilePath != null &&
      book.sourceFilePath!.trim().isNotEmpty) {
    return book.sourceFilePath!.trim();
  }
  return book.filePath;
}

/// Helper to convert a relative file path (e.g. `file/foo.txt` or `cover/bar.png`)
/// into the corresponding remote path under `anx/data/`.
String toRemoteDataPath(String relativePath) {
  final normalized = relativePath.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
  return 'anx/data/$normalized';
}

/// Helper to filter out historical remote EPUB files and cache artifacts
/// from remote orphan deletion.
///
/// Under the source-file-only sync model, remote `file/*.epub` files are preserved
/// to prevent deleting historical EPUB copies from older sync versions or dual-format setups.
/// Returns true if the remote relative path can be safely pruned when missing from [totalCurrentFiles].
bool shouldPruneRemoteOrphan(String remoteRelativePath) {
  final normalized = remoteRelativePath.replaceAll('\\', '/').toLowerCase();
  // Never prune remote epubs under file/
  if (normalized.startsWith('file/') && normalized.endsWith('.epub')) {
    return false;
  }
  return true;
}

/// Helper to determine if a cache path is safe to delete.
///
/// Safety rules:
/// - Must not be empty or null
/// - Must not be identical to sourceFilePath or filePath
/// - Must point to a generated EPUB inside the dedicated `txt_epub` cache.
bool isSafeCachePathToDelete(
  String? cachePath, {
  required String resolvedSyncPath,
  required String filePath,
}) {
  if (cachePath == null || cachePath.trim().isEmpty) return false;
  final normalizedCache = cachePath.replaceAll('\\', '/').trim();
  final normalizedSync = resolvedSyncPath.replaceAll('\\', '/').trim();
  final normalizedFile = filePath.replaceAll('\\', '/').trim();

  if (normalizedCache == normalizedSync || normalizedCache == normalizedFile) {
    return false;
  }

  final cacheMarker = '${TxtCacheManager.cacheDirectoryName}/';
  final markerIndex = normalizedCache.indexOf(cacheMarker);
  if (markerIndex < 0) return false;

  final cacheRelative = normalizedCache.substring(markerIndex);
  return RegExp(
    r'^txt_epub/[A-Za-z0-9._-]+/generated\.epub$',
  ).hasMatch(cacheRelative);
}

@Riverpod(keepAlive: true)
class Sync extends _$Sync {
  static final Sync _instance = Sync._internal();

  factory Sync() {
    return _instance;
  }

  Sync._internal();

  // Flag to prevent multiple sync direction dialogs
  bool _isShowingDirectionDialog = false;

  @override
  SyncStateModel build() {
    return const SyncStateModel(
      direction: SyncDirection.both,
      isSyncing: false,
      total: 0,
      count: 0,
      fileName: '',
    );
  }

  void changeState(SyncStateModel s) {
    state = s;
  }

  SyncClientBase? get _syncClient {
    if (SyncClientFactory.currentClient == null) {
      SyncClientFactory.initializeCurrentClient();
    }
    return SyncClientFactory.currentClient;
  }

  Future<void> init() async {
    final client = _syncClient;
    if (client == null) {
      AnxLog.severe('No sync client configured');
      return;
    }

    AnxLog.info('${client.protocolName}: init');
  }

  Future<void> _createAnxDir() async {
    final client = _syncClient;
    if (client == null) return;

    if (!await client.isExist('/anx/data/file')) {
      await client.mkdirAll('anx/data/file');
      await client.mkdirAll('anx/data/cover');
    }
  }

  Future<bool> shouldSync() async {
    if (!Prefs().webdavStatus) {
      return false;
    }

    if (Prefs().onlySyncWhenWifi &&
        !(await Connectivity().checkConnectivity())
            .contains(ConnectivityResult.wifi)) {
      if (Prefs().syncCompletedToast) {
        AnxToast.show(L10n.of(navigatorKey.currentContext!).webdavOnlyWifi);
      }
      return false;
    }

    return true;
  }

  Future<SyncDirection?> determineSyncDirection(
      SyncDirection requestedDirection) async {
    final client = _syncClient;
    if (client == null) return null;

    String remoteDbFileName = 'database$currentDbVersion.db';

    // Check for version mismatch
    List<RemoteFile> remoteFiles = [];
    try {
      remoteFiles = await client.safeReadDir('/anx');
    } catch (e) {
      await _createAnxDir();
      remoteFiles = await client.safeReadDir('/anx');
    }

    for (var file in remoteFiles) {
      if (file.name != null &&
          file.name!.startsWith('database') &&
          file.name!.endsWith('.db')) {
        String versionStr =
            file.name!.replaceAll('database', '').replaceAll('.db', '');
        int version = int.tryParse(versionStr) ?? 0;
        if (version > currentDbVersion) {
          await _showDatabaseVersionMismatchDialog(version);
          return null;
        }
      }
    }

    RemoteFile? remoteDb = await client.readProps('anx/$remoteDbFileName');
    final databasePath = await getAnxDataBasesPath();
    final localDbPath = join(databasePath, 'app_database.db');
    io.File localDb = io.File(localDbPath);

    // Use getLatestModTime to include WAL file modification time
    final localDbTime = DBHelper.getLatestModTime(localDbPath);
    AnxLog.info('localDbTime: $localDbTime, remoteDbTime: ${remoteDb?.mTime}');

    // Less than 5s difference, no sync needed
    if (remoteDb != null &&
        localDbTime.difference(remoteDb.mTime!).inSeconds.abs() < 5) {
      return null;
    }

    if (remoteDb == null) {
      return SyncDirection.upload;
    }

    if (requestedDirection == SyncDirection.both) {
      if (Prefs().lastUploadBookDate == null ||
          Prefs()
                  .lastUploadBookDate!
                  .difference(remoteDb.mTime!)
                  .inSeconds
                  .abs() >
              5) {
        return await _showSyncDirectionDialog(localDb, remoteDb);
      }
    }

    return requestedDirection;
  }

  Future<SyncDirection?> _showSyncDirectionDialog(
      io.File localDb, RemoteFile remoteDb) async {
    // Prevent multiple dialogs from showing simultaneously
    if (_isShowingDirectionDialog) {
      AnxLog.info('Sync direction dialog already showing, skipping');
      return null;
    }

    _isShowingDirectionDialog = true;
    try {
      return await showDialog<SyncDirection>(
        context: navigatorKey.currentContext!,
        barrierDismissible: false, // Prevent dismissing by tapping outside
        builder: (context) => AlertDialog(
          title: Text(L10n.of(context).commonAttention),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.of(context).webdavSyncDirection),
              SizedBox(height: 10),
              Text(
                  '${L10n.of(context).bookSyncStatusLocalUpdateTime} ${localDb.lastModifiedSync()}'),
              Text(
                  '${L10n.of(context).syncRemoteDataUpdateTime} ${remoteDb.mTime}'),
            ],
          ),
          actionsOverflowDirection: VerticalDirection.up,
          actionsOverflowAlignment: OverflowBarAlignment.center,
          actionsOverflowButtonSpacing: 10,
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(SyncDirection.upload);
              },
              child: Text(L10n.of(context).webdavUpload),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(SyncDirection.download);
              },
              child: Text(L10n.of(context).webdavDownload),
            ),
          ],
        ),
      );
    } finally {
      _isShowingDirectionDialog = false;
    }
  }

  Future<void> _showDatabaseVersionMismatchDialog(int remoteVersion) async {
    await SmartDialog.show(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).webdavSyncAborted),
        content: Text(
            L10n.of(context).syncMismatchTip(currentDbVersion, remoteVersion)),
        actions: [
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
            },
            child: Text(L10n.of(context).commonOk),
          ),
        ],
      ),
    );
  }

  Future<void> syncData(
    SyncDirection direction,
    WidgetRef? ref, {
    SyncTrigger trigger = SyncTrigger.auto,
  }) async {
    final client = _syncClient;
    if (client == null) {
      AnxLog.info('No sync client configured');
      return;
    }

    if (trigger == SyncTrigger.auto && !Prefs().autoSync) {
      return;
    }

    if (!(await shouldSync())) {
      return;
    }

    // Check if already syncing - MOVED BEFORE determineSyncDirection
    if (state.isSyncing) {
      AnxLog.info('Sync already in progress, skipping');
      return;
    }

    // Test ping and initialize
    try {
      await client.ping();
      await _createAnxDir();
    } catch (e) {
      AnxLog.severe('Sync connection failed, ping failed2\n${e.toString()}');
      return;
    }

    AnxLog.info('Sync ping success');

    // Determine sync direction
    SyncDirection? finalDirection = await determineSyncDirection(direction);
    if (finalDirection == null) {
      return; // User cancelled or no sync needed
    }

    changeState(state.copyWith(isSyncing: true));

    if (Prefs().syncCompletedToast) {
      AnxToast.show(L10n.of(navigatorKey.currentContext!).webdavSyncing);
    }

    try {
      await syncDatabase(finalDirection);

      if (await isCurrentEmpty()) {
        await _showSyncAbortedDialog();
        changeState(state.copyWith(isSyncing: false));
        return;
      }

      if (Prefs().syncCompletedToast) {
        AnxToast.show(L10n.of(navigatorKey.currentContext!).webdavSyncingFiles);
      }

      await syncFiles();

      imageCache.clear();
      imageCache.clearLiveImages();

      try {
        ref?.read(bookListProvider.notifier).refresh();
        ref?.read(groupDaoProvider.notifier).refresh();
      } catch (e) {
        AnxLog.info('Failed to refresh book list: $e');
      }

      // Backup cleanup is now handled by DatabaseSyncManager

      if (Prefs().syncCompletedToast) {
        AnxToast.show(L10n.of(navigatorKey.currentContext!).webdavSyncComplete);
      }
    } catch (e, s) {
      if (e is DioException && e.type == DioExceptionType.connectionError) {
        AnxToast.show('Sync connection failed, check your network');
        AnxLog.severe('Sync connection failed, connection error\n$e, $s');
      } else {
        AnxToast.show('Sync failed\n$e');
        AnxLog.severe('Sync failed\n$e, $s');
      }
    } finally {
      changeState(state.copyWith(isSyncing: false));
      // _deleteBackUpDb();
    }
  }

  Future<void> syncFiles() async {
    final client = _syncClient;
    if (client == null) return;

    AnxLog.info('Sync: syncFiles');
    List<String> currentBooks = await bookDao.getCurrentSourceFiles();
    List<String> currentCover = await bookDao.getCurrentCover();

    List<String> remoteBooksName = [];
    List<String> remoteCoversName = [];

    List<RemoteFile> remoteBooks = await client.safeReadDir('/anx/data/file');
    remoteBooksName = List.generate(
        remoteBooks.length, (index) => 'file/${remoteBooks[index].name!}');

    List<RemoteFile> remoteCovers = await client.safeReadDir('/anx/data/cover');
    remoteCoversName = List.generate(
        remoteCovers.length, (index) => 'cover/${remoteCovers[index].name!}');

    List<String> totalCurrentFiles = [...currentCover, ...currentBooks];
    List<String> totalRemoteFiles = [...remoteBooksName, ...remoteCoversName];

    List<String> localBooks =
        io.Directory(getBasePath('file')).listSync().map((e) {
      return 'file/${basename(e.path)}';
    }).toList();
    List<String> localCovers =
        io.Directory(getBasePath('cover')).listSync().map((e) {
      return 'cover/${basename(e.path)}';
    }).toList();
    List<String> totalLocalFiles = [...localBooks, ...localCovers];

    // Abort if totalCurrentFiles is empty
    if (totalCurrentFiles.isEmpty) {
      await _showSyncAbortedDialog();
      return;
    }

    // Sync cover files
    for (var file in currentCover) {
      if (!remoteCoversName.contains(file) && localCovers.contains(file)) {
        await uploadFile(getBasePath(file), 'anx/data/$file');
      }
      if (!io.File(getBasePath(file)).existsSync() &&
          remoteCoversName.contains(file)) {
        await downloadFile('anx/data/$file', getBasePath(file));
      }
    }

    // Sync book files
    for (var file in currentBooks) {
      if (!remoteBooksName.contains(file) && localBooks.contains(file)) {
        await uploadFile(getBasePath(file), 'anx/data/$file');
      }
    }

    // Remove remote files not in database (never delete historical remote EPUBs under source-only sync)
    for (var file in totalRemoteFiles) {
      if (!totalCurrentFiles.contains(file) && shouldPruneRemoteOrphan(file)) {
        await client.remove('anx/data/$file');
      }
    }

    // Do not delete local files here. In source-only mode an existing local
    // EPUB may be a legacy artifact that must remain auditable and recoverable.
    // Explicit book deletion/replacement owns its own cleanup.
    ref.read(syncStatusProvider.notifier).refresh();
  }

  Future<void> syncDatabase(SyncDirection direction) async {
    final client = _syncClient;
    if (client == null) return;

    String remoteDbFileName = 'database$currentDbVersion.db';
    RemoteFile? remoteDb = await client.readProps('anx/$remoteDbFileName');

    final databasePath = await getAnxDataBasesPath();
    final localDbPath = join(databasePath, 'app_database.db');
    io.File localDb = io.File(localDbPath);

    try {
      switch (direction) {
        case SyncDirection.upload:
          // Use VACUUM INTO to create a snapshot, avoiding database locking/closing
          final snapshotPath = await DBHelper.prepareUploadSnapshot();
          try {
            await uploadFile(snapshotPath, 'anx/$remoteDbFileName');
          } finally {
            // Clean up snapshot file
            final snapshotFile = io.File(snapshotPath);
            if (snapshotFile.existsSync()) {
              await snapshotFile.delete();
            }
          }
          break;

        case SyncDirection.download:
          if (remoteDb != null) {
            // Use safe database download method
            final result = await DatabaseSyncManager.safeDownloadDatabase(
              client: client,
              remoteDbFileName: remoteDbFileName,
              onProgress: (received, total) {
                changeState(state.copyWith(
                  direction: SyncDirection.download,
                  fileName: remoteDbFileName,
                  isSyncing: received < total,
                  count: received,
                  total: total,
                ));
              },
            );

            if (!result.isSuccess) {
              await DatabaseSyncManager.showSyncErrorDialog(result);
              AnxLog.severe('Database sync failed: ${result.message}');
              // Don't throw exception, let sync continue with file sync
              return;
            }
          } else {
            await _showSyncAbortedDialog();
            return;
          }
          break;

        case SyncDirection.both:
          if (remoteDb == null ||
              remoteDb.mTime!.isBefore(localDb.lastModifiedSync())) {
            // Use VACUUM INTO to create a snapshot, avoiding database locking/closing
            final snapshotPath = await DBHelper.prepareUploadSnapshot();
            try {
              await uploadFile(snapshotPath, 'anx/$remoteDbFileName');
            } finally {
              // Clean up snapshot file
              final snapshotFile = io.File(snapshotPath);
              if (snapshotFile.existsSync()) {
                await snapshotFile.delete();
              }
            }
          } else if (remoteDb.mTime!.isAfter(localDb.lastModifiedSync())) {
            // Use safe database download method
            final result = await DatabaseSyncManager.safeDownloadDatabase(
              client: client,
              remoteDbFileName: remoteDbFileName,
              onProgress: (received, total) {
                changeState(state.copyWith(
                  direction: SyncDirection.download,
                  fileName: remoteDbFileName,
                  isSyncing: received < total,
                  count: received,
                  total: total,
                ));
              },
            );

            if (!result.isSuccess) {
              await DatabaseSyncManager.showSyncErrorDialog(result);
              AnxLog.severe('Database sync failed: ${result.message}');
              // Don't throw exception, let sync continue with file sync
              return;
            }
          }
          break;
      }

      // Update last sync time
      RemoteFile? newRemoteDb = await client.readProps('anx/$remoteDbFileName');
      if (newRemoteDb != null) {
        Prefs().lastUploadBookDate = newRemoteDb.mTime;
      }
    } catch (e) {
      AnxLog.severe('Failed to sync database\n$e');
      rethrow;
    }
  }

  Future<void> uploadFile(
    String localPath,
    String remotePath, [
    bool replace = true,
  ]) async {
    changeState(state.copyWith(
      direction: SyncDirection.upload,
      fileName: localPath.split('/').last,
    ));

    final client = _syncClient;
    if (client != null) {
      ref.read(syncStatusProvider.notifier).addUploading(remotePath);
      await client.uploadFile(
        localPath,
        remotePath,
        replace: replace,
        onProgress: (sent, total) {
          changeState(state.copyWith(
            isSyncing: true,
            count: sent,
            total: total,
          ));
        },
      );
      ref.read(syncStatusProvider.notifier).removeUploading(remotePath);
    }

    changeState(state.copyWith(isSyncing: false));
  }

  Future<void> downloadFile(String remotePath, String localPath) async {
    changeState(state.copyWith(
      direction: SyncDirection.download,
      fileName: remotePath.split('/').last,
    ));

    final client = _syncClient;
    if (client != null) {
      ref.read(syncStatusProvider.notifier).addDownloading(remotePath);
      await client.downloadFile(
        remotePath,
        localPath,
        onProgress: (received, total) {
          changeState(state.copyWith(
            isSyncing: true,
            count: received,
            total: total,
          ));
        },
      );
      ref.read(syncStatusProvider.notifier).removeDownloading(remotePath);
    }

    changeState(state.copyWith(isSyncing: false));
  }

  Future<List<String>> listRemoteBookFiles() async {
    final client = _syncClient;
    if (client == null) return [];

    final remoteFiles = await client.safeReadDir('/anx/data/file');
    return remoteFiles.map((e) => e.name!).toList();
  }

  Future<void> downloadBook(Book book) async {
    final syncStatus = await ref.read(syncStatusProvider.future);

    if (!syncStatus.remoteOnly.contains(book.id)) {
      AnxToast.show(L10n.of(navigatorKey.currentContext!)
          .bookSyncStatusBookNotFoundRemote);
      return;
    }

    try {
      await _downloadBook(book);
    } catch (e) {
      // Error handling is done in _downloadBook
    }
  }

  Future<void> releaseBook(Book book) async {
    final syncStatus = await ref.read(syncStatusProvider.future);
    final syncPath = resolveBookSyncPath(book);
    final isTxt = isTxtSourceFormat(book.sourceFormat) ||
        book.filePath.toLowerCase().endsWith('.txt') ||
        (book.sourceFilePath != null &&
            book.sourceFilePath!.toLowerCase().endsWith('.txt'));

    Future<void> deleteLocalFiles() async {
      // 1. Delete canonical local source / file
      final localFile = io.File(getBasePath(syncPath));
      if (await localFile.exists()) {
        await localFile.delete();
      }

      // 2. For TXT, also delete local cache file if safe
      if (isTxt &&
          isSafeCachePathToDelete(
            book.cacheFilePath,
            resolvedSyncPath: syncPath,
            filePath: book.filePath,
          )) {
        try {
          final cacheFile =
              await TxtCacheManager.resolveBookCacheFile(book.cacheFilePath);
          if (cacheFile != null && await cacheFile.exists()) {
            // The marker lives beside the EPUB. Remove the whole fingerprint
            // directory so a released book cannot leave a misleading cache.
            await cacheFile.parent.delete(recursive: true);
          }
        } on ArgumentError catch (e) {
          // A malformed cache metadata value must never block source release.
          AnxLog.warning('Skipping invalid TXT cache path: $e');
        }
      }
    }

    Future<void> uploadCanonicalBook() async {
      try {
        final remotePath = toRemoteDataPath(syncPath);
        final localPath = getBasePath(syncPath);
        await uploadFile(localPath, remotePath);
      } catch (e) {
        AnxToast.show(
            L10n.of(navigatorKey.currentContext!).bookSyncStatusUploadFailed);
        AnxLog.severe('Failed to upload book\n$e');
        rethrow;
      }
    }

    if (syncStatus.remoteOnly.contains(book.id)) {
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).bookSyncStatusSpaceReleased);
      return;
    } else if (syncStatus.both.contains(book.id)) {
      await deleteLocalFiles();
      ref.read(syncStatusProvider.notifier).refresh();
    } else {
      try {
        await uploadCanonicalBook();
        await deleteLocalFiles();
      } catch (e) {
        AnxToast.show(
            L10n.of(navigatorKey.currentContext!).bookSyncStatusUploadFailed);
      }
    }
  }

  Future<void> downloadMultipleBooks(List<int> bookIds) async {
    AnxLog.info(
        'WebDAV: Starting download for ${bookIds.length} remote books.');
    int successCount = 0;
    int failCount = 0;

    try {
      final client = _syncClient;
      if (client != null) {
        await client.ping();
      } else {
        throw Exception('No sync client configured');
      }
    } catch (e) {
      AnxLog.severe(
          'WebDAV connection failed before batch download, ping failed\n${e.toString()}');
      return;
    }

    for (final bookId in bookIds) {
      try {
        final book = await bookDao.selectBookById(bookId);
        AnxLog.info('WebDAV: Downloading book ID $bookId: ${book.title}');
        await _downloadBook(book);
        successCount++;
      } catch (e) {
        AnxLog.severe('WebDAV: Failed to download book ID $bookId: $e');
        failCount++;
      }
    }

    AnxLog.info(L10n.of(navigatorKey.currentContext!)
        .webdavBatchDownloadFinishedReport(successCount, failCount));
    AnxToast.show(L10n.of(navigatorKey.currentContext!)
        .webdavBatchDownloadFinishedReport(successCount, failCount));
  }

  Future<void> _downloadBook(Book book) async {
    try {
      final syncPath = resolveBookSyncPath(book);
      AnxToast.show(L10n.of(navigatorKey.currentContext!)
          .bookSyncStatusDownloadingBook(syncPath));
      final remotePath = toRemoteDataPath(syncPath);
      final localPath = getBasePath(syncPath);
      await downloadFile(remotePath, localPath);
    } catch (e) {
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).bookSyncStatusDownloadFailed);
      AnxLog.severe('Failed to download book\n$e');
      rethrow;
    }
  }

  Future<bool> isCurrentEmpty() async {
    List<String> currentBooks = await bookDao.getCurrentBooks();
    List<String> currentCover = await bookDao.getCurrentCover();
    List<String> totalCurrentFiles = [...currentCover, ...currentBooks];
    return totalCurrentFiles.isEmpty;
  }

  /// Get available database backup list
  Future<List<String>> getAvailableBackups() async {
    return await DatabaseSyncManager.getAvailableBackups();
  }

  /// Show database backup management dialog
  Future<void> showBackupManagementDialog() async {
    try {
      final backups = await getAvailableBackups();

      await SmartDialog.show(
        builder: (context) => AlertDialog(
          title: Text(L10n.of(context).databaseBackupManagement),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(L10n.of(context).availableBackups),
                const SizedBox(height: 12),
                if (backups.isEmpty)
                  Text(
                    L10n.of(context).noBackupsAvailable,
                    style: const TextStyle(color: Colors.grey),
                  )
                else
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      itemCount: backups.length,
                      itemBuilder: (context, index) {
                        final backup = backups[index];
                        final fileName = backup.split('/').last;
                        final timestamp = fileName
                            .replaceAll('backup_database_', '')
                            .replaceAll('.db', '');

                        return ListTile(
                          title: Text('Backup ${index + 1}'),
                          subtitle: Text(timestamp),
                          trailing: ElevatedButton(
                            onPressed: () async {
                              // Navigator.of(context).pop();
                              await _restoreFromBackup(backup);
                            },
                            child: Text(L10n.of(context).restore),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(L10n.of(context).commonCancel),
            ),
          ],
        ),
      );
    } catch (e) {
      AnxLog.severe('Failed to show backup management dialog: $e');
      AnxToast.show('Failed to get backup list: $e');
    }
  }

  /// Restore database from specified backup
  Future<void> _restoreFromBackup(String backupPath) async {
    try {
      final databasePath = await getAnxDataBasesPath();
      final localDbPath = join(databasePath, 'app_database.db');

      // Confirmation dialog
      final confirmed = await SmartDialog.show<bool>(
        builder: (context) => AlertDialog(
          title: Text(L10n.of(context).confirmRestore),
          content: Text(L10n.of(context).restoreWarning),
          actions: [
            TextButton(
              onPressed: () => SmartDialog.dismiss(result: false),
              child: Text(L10n.of(context).commonCancel),
            ),
            FilledButton(
              onPressed: () => SmartDialog.dismiss(result: true),
              child: Text(L10n.of(context).commonConfirm),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Execute restore
      await DBHelper.close();
      await io.File(backupPath).copy(localDbPath);
      await DBHelper().initDB();

      // Refresh related providers
      try {
        ref.read(bookListProvider.notifier).refresh();
        ref.read(groupDaoProvider.notifier).refresh();
      } catch (e) {
        AnxLog.info('Failed to refresh providers after restore: $e');
      }

      AnxToast.show(L10n.of(navigatorKey.currentContext!).restoreSuccess);
      AnxLog.info('Database restored from backup: $backupPath');
    } catch (e) {
      AnxLog.severe('Failed to restore from backup: $e');
      AnxToast.show('Restore failed: $e');
    }
  }

  Future<void> _showSyncAbortedDialog() async {
    await SmartDialog.show(
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).webdavSyncAborted),
        content: Text(L10n.of(context).webdavSyncAbortedContent),
        actions: [
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
            },
            child: Text(L10n.of(context).commonOk),
          ),
        ],
      ),
    );
  }
}
