import 'dart:io';

import 'package:anx_reader/service/txt_cache/txt_cache_manager.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempRoot;
  late TxtCacheManager manager;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('anx-txt-cache-test-');
    manager = TxtCacheManager(cacheRoot: tempRoot);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('keeps cache paths isolated from the source file directory', () {
    final file = manager.cacheFileFor('abc123');
    expect(file.path, contains('${Platform.pathSeparator}abc123${Platform.pathSeparator}'));
    expect(file.path, endsWith('generated.epub'));
  });

  test('missing and mismatched markers invalidate a cache', () async {
    expect(await manager.isValid('fingerprint-a'), isFalse);

    final file = manager.cacheFileFor('fingerprint-a');
    await file.parent.create(recursive: true);
    await file.writeAsString('epub');
    expect(await manager.isValid('fingerprint-a'), isFalse);

    await manager.fingerprintFileFor('fingerprint-a').writeAsString('fingerprint-b');
    expect(await manager.isValid('fingerprint-a'), isFalse);

    await manager.fingerprintFileFor('fingerprint-a').writeAsString('fingerprint-a');
    expect(await manager.isValid('fingerprint-a'), isTrue);
  });

  test('creates a cache and reuses it when the fingerprint is unchanged', () async {
    final source = File('${tempRoot.path}${Platform.pathSeparator}source.txt')
      ..writeAsStringSync('source');
    var conversions = 0;

    final first = await manager.ensureCache(
      source: source,
      fingerprint: 'stable',
      converter: (input) async {
        conversions++;
        final output = File('${tempRoot.path}${Platform.pathSeparator}out-$conversions.epub');
        await output.writeAsString('epub-$conversions');
        return output;
      },
    );
    final second = await manager.ensureCache(
      source: source,
      fingerprint: 'stable',
      converter: (input) async {
        conversions++;
        final output = File('${tempRoot.path}${Platform.pathSeparator}out-$conversions.epub');
        await output.writeAsString('epub-$conversions');
        return output;
      },
    );

    expect(first.path, second.path);
    expect(conversions, 1);
    expect(await first.readAsString(), 'epub-1');
  });

  test('conversion failure preserves the previous valid cache', () async {
    final source = File('${tempRoot.path}${Platform.pathSeparator}source.txt')
      ..writeAsStringSync('source');

    final cache = await manager.ensureCache(
      source: source,
      fingerprint: 'same',
      converter: (input) async {
        final output = File('${tempRoot.path}${Platform.pathSeparator}initial.epub');
        await output.writeAsString('old');
        return output;
      },
    );

    // Invalidate the marker so a rebuild is attempted, while keeping the old
    // EPUB in place as the fallback artifact.
    await manager.fingerprintFileFor('same').writeAsString('stale');
    await expectLater(
      manager.ensureCache(
        source: source,
        fingerprint: 'same',
        converter: (input) async => throw StateError('conversion failed'),
      ),
      throwsStateError,
    );

    expect(await cache.exists(), isTrue);
    expect(await cache.readAsString(), 'old');
  });

  test('successful rebuild replaces the old cache and marker', () async {
    final source = File('${tempRoot.path}${Platform.pathSeparator}source.txt')
      ..writeAsStringSync('source');

    final cache = await manager.ensureCache(
      source: source,
      fingerprint: 'replace',
      converter: (input) async {
        final output = File('${tempRoot.path}${Platform.pathSeparator}old.epub');
        await output.writeAsString('old');
        return output;
      },
    );
    await manager.fingerprintFileFor('replace').writeAsString('stale');

    final rebuilt = await manager.ensureCache(
      source: source,
      fingerprint: 'replace',
      converter: (input) async {
        final output = File('${tempRoot.path}${Platform.pathSeparator}new.epub');
        await output.writeAsString('new');
        return output;
      },
    );

    expect(rebuilt.path, cache.path);
    expect(await rebuilt.readAsString(), 'new');
    expect(await manager.isValid('replace'), isTrue);
  });

  test('marker write failure restores old target and old marker and cleans up temp', () async {
    final source = File('${tempRoot.path}${Platform.pathSeparator}source.txt')
      ..writeAsStringSync('source');

    // 1. Setup initial valid cache
    final initialCache = await manager.ensureCache(
      source: source,
      fingerprint: 'marker-fail',
      converter: (input) async {
        final output = File('${tempRoot.path}${Platform.pathSeparator}initial.epub');
        await output.writeAsString('initial-content');
        return output;
      },
    );
    expect(await initialCache.readAsString(), 'initial-content');
    expect(await manager.isValid('marker-fail'), isTrue);

    // Corrupt marker so ensureCache attempts to rebuild
    await manager.fingerprintFileFor('marker-fail').writeAsString('old-marker');

    // 2. Trigger ensureCache with injected markerWriter that throws
    await expectLater(
      manager.ensureCache(
        source: source,
        fingerprint: 'marker-fail',
        converter: (input) async {
          final output = File('${tempRoot.path}${Platform.pathSeparator}new.epub');
          await output.writeAsString('new-attempt-content');
          return output;
        },
        markerWriter: (marker, content) async {
          throw const FileSystemException('Simulated disk full or permission denied on marker');
        },
      ),
      throwsA(isA<FileSystemException>()),
    );

    // 3. Verify rollback: old target EPUB and old marker are restored
    expect(await initialCache.exists(), isTrue);
    expect(await initialCache.readAsString(), 'initial-content');
    final markerFile = manager.fingerprintFileFor('marker-fail');
    expect(await markerFile.exists(), isTrue);
    expect(await markerFile.readAsString(), 'old-marker');

    // 4. Verify no temporary files remain in target directory
    final dir = manager.directoryFor('marker-fail');
    final tmpFiles = dir.listSync().where((entity) =>
        entity.path.contains('.tmp.') ||
        entity.path.contains('.backup.'));
    expect(tmpFiles, isEmpty);
  });

  test('file replacement failure restores old target and marker and cleans up temp', () async {
    final source = File('${tempRoot.path}${Platform.pathSeparator}source.txt')
      ..writeAsStringSync('source');

    // 1. Setup initial valid cache
    final initialCache = await manager.ensureCache(
      source: source,
      fingerprint: 'replace-fail',
      converter: (input) async {
        final output = File('${tempRoot.path}${Platform.pathSeparator}initial.epub');
        await output.writeAsString('initial-content');
        return output;
      },
    );
    await manager.fingerprintFileFor('replace-fail').writeAsString('stale-marker');

    // 2. Trigger ensureCache with injected fileReplacer that throws
    await expectLater(
      manager.ensureCache(
        source: source,
        fingerprint: 'replace-fail',
        converter: (input) async {
          final output = File('${tempRoot.path}${Platform.pathSeparator}new.epub');
          await output.writeAsString('new-attempt-content');
          return output;
        },
        fileReplacer: (sourceFile, targetPath) async {
          throw const FileSystemException('Simulated file rename failure');
        },
      ),
      throwsA(isA<FileSystemException>()),
    );

    // 3. Verify old target and marker remain intact
    expect(await initialCache.exists(), isTrue);
    expect(await initialCache.readAsString(), 'initial-content');
    final markerFile = manager.fingerprintFileFor('replace-fail');
    expect(await markerFile.exists(), isTrue);
    expect(await markerFile.readAsString(), 'stale-marker');

    // 4. Verify no temporary files or backups remain
    final dir = manager.directoryFor('replace-fail');
    final tmpFiles = dir.listSync().where((entity) =>
        entity.path.contains('.tmp.') ||
        entity.path.contains('.backup.'));
    expect(tmpFiles, isEmpty);
  });

  test('conversion failure cleans up any temp files', () async {
    final source = File('${tempRoot.path}${Platform.pathSeparator}source.txt')
      ..writeAsStringSync('source');

    await expectLater(
      manager.ensureCache(
        source: source,
        fingerprint: 'clean-temp',
        converter: (input) async {
          throw StateError('Conversion crashed before returning file');
        },
      ),
      throwsStateError,
    );

    final dir = manager.directoryFor('clean-temp');
    if (await dir.exists()) {
      final tmpFiles = dir.listSync().where((entity) =>
          entity.path.contains('.tmp.') ||
          entity.path.contains('.backup.'));
      expect(tmpFiles, isEmpty);
    }
  });
}
