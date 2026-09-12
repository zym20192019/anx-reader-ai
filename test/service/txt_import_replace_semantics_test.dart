import 'dart:io';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_source.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/convert_to_epub/txt/convert_from_txt.dart';
import 'package:anx_reader/service/txt_cache/txt_cache_key.dart';
import 'package:anx_reader/service/txt_cache/txt_cache_manager.dart';
import 'package:test/test.dart';

void main() {
  group('TXT Import Artifact & Path Semantics', () {
    test('allocateImportTxtRelativePath allocates clean path without collisions', () {
      final allocated = allocateImportTxtRelativePath(
        title: '三国演义',
        existingPaths: [],
      );
      expect(allocated, equals('file/三国演义.txt'));
    });

    test('allocateImportTxtRelativePath increments collision suffixes properly', () {
      final allocated1 = allocateImportTxtRelativePath(
        title: '三国演义',
        existingPaths: ['file/三国演义.txt'],
      );
      expect(allocated1, equals('file/三国演义 (1).txt'));

      final allocated2 = allocateImportTxtRelativePath(
        title: '三国演义',
        existingPaths: ['三国演义.txt', '三国演义 (1).txt'],
      );
      expect(allocated2, equals('file/三国演义 (2).txt'));
    });

    test('normalizeTxtLineBreaks handles CRLF, CR, and LF uniformly', () {
      const crlf = 'Line 1\r\nLine 2\r\nLine 3';
      const cr = 'Line 1\rLine 2\rLine 3';
      const lf = 'Line 1\nLine 2\nLine 3';

      expect(normalizeTxtLineBreaks(crlf), equals('Line 1\nLine 2\nLine 3'));
      expect(normalizeTxtLineBreaks(cr), equals('Line 1\nLine 2\nLine 3'));
      expect(normalizeTxtLineBreaks(lf), equals('Line 1\nLine 2\nLine 3'));
    });

    test('getNormalizedTxtLength counts code units after newline normalization', () async {
      final tempDir = await Directory.systemTemp.createTemp('txt-len-test-');
      try {
        final file = File('${tempDir.path}${Platform.pathSeparator}test.txt');
        await file.writeAsString('Hello\r\nWorld\r\n');
        // 'Hello\nWorld\n' has 5 + 1 + 5 + 1 = 12 characters
        expect(getNormalizedTxtLength(file), equals(12));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('TxtCacheManager relativeCachePathFor and resolveRelativeCachePath bidirectional consistency', () async {
      final tempDir = await Directory.systemTemp.createTemp('txt-cache-mgr-test-');
      try {
        final manager = TxtCacheManager(cacheRoot: tempDir);
        const testFingerprint = 'abcde12345ffeedd';
        final relPath = manager.relativeCachePathFor(testFingerprint);

        expect(relPath, equals('txt_epub/$testFingerprint/generated.epub'));

        final resolvedFile = manager.resolveRelativeCachePath(relPath);
        final expectedPath = manager.cacheFileFor(testFingerprint).path;
        expect(resolvedFile.path, equals(expectedPath));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolveBookMd5OnSave for new TXT book sets both fileMd5 and sourceMd5 to source hash', () {
      const sourceHash = 'txt_source_md5_12345';
      final resolution = resolveBookMd5OnSave(
        isExistingBook: false,
        effectiveFileMd5: sourceHash,
        effectiveSourceMd5: sourceHash,
        provideBook: null,
      );

      expect(resolution.fileMd5, equals(sourceHash));
      expect(resolution.sourceMd5, equals(sourceHash));
    });
  });

  group('Duplicate Source MD5 Semantics', () {
    test('Existing book hit preserves provideBook.fileMd5 and does not overwrite with new hash', () {
      final existingBook = Book(
        id: 7,
        title: 'Original Title',
        coverPath: 'cover/original.png',
        filePath: 'file/original.txt',
        lastReadPosition: '100',
        readingPercentage: 0.2,
        author: 'Author',
        isDeleted: false,
        rating: 4.0,
        fileMd5: 'canonical_source_hash',
        sourceMd5: 'canonical_source_hash',
        createTime: DateTime(2026, 1, 1),
        updateTime: DateTime(2026, 1, 1),
      );

      final resolution = resolveBookMd5OnSave(
        isExistingBook: true,
        effectiveFileMd5: 'new_temp_file_hash',
        effectiveSourceMd5: 'canonical_source_hash',
        provideBook: existingBook,
      );

      expect(resolution.fileMd5, equals('canonical_source_hash'));
      expect(resolution.sourceMd5, equals('canonical_source_hash'));
    });

    test('Legacy existing book with null sourceMd5 adopts new sourceMd5 without modifying fileMd5', () {
      final legacyBook = Book(
        id: 8,
        title: 'Legacy Book',
        coverPath: 'cover/legacy.png',
        filePath: 'file/legacy.epub',
        lastReadPosition: '',
        readingPercentage: 0.0,
        author: 'Old Author',
        isDeleted: false,
        rating: 0.0,
        fileMd5: 'legacy_epub_hash',
        sourceMd5: null,
        createTime: DateTime(2025, 1, 1),
        updateTime: DateTime(2025, 1, 1),
      );

      final resolution = resolveBookMd5OnSave(
        isExistingBook: true,
        effectiveFileMd5: 'any_hash',
        effectiveSourceMd5: 'new_adopted_source_md5',
        provideBook: legacyBook,
      );

      expect(resolution.fileMd5, equals('legacy_epub_hash'));
      expect(resolution.sourceMd5, equals('new_adopted_source_md5'));
    });
  });

  group('TXT Replace Semantics', () {
    test('resolveReplaceFilePath preserves existing path for TXT books', () {
      final path = resolveReplaceFilePath(
        existingFilePath: 'file/my_existing_book.txt',
        isTxt: true,
        title: 'New Title',
        extension: '.txt',
      );

      expect(path, equals('file/my_existing_book.txt'));
    });

    test('resolveReplaceFilePath converts extension to .txt for non-TXT existing book replaced by TXT', () {
      final path = resolveReplaceFilePath(
        existingFilePath: 'file/my_existing_book.epub',
        isTxt: true,
        title: 'New Title',
        extension: '.txt',
      );

      expect(path, equals('file/my_existing_book.txt'));
    });

    test('resolveReplaceFilePath generates timestamped file name for non-TXT replacement', () {
      final path1 = resolveReplaceFilePath(
        existingFilePath: 'file/my_existing_book.txt',
        isTxt: false,
        title: 'Replacement Book',
        extension: '.epub',
      );

      expect(path1, startsWith('file/Replacement Book-'));
      expect(path1, endsWith('.epub'));
    });

    test('resolveBookMd5OnReplace sets both hashes to new source hash when replacing with TXT', () {
      const newTxtMd5 = 'brand_new_txt_md5_abcdef';
      final resolution = resolveBookMd5OnReplace(
        isTxt: true,
        newSourceFileMd5: newTxtMd5,
        newProcessedFileMd5: newTxtMd5,
      );

      expect(resolution.fileMd5, equals(newTxtMd5));
      expect(resolution.sourceMd5, equals(newTxtMd5));
    });

    test('resolveBookMd5OnReplace sets fileMd5 to newProcessedFileMd5 ?? newSourceFileMd5 when replacing with TXT', () {
      const newTxtMd5 = 'txt_md5_123';
      final resolution = resolveBookMd5OnReplace(
        isTxt: true,
        newSourceFileMd5: newTxtMd5,
        newProcessedFileMd5: null,
      );

      expect(resolution.fileMd5, equals(newTxtMd5));
      expect(resolution.sourceMd5, equals(newTxtMd5));
    });

    test('resolveBookMd5OnReplace for non-TXT sets both hashes to new file MD5', () {
      const newEpubMd5 = 'new_epub_md5_789';
      final resolution = resolveBookMd5OnReplace(
        isTxt: false,
        newSourceFileMd5: newEpubMd5,
        newProcessedFileMd5: newEpubMd5,
      );

      expect(resolution.fileMd5, equals(newEpubMd5));
      expect(resolution.sourceMd5, equals(newEpubMd5));
    });
  });

  group('Book Model TXT Source & Cache Fields', () {
    test('Book supports all Task 4 fields and roundtrips through copyWith', () {
      final book = Book(
        id: 1,
        title: 'Test TXT Book',
        coverPath: 'cover/test.png',
        filePath: 'file/test.txt',
        lastReadPosition: '0',
        readingPercentage: 0.0,
        author: 'Unknown',
        isDeleted: false,
        rating: 0.0,
        fileMd5: 'md5_123',
        sourceMd5: 'md5_123',
        sourceFilePath: 'file/test.txt',
        sourceFormat: 'txt',
        cacheFilePath: 'txt_epub/fp_123/generated.epub',
        cacheFingerprint: 'fp_123',
        sourceTextLength: 50000,
        createTime: DateTime(2026, 9, 12),
        updateTime: DateTime(2026, 9, 12),
      );

      expect(book.isDeleted, isFalse);
      expect(book.filePath, equals('file/test.txt'));
      expect(book.sourceFilePath, equals('file/test.txt'));
      expect(book.sourceFormat, equals('txt'));
      expect(book.fileMd5, equals('md5_123'));
      expect(book.sourceMd5, equals('md5_123'));
      expect(book.cacheFilePath, equals('txt_epub/fp_123/generated.epub'));
      expect(book.cacheFingerprint, equals('fp_123'));
      expect(book.sourceTextLength, equals(50000));

      final updated = book.copyWith(
        readingPercentage: 0.5,
        sourceTextOffset: 25000,
      );

      expect(updated.readingPercentage, equals(0.5));
      expect(updated.sourceTextOffset, equals(25000));
      expect(updated.cacheFilePath, equals('txt_epub/fp_123/generated.epub'));
    });
  });
}
