import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/service/sync/sync_decision_helper.dart';
import 'package:anx_reader/service/sync/webdav_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

enum SyncWorkflowStep {
  uploadDatabase,
  downloadDatabase,
  uploadFiles,
  skipFilesNoOp,
  showAbortedDialog,
  throwRemoteBackupNotFound,
}

/// A pure test seam simulating the sync decision and execution flow
/// to verify end-to-end orchestration without requiring real network or UI.
class MockSyncWorkflowExecutor {
  final List<SyncWorkflowStep> executedSteps = [];

  SyncDirection? determineSyncDirection({
    required SyncDirection requestedDirection,
    required bool hasRemoteDb,
  }) {
    if (!hasRemoteDb) {
      return SyncDecisionHelper.resolveDirectionForEmptyRemote(
          requestedDirection);
    }
    return requestedDirection;
  }

  Future<void> syncDatabase({
    required SyncDirection direction,
    required bool hasRemoteDb,
  }) async {
    switch (direction) {
      case SyncDirection.upload:
        executedSteps.add(SyncWorkflowStep.uploadDatabase);
        break;
      case SyncDirection.download:
        if (hasRemoteDb) {
          executedSteps.add(SyncWorkflowStep.downloadDatabase);
        } else {
          executedSteps.add(SyncWorkflowStep.showAbortedDialog);
          executedSteps.add(SyncWorkflowStep.throwRemoteBackupNotFound);
          throw const RemoteBackupNotFoundException();
        }
        break;
      case SyncDirection.both:
        if (!hasRemoteDb) {
          executedSteps.add(SyncWorkflowStep.uploadDatabase);
        } else {
          executedSteps.add(SyncWorkflowStep.downloadDatabase);
        }
        break;
    }
  }

  Future<void> syncFiles({
    required List<String> currentFiles,
  }) async {
    if (SyncDecisionHelper.canSkipFileSync(currentFiles)) {
      executedSteps.add(SyncWorkflowStep.skipFilesNoOp);
      return;
    }
    executedSteps.add(SyncWorkflowStep.uploadFiles);
  }

  Future<bool> runSyncWorkflow({
    required SyncDirection requestedDirection,
    required bool hasRemoteDb,
    required List<String> currentFiles,
  }) async {
    final finalDirection = determineSyncDirection(
      requestedDirection: requestedDirection,
      hasRemoteDb: hasRemoteDb,
    );
    if (finalDirection == null) {
      return false;
    }

    try {
      await syncDatabase(
        direction: finalDirection,
        hasRemoteDb: hasRemoteDb,
      );

      // upload direction must NOT be intercepted even if local library is empty
      if (SyncDecisionHelper.shouldInterceptEmptyCurrent(finalDirection) &&
          currentFiles.isEmpty) {
        executedSteps.add(SyncWorkflowStep.showAbortedDialog);
        return false;
      }

      await syncFiles(currentFiles: currentFiles);
      return true;
    } on RemoteBackupNotFoundException {
      return false;
    }
  }
}

