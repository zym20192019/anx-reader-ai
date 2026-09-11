/// Integration test suite for EPUB generation and packaging via `createEpub`.
///
/// Exercises real file I/O, temporary directory isolation, ZIP archive packaging
/// and decompression, OEBPS XML/XHTML specification compliance, XML escaping,
/// paragraph reconstruction, concurrency safety, failure cleanup via `finally`,
/// and source TXT retention via `prepareImportedFile`.
///
/// Test environment note:
/// This test exercises `createEpub` in `lib/service/convert_to_epub/create_epub.dart`,
/// which transitively references application logging (`AnxLog`) and path utilities.
/// In the Flutter project structure, run these tests using the Flutter test runner:
///   `flutter test test/service/convert_to_epub/txt_to_epub_integration_test.dart`
///
/// Pure Dart unit tests with zero transitive Flutter dependencies are located in:
///   - `test/service/convert_to_epub/epub_artifact_paths_test.dart`
///   - `test/service/convert_to_epub/generate_toc_test.dart`
///   - `test/service/convert_to_epub/txt/txt_paragraphs_test.dart`
///   - `test/service/convert_to_epub/txt/txt_title_helper_test.dart`
///   - `test/service/convert_to_epub/txt/convert_from_txt_test.dart`
///   - `test/service/prepare_imported_file_test.dart`
///
/// Note: Tests are not claimed to have run locally because flutter and dart binaries
/// are not installed in this environment.
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/convert_to_epub/create_epub.dart';
import 'package:anx_reader/service/convert_to_epub/epub_artifact_paths.dart';
import 'package:anx_reader/service/convert_to_epub/section.dart';
import 'package:anx_reader/service/convert_to_epub/txt/txt_title_helper.dart';
import 'package:anx_reader/service/prepare_imported_file.dart';
import 'package:archive/archive_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('anx_txt_to_epub_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Unzips an EPUB file into an in-memory map of {relativeFilePath: contentBytes}.
  Map<String, List<int>> unzipEpub(File epubFile) {
    expect(epubFile.existsSync(), isTrue,
        reason: 'EPUB file must exist at ${epubFile.path}');
    final bytes = epubFile.readAsBytesSync();
    expect(bytes.isNotEmpty, isTrue, reason: 'EPUB file must not be empty');

    final archive = ZipDecoder().decodeBytes(bytes);
    final fileMap = <String, List<int>>{};
    for (final file in archive) {
      if (file.isFile) {
        fileMap[file.name] = file.content as List<int>;
      }
    }
    return fileMap;
  }

  String decodeEntry(Map<String, List<int>> unzipped, String path) {
    final bytes = unzipped[path];
    expect(bytes, isNotNull,
        reason: 'Archive entry "$path" must exist in EPUB');
    return utf8.decode(bytes!);
  }

  group('EPUB structure and XML/XHTML validation', () {
    test('creates unzippable EPUB with complete spec-compliant file structure',
        () async {
      const bookTitle = '三体：黑暗森林';
      const author = '刘慈欣';
      final sections = [
        Section('第一章 序章', '第一行正文。\n第二行正文。', 1),
        Section('第二章 面壁者', '面壁计划正式启动。\n四位面壁者名单公布。', 1),
      ];

      final epubFile = await createEpub(
        bookTitle,
        author,
        sections,
        tempDir: tempDir,
        uniqueId: 'test-spec-structure-001',
      );

      final unzipped = unzipEpub(epubFile);

      // 1. mimetype: MUST be present and content exactly application/epub+zip
      expect(unzipped.containsKey('mimetype'), isTrue);
      final mimetypeContent = utf8.decode(unzipped['mimetype']!).trim();
      expect(mimetypeContent, equals('application/epub+zip'));

      // 2. META-INF/container.xml: MUST point to OEBPS/content.opf
      expect(unzipped.containsKey('META-INF/container.xml'), isTrue);
      final containerXml = decodeEntry(unzipped, 'META-INF/container.xml');
      expect(containerXml, contains('version="1.0"'));
      expect(
        containerXml,
        contains(
            '<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'),
      );

      // 3. OEBPS/content.opf: MUST define metadata, manifest, spine
      expect(unzipped.containsKey('OEBPS/content.opf'), isTrue);
      final opfXml = decodeEntry(unzipped, 'OEBPS/content.opf');
      expect(opfXml, contains('<dc:title>$bookTitle</dc:title>'));
      expect(opfXml, contains('<dc:creator>$author</dc:creator>'));
      expect(opfXml, contains('<dc:identifier id="pub-id">urn:uuid:'));
      expect(
        opfXml,
        contains(
            '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'),
      );
      expect(
        opfXml,
        contains('<item id="css" href="style.css" media-type="text/css"/>'),
      );
      expect(
        opfXml,
        contains(
            '<item id="item0" href="xhtml/0.xhtml" media-type="application/xhtml+xml"/>'),
      );
      expect(
        opfXml,
        contains(
            '<item id="item1" href="xhtml/1.xhtml" media-type="application/xhtml+xml"/>'),
      );
      expect(opfXml, contains('<itemref idref="item0"/>'));
      expect(opfXml, contains('<itemref idref="item1"/>'));

      // 4. OEBPS/toc.ncx: MUST contain docTitle and navPoints
      expect(unzipped.containsKey('OEBPS/toc.ncx'), isTrue);
      final ncxXml = decodeEntry(unzipped, 'OEBPS/toc.ncx');
      expect(ncxXml, contains('<text>$bookTitle</text>'));
      expect(ncxXml, contains('第一章 序章'));
      expect(ncxXml, contains('第二章 面壁者'));
      expect(ncxXml, contains('src="xhtml/0.xhtml"'));
      expect(ncxXml, contains('src="xhtml/1.xhtml"'));

      // 5. OEBPS/style.css: MUST exist with paragraph formatting
      expect(unzipped.containsKey('OEBPS/style.css'), isTrue);
      final css = decodeEntry(unzipped, 'OEBPS/style.css');
      expect(css, contains('line-height: 1.8;'));
      expect(css, contains('text-indent: 2em;'));

      // 6. OEBPS/xhtml/*.xhtml: MUST exist for each section
      expect(unzipped.containsKey('OEBPS/xhtml/0.xhtml'), isTrue);
      expect(unzipped.containsKey('OEBPS/xhtml/1.xhtml'), isTrue);

      final xhtml0 = decodeEntry(unzipped, 'OEBPS/xhtml/0.xhtml');
      expect(xhtml0, contains('<?xml version="1.0" encoding="utf-8"?>'));
      expect(xhtml0, contains('xmlns="http://www.w3.org/1999/xhtml"'));
      expect(
        xhtml0,
        contains('<link rel="stylesheet" type="text/css" href="../style.css"/>'),
      );
      expect(xhtml0, contains('<h1>第一章 序章</h1>'));
      expect(xhtml0, contains('<p>第一行正文。</p>'));
      expect(xhtml0, contains('<p>第二行正文。</p>'));
    });

    test('escapes XML special characters in title, creator, chapter and body',
        () async {
      const specialTitle = 'Bed & Breakfast: <Tom & Jerry> "Special" \'Edition\'';
      const specialAuthor = 'Author & Co. <info@example.com>';
      final sections = [
        Section(
          'Chapter 1: Fish & Chips <Part A>',
          'Paragraph with special chars: 1 < 2 & 5 > 4. He said: "Hello" and \'Goodbye\'.',
          1,
        ),
      ];

      final epubFile = await createEpub(
        specialTitle,
        specialAuthor,
        sections,
        tempDir: tempDir,
        uniqueId: 'test-xml-escape-001',
      );

      final unzipped = unzipEpub(epubFile);

      // Verify content.opf escaping
      final opfXml = decodeEntry(unzipped, 'OEBPS/content.opf');
      expect(
        opfXml,
        contains(
            '&lt;Tom &amp; Jerry&gt; &quot;Special&quot; &apos;Edition&apos;'),
      );
      expect(opfXml, contains('Author &amp; Co. &lt;info@example.com&gt;'));
      expect(opfXml, isNot(contains('<dc:title>$specialTitle</dc:title>')));

      // Verify toc.ncx escaping
      final ncxXml = decodeEntry(unzipped, 'OEBPS/toc.ncx');
      expect(ncxXml, contains('Fish &amp; Chips &lt;Part A&gt;'));

      // Verify xhtml escaping
      final xhtml = decodeEntry(unzipped, 'OEBPS/xhtml/0.xhtml');
      expect(xhtml, contains('<h1>Chapter 1: Fish &amp; Chips &lt;Part A&gt;</h1>'));
      expect(
        xhtml,
        contains(
            '<p>Paragraph with special chars: 1 &lt; 2 &amp; 5 &gt; 4. He said: &quot;Hello&quot; and &apos;Goodbye&apos;.</p>'),
      );
      expect(xhtml, isNot(contains('< 2 & 5 >')));
    });

    test('ensures body has no empty <p> tags under empty lines and whitespace runs',
        () async {
      final sections = [
        Section(
          '第一章 空行测试',
          '第一段。\n\n\n\n第二段。\n   \n　　\n\n第三段。\n\n',
          1,
        ),
      ];

      final epubFile = await createEpub(
        '空行测试书',
        '作者',
        sections,
        tempDir: tempDir,
        uniqueId: 'test-no-empty-p-001',
      );

      final unzipped = unzipEpub(epubFile);
      final xhtml = decodeEntry(unzipped, 'OEBPS/xhtml/0.xhtml');

      expect(xhtml, contains('<p>第一段。</p>'));
      expect(xhtml, contains('<p>第二段。</p>'));
      expect(xhtml, contains('<p>第三段。</p>'));

      // Must NOT contain empty <p></p> or whitespace-only <p>
      expect(xhtml, isNot(contains('<p></p>')));
      expect(xhtml, isNot(contains(RegExp(r'<p>\s*</p>'))));
    });

    test('omits heading tag when section title is empty (preface/intro)',
        () async {
      final sections = [
        Section('', '这是没有标题的前言段落。', 1),
        Section('正文第一章', '正式内容第一段。', 1),
      ];

      final epubFile = await createEpub(
        '无标题章节测试',
        '作者',
        sections,
        tempDir: tempDir,
        uniqueId: 'test-empty-title-section-001',
      );

      final unzipped = unzipEpub(epubFile);
      final xhtml0 = decodeEntry(unzipped, 'OEBPS/xhtml/0.xhtml');
      expect(xhtml0, isNot(contains('<h1>')));
      expect(xhtml0, isNot(contains('<h1/>')));
      expect(xhtml0, contains('<p>这是没有标题的前言段落。</p>'));

      final xhtml1 = decodeEntry(unzipped, 'OEBPS/xhtml/1.xhtml');
      expect(xhtml1, contains('<h1>正文第一章</h1>'));
      expect(xhtml1, contains('<p>正式内容第一段。</p>'));
    });
  });

  group('Paragraph reconstruction, concurrency, and failure cleanup', () {
    test('joins hard wraps without duplicating lines across Chinese, English, and hyphens',
        () async {
      const rawContent = '''
这是一段因为原文本编辑排版
硬回车断开的中文句子，后面
应该自然连贯成一个段落。

This is an English paragraph that was hard-
wrapped by the legacy terminal export
tool without losing meaning.

Another English line ending with punctuation.
A subsequent sentence that starts here.
''';

      final sections = [Section('第一章 排版测试', rawContent, 1)];

      final epubFile = await createEpub(
        '排版连接测试',
        '测试员',
        sections,
        tempDir: tempDir,
        uniqueId: 'test-wrap-join-001',
      );

      final unzipped = unzipEpub(epubFile);
      final xhtml = decodeEntry(unzipped, 'OEBPS/xhtml/0.xhtml');

      // Chinese lines joined directly without spaces
      expect(
        xhtml,
        contains(
            '<p>这是一段因为原文本编辑排版硬回车断开的中文句子，后面应该自然连贯成一个段落。</p>'),
      );

      // Hyphenated word joined cleanly
      expect(
        xhtml,
        contains(
            'This is an English paragraph that was hard-wrapped by the legacy terminal export tool without losing meaning.'),
      );

      // English sentences ending with punctuation and starting with next word
      expect(
        xhtml,
        contains('<p>Another English line ending with punctuation.</p>'),
      );
      expect(
        xhtml,
        contains('<p>A subsequent sentence that starts here.</p>'),
      );
    });

    test('concurrent createEpub invocations with identical titles generate unique paths without collision',
        () async {
      const sharedTitle = '并发同名书籍';
      const author = '并发测试员';
      final sectionsA = [Section('Chapter 1', 'Instance A content', 1)];
      final sectionsB = [Section('Chapter 1', 'Instance B content', 1)];

      // Launch both simultaneously
      final futureA = createEpub(
        sharedTitle,
        author,
        sectionsA,
        tempDir: tempDir,
      );
      final futureB = createEpub(
        sharedTitle,
        author,
        sectionsB,
        tempDir: tempDir,
      );

      final results = await Future.wait([futureA, futureB]);
      final fileA = results[0];
      final fileB = results[1];

      // Paths must be distinct
      expect(fileA.path, isNot(equals(fileB.path)));
      expect(fileA.existsSync(), isTrue);
      expect(fileB.existsSync(), isTrue);

      // Unzip both independently to ensure neither was corrupted
      final unzippedA = unzipEpub(fileA);
      final unzippedB = unzipEpub(fileB);

      final contentA = decodeEntry(unzippedA, 'OEBPS/xhtml/0.xhtml');
      final contentB = decodeEntry(unzippedB, 'OEBPS/xhtml/0.xhtml');

      expect(contentA, contains('Instance A content'));
      expect(contentA, isNot(contains('Instance B content')));

      expect(contentB, contains('Instance B content'));
      expect(contentB, isNot(contains('Instance A content')));

      // Working build directories must have been cleaned up
      final buildDirs = tempDir
          .listSync()
          .whereType<Directory>()
          .where((dir) => dir.path.contains('epub_build_'))
          .toList();
      expect(buildDirs, isEmpty,
          reason: 'All temporary build directories must be cleaned up on success');
    });

    test('failure during packaging cleans up working directory via finally block',
        () async {
      const bookTitle = '失败清理测试书';
      const author = '测试员';
      const uniqueId = 'test-cleanup-failure-sim-001';
      final sections = [Section('第一章', '正文内容', 1)];

      // Pre-calculate target paths generated by createEpub
      final expectedPaths = generateEpubArtifactPaths(
        tempDir,
        uniqueId: uniqueId,
        safeTitle: toSafePathComponent(bookTitle),
      );

      // Create a directory at the expected outputFile path.
      // During createEpub:
      // 1. epubDir (working build dir) is created and populated.
      // 2. zipFile.createSync() fails because the target path is a directory (EISDIR).
      // 3. createEpub enters its finally block with success: false.
      // 4. cleanupEpubArtifacts deletes the working build directory.
      final conflictingDir = Directory(expectedPaths.outputFile.path);
      conflictingDir.createSync(recursive: true);
      expect(conflictingDir.existsSync(), isTrue);

      // Working build directory should not exist yet
      expect(expectedPaths.workingDir.existsSync(), isFalse);

      // Invoke createEpub and verify that an exception is thrown
      await expectLater(
        createEpub(
          bookTitle,
          author,
          sections,
          tempDir: tempDir,
          uniqueId: uniqueId,
        ),
        throwsA(isA<FileSystemException>()),
      );

      // Assert that createEpub's finally block cleaned up the working build directory
      expect(
        expectedPaths.workingDir.existsSync(),
        isFalse,
        reason:
            'Temporary working build directory must be deleted by createEpub finally block on packaging failure',
      );
    });
  });

  group('prepareImportedFile real filesystem and lifecycle behavior', () {
    test('retains source TXT on disk while allowing converter artifact cleanup',
        () async {
      final sourceTxt = File('${tempDir.path}/user_upload_source.txt');
      sourceTxt.writeAsStringSync('用户原始书籍内容，切勿删除！');
      expect(sourceTxt.existsSync(), isTrue);

      final convertedEpub = File('${tempDir.path}/user_upload_source.epub');
      convertedEpub.writeAsStringSync('converted epub binary mock');

      // prepareImportedFile does NOT delete sourceTxt
      final prepared = await prepareImportedFile(
        sourceTxt,
        convertTxt: (src) async => convertedEpub,
      );

      expect(prepared.path, equals(convertedEpub.path));
      expect(sourceTxt.existsSync(), isTrue,
          reason: 'Source TXT must remain intact on filesystem');

      // User files are not owned by import and must not be deleted
      expect(shouldDeleteImportedInput(sourceTxt, ownsFile: false), isFalse);

      // Temporary app-created converted artifacts can be cleaned up
      expect(shouldDeleteImportedInput(convertedEpub, ownsFile: true), isTrue);
      convertedEpub.deleteSync();
      expect(convertedEpub.existsSync(), isFalse);
      expect(sourceTxt.existsSync(), isTrue,
          reason: 'Deleting converted artifact must not affect source TXT');
    });
  });
}
