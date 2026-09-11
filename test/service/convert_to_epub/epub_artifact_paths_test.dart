import 'dart:io';

import 'package:anx_reader/service/convert_to_epub/epub_artifact_paths.dart';
import 'package:test/test.dart';

void main() {
  group('EPUB artifact paths and lifecycle cleanup', () {
    late Directory tempBaseDir;

    setUp(() {
      tempBaseDir = Directory.systemTemp.createTempSync('anx_test_base_');
    });

    tearDown(() {
      if (tempBaseDir.existsSync()) {
        tempBaseDir.deleteSync(recursive: true);
      }
    });

    test('generates isolated unique working directory and epub file', () {
      final paths1 = generateEpubArtifactPaths(tempBaseDir);
      final paths2 = generateEpubArtifactPaths(tempBaseDir);

      expect(paths1.workingDir.path, isNot(equals(paths2.workingDir.path)));
      expect(paths1.outputFile.path, isNot(equals(paths2.outputFile.path)));
      expect(paths1.workingDir.path, isNot(equals(paths1.outputFile.path)));
      expect(paths1.outputFile.path.endsWith('.epub'), isTrue);
      expect(paths2.outputFile.path.endsWith('.epub'), isTrue);
    });

    test('does not rely on or incorporate raw book title in temporary paths', () {
      const dangerousTitle = 'Chapter 1: / \\ ? * < > | " & % #';
      final paths = generateEpubArtifactPaths(tempBaseDir);

      expect(paths.workingDir.path.contains(dangerousTitle), isFalse);
      expect(paths.outputFile.path.contains(dangerousTitle), isFalse);
      expect(paths.workingDir.path.startsWith(tempBaseDir.path), isTrue);
      expect(paths.outputFile.path.startsWith(tempBaseDir.path), isTrue);
    });

    test('supports explicit uniqueId for deterministic tests', () {
      final paths = generateEpubArtifactPaths(
        tempBaseDir,
        uniqueId: 'custom-unique-1234',
      );

      expect(
        paths.workingDir.path,
        equals('${tempBaseDir.path}/epub_build_custom-unique-1234'),
      );
      expect(
        paths.outputFile.path,
        equals('${tempBaseDir.path}/custom-unique-1234.epub'),
      );
    });

    test('cleanupEpubArtifacts on success deletes working dir and preserves output file', () {
      final paths = generateEpubArtifactPaths(tempBaseDir);
      paths.workingDir.createSync(recursive: true);
      final dummyInner = File('${paths.workingDir.path}/mimetype');
      dummyInner.writeAsStringSync('application/epub+zip');

      paths.outputFile.createSync();
      paths.outputFile.writeAsStringSync('dummy zip content');

      expect(paths.workingDir.existsSync(), isTrue);
      expect(paths.outputFile.existsSync(), isTrue);

      cleanupEpubArtifacts(
        workingDir: paths.workingDir,
        outputFile: paths.outputFile,
        success: true,
      );

      expect(paths.workingDir.existsSync(), isFalse);
      expect(paths.outputFile.existsSync(), isTrue);

      // clean up created test output file
      paths.outputFile.deleteSync();
    });

    test('cleanupEpubArtifacts on failure deletes both working dir and output file', () {
      final paths = generateEpubArtifactPaths(tempBaseDir);
      paths.workingDir.createSync(recursive: true);
      final dummyInner = File('${paths.workingDir.path}/mimetype');
      dummyInner.writeAsStringSync('application/epub+zip');

      paths.outputFile.createSync();
      paths.outputFile.writeAsStringSync('partial zip content');

      expect(paths.workingDir.existsSync(), isTrue);
      expect(paths.outputFile.existsSync(), isTrue);

      cleanupEpubArtifacts(
        workingDir: paths.workingDir,
        outputFile: paths.outputFile,
        success: false,
      );

      expect(paths.workingDir.existsSync(), isFalse);
      expect(paths.outputFile.existsSync(), isFalse);
    });

    test('cleanupEpubArtifacts handles missing paths gracefully without throwing', () {
      final paths = generateEpubArtifactPaths(tempBaseDir);

      expect(paths.workingDir.existsSync(), isFalse);
      expect(paths.outputFile.existsSync(), isFalse);

      expect(
        () => cleanupEpubArtifacts(
          workingDir: paths.workingDir,
          outputFile: paths.outputFile,
          success: false,
        ),
        returnsNormally,
      );
    });
  });
}