void main() {
  group('WebdavClient.handleReadPropsError', () {
    test('returns null when DioException has status code 404', () {
      final dio404 = DioException(
        requestOptions: RequestOptions(path: '/anx/database.db'),
        response: Response(
          requestOptions: RequestOptions(path: '/anx/database.db'),
          statusCode: 404,
        ),
        type: DioExceptionType.badResponse,
      );

      final result = WebdavClient.handleReadPropsError(dio404);
      expect(result, isNull);
    });

    test('rethrows DioException when status code is 401 (unauthorized)', () {
      final dio401 = DioException(
        requestOptions: RequestOptions(path: '/anx/database.db'),
        response: Response(
          requestOptions: RequestOptions(path: '/anx/database.db'),
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );

      expect(
        () => WebdavClient.handleReadPropsError(dio401),
        throwsA(isA<DioException>().having(
          (e) => e.response?.statusCode,
          'statusCode',
          equals(401),
        )),
      );
    });

    test('rethrows DioException when status code is 500 (server error)', () {
      final dio500 = DioException(
        requestOptions: RequestOptions(path: '/anx/database.db'),
        response: Response(
          requestOptions: RequestOptions(path: '/anx/database.db'),
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      );

      expect(
        () => WebdavClient.handleReadPropsError(dio500),
        throwsA(isA<DioException>().having(
          (e) => e.response?.statusCode,
          'statusCode',
          equals(500),
        )),
      );
    });

    test('rethrows DioException on connection timeout without response', () {
      final dioTimeout = DioException(
        requestOptions: RequestOptions(path: '/anx/database.db'),
        type: DioExceptionType.connectionTimeout,
        error: 'Connection timed out',
      );

      expect(
        () => WebdavClient.handleReadPropsError(dioTimeout),
        throwsA(isA<DioException>().having(
          (e) => e.type,
          'type',
          equals(DioExceptionType.connectionTimeout),
        )),
      );
    });

    test('rethrows non-Dio exceptions unchanged', () {
      final genericException = Exception('Filesystem error');

      expect(
        () => WebdavClient.handleReadPropsError(genericException),
        throwsA(equals(genericException)),
      );
    });
  });

  group('SyncDecisionHelper unit decisions', () {
    test('resolveDirectionForEmptyRemote retains download on explicit download', () {
      final result = SyncDecisionHelper.resolveDirectionForEmptyRemote(
          SyncDirection.download);
      expect(result, equals(SyncDirection.download));
    });

    test('resolveDirectionForEmptyRemote resolves upload for upload and both', () {
      expect(
        SyncDecisionHelper.resolveDirectionForEmptyRemote(SyncDirection.upload),
        equals(SyncDirection.upload),
      );
      expect(
        SyncDecisionHelper.resolveDirectionForEmptyRemote(SyncDirection.both),
        equals(SyncDirection.upload),
      );
    });

    test('shouldInterceptEmptyCurrent is false for upload and true for download', () {
      expect(
        SyncDecisionHelper.shouldInterceptEmptyCurrent(SyncDirection.upload),
        isFalse,
      );
      expect(
        SyncDecisionHelper.shouldInterceptEmptyCurrent(SyncDirection.download),
        isTrue,
      );
    });

    test('canSkipFileSync is true only when totalCurrentFiles is empty', () {
      expect(SyncDecisionHelper.canSkipFileSync([]), isTrue);
      expect(SyncDecisionHelper.canSkipFileSync(['file/a.epub']), isFalse);
    });
  });

  group('WebDAV Empty Remote Sync Scenarios', () {
    test('空远端 + 本地有书 + upload：允许数据库/文件同步，不弹取消', () async {
      final executor = MockSyncWorkflowExecutor();
      final success = await executor.runSyncWorkflow(
        requestedDirection: SyncDirection.upload,
        hasRemoteDb: false,
        currentFiles: ['file/book1.epub', 'cover/book1.jpg'],
      );

      expect(success, isTrue);
      expect(executor.executedSteps, [
        SyncWorkflowStep.uploadDatabase,
        SyncWorkflowStep.uploadFiles,
      ]);
      expect(
        executor.executedSteps.contains(SyncWorkflowStep.showAbortedDialog),
        isFalse,
      );
    });

    test('空远端 + 本地无书 + upload：允许上传空数据库，文件同步 no-op，不弹取消', () async {
      final executor = MockSyncWorkflowExecutor();
      final success = await executor.runSyncWorkflow(
        requestedDirection: SyncDirection.upload,
        hasRemoteDb: false,
        currentFiles: [],
      );

      expect(success, isTrue);
      expect(executor.executedSteps, [
        SyncWorkflowStep.uploadDatabase,
        SyncWorkflowStep.skipFilesNoOp,
      ]);
      expect(
        executor.executedSteps.contains(SyncWorkflowStep.showAbortedDialog),
        isFalse,
      );
    });

    test('空远端 + explicit download：不能暗改成 upload；明确返回/错误为无远端备份', () async {
      final executor = MockSyncWorkflowExecutor();
      final success = await executor.runSyncWorkflow(
        requestedDirection: SyncDirection.download,
        hasRemoteDb: false,
        currentFiles: ['file/local_book.epub'],
      );

      expect(success, isFalse);
      expect(executor.executedSteps, [
        SyncWorkflowStep.showAbortedDialog,
        SyncWorkflowStep.throwRemoteBackupNotFound,
      ]);
      expect(
        executor.executedSteps.contains(SyncWorkflowStep.uploadDatabase),
        isFalse,
        reason: 'Explicit download on empty remote must never silently upload database',
      );
      expect(
        executor.executedSteps.contains(SyncWorkflowStep.uploadFiles),
        isFalse,
        reason: 'Explicit download on empty remote must never silently upload files',
      );
    });
  });
}
