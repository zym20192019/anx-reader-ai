import 'dart:convert';
import 'dart:io';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/service/book_player/temp_file_manager.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';

void main() {
  group('TempFileManager Concurrency & Isolation Tests', () {
    late Directory tempDir;
    late File fileA;
    late File fileB;
    late TempFileManager manager;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('anx_temp_server_test_');
      fileA = File('${tempDir.path}/book_a.epub')
        ..writeAsStringSync('EPUB_CONTENT_OF_BOOK_A');
      fileB = File('${tempDir.path}/book_b.epub')
        ..writeAsStringSync('EPUB_CONTENT_OF_BOOK_B');
      manager = TempFileManager();
    });

    tearDown(() {
      manager.clear();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('token generation produces distinct tokens even with rapid calls', () {
      final tokens = <String>{};
      for (int i = 0; i < 30; i++) {
        final token = manager.setTempFile(fileA);
        expect(tokens.contains(token), isFalse,
            reason: 'Token $token was duplicated');
        tokens.add(token);
      }
      expect(tokens.length, equals(30));
      expect(manager.count, equals(30));
    });

    test(
        'concurrent requests for A and B return isolated responses, release A leaves B readable, unknown token is 404',
        () async {
      // 1. Register A and B
      final tokenA = manager.setTempFile(fileA);
      final tokenB = manager.setTempFile(fileB);

      expect(tokenA, isNot(equals(tokenB)));
      expect(manager.has(tokenA), isTrue);
      expect(manager.has(tokenB), isTrue);

      // 2. Request A and B via shelf handler
      final reqA = shelf.Request('GET', Uri.parse('http://127.0.0.1/$tokenA'));
      final reqB = shelf.Request('GET', Uri.parse('http://127.0.0.1/$tokenB'));

      final resA = manager.handleRequest(reqA);
      final resB = manager.handleRequest(reqB);

      expect(resA, isNotNull);
      expect(resB, isNotNull);
      expect(resA!.statusCode, equals(200));
      expect(resB!.statusCode, equals(200));

      expect(resA.headers['Content-Type'], equals('application/epub+zip'));
      expect(resA.headers['Access-Control-Allow-Origin'], equals('*'));
      expect(resB.headers['Content-Type'], equals('application/epub+zip'));
      expect(resB.headers['Access-Control-Allow-Origin'], equals('*'));

      final contentA = await resA.readAsString();
      final contentB = await resB.readAsString();

      expect(contentA, equals('EPUB_CONTENT_OF_BOOK_A'));
      expect(contentB, equals('EPUB_CONTENT_OF_BOOK_B'));
      expect(contentA, isNot(equals(contentB)));

      // 3. Release A, B remains readable, A becomes 404
      final releasedA = manager.releaseTempFile(tokenA);
      expect(releasedA, isTrue);
      expect(manager.has(tokenA), isFalse);
      expect(manager.has(tokenB), isTrue);

      final reqAAfter =
          shelf.Request('GET', Uri.parse('http://127.0.0.1/$tokenA'));
      final resAAfter = manager.handleRequest(reqAAfter);
      expect(resAAfter, isNotNull);
      expect(resAAfter!.statusCode, equals(404));

      final reqBAfter =
          shelf.Request('GET', Uri.parse('http://127.0.0.1/$tokenB'));
      final resBAfter = manager.handleRequest(reqBAfter);
      expect(resBAfter, isNotNull);
      expect(resBAfter!.statusCode, equals(200));
      final contentBAfter = await resBAfter.readAsString();
      expect(contentBAfter, equals('EPUB_CONTENT_OF_BOOK_B'));

      // 4. Unknown token returns 404
      final reqUnknown = shelf.Request(
          'GET', Uri.parse('http://127.0.0.1/non_existent_token_99999.epub'));
      final resUnknown = manager.handleRequest(reqUnknown);
      expect(resUnknown, isNotNull);
      expect(resUnknown!.statusCode, equals(404));

      // 5. Release non-existent returns false
      expect(manager.releaseTempFile('non_existent_token_99999.epub'), isFalse);

      // 6. Release B, then B becomes 404
      final releasedB = manager.releaseTempFile(tokenB);
      expect(releasedB, isTrue);
      final resBFinal = manager.handleRequest(reqBAfter);
      expect(resBFinal, isNotNull);
      expect(resBFinal!.statusCode, equals(404));
      expect(manager.count, equals(0));
    });

    test('rejects path traversal and unsafe token patterns', () {
      expect(TempFileManager.isValidToken('valid_token-123.epub'), isTrue);
      expect(TempFileManager.isValidToken('1694389200000.epub'), isTrue);

      // Traversal and illegal patterns
      expect(TempFileManager.isValidToken('../etc/passwd'), isFalse);
      expect(TempFileManager.isValidToken('..'), isFalse);
      expect(TempFileManager.isValidToken('dir/token.epub'), isFalse);
      expect(TempFileManager.isValidToken('dir\\token.epub'), isFalse);
      expect(TempFileManager.isValidToken(''), isFalse);
      expect(TempFileManager.isValidToken('token with space.epub'), isFalse);
      expect(TempFileManager.isValidToken('token?query=1'), isFalse);

      // Multi-segment requests return null from handleRequest so fallthrough can route
      final reqTraversal =
          shelf.Request('GET', Uri.parse('http://127.0.0.1/../etc/passwd'));
      final resTraversal = manager.handleRequest(reqTraversal);
      expect(resTraversal, isNull);

      final reqNested =
          shelf.Request('GET', Uri.parse('http://127.0.0.1/sub/path/book.epub'));
      final resNested = manager.handleRequest(reqNested);
      expect(resNested, isNull);
    });

    test('pruneExpired evicts expired entries by maxAge and caps capacity strictly to maxCount', () {
      var currentTime = DateTime(2026, 9, 11, 10, 0, 0);
      final customManager = TempFileManager(nowProvider: () => currentTime);

      // 1. Test maxAge expiration with injected clock
      final expiredToken = customManager.setTempFile(fileA, token: 'old_file.epub');
      expect(customManager.has(expiredToken), isTrue);

      // Advance clock by 31 minutes (exceeds default 30-minute maxAge)
      currentTime = currentTime.add(const Duration(minutes: 31));

      // Inserting a new entry triggers pruneExpired()
      final activeToken = customManager.setTempFile(fileB, token: 'recent_file.epub');
      expect(customManager.has(expiredToken), isFalse,
          reason: 'Old entry exceeding maxAge must be pruned');
      expect(customManager.has(activeToken), isTrue);
      expect(customManager.count, equals(1));

      // 2. Test maxCount boundary: only remove excess entries when count > maxCount
      customManager.clear();
      currentTime = DateTime(2026, 9, 11, 12, 0, 0);
      customManager.setTempFile(fileA, token: 'f1.epub');
      currentTime = currentTime.add(const Duration(seconds: 1));
      customManager.setTempFile(fileB, token: 'f2.epub');
      currentTime = currentTime.add(const Duration(seconds: 1));
      customManager.setTempFile(fileA, token: 'f3.epub');
      expect(customManager.count, equals(3));

      // Prune down to maxCount = 2: count (3) > maxCount (2), so exactly 1 oldest entry (f1) is pruned
      customManager.pruneExpired(maxCount: 2);
      expect(customManager.count, equals(2));
      expect(customManager.has('f1.epub'), isFalse);
      expect(customManager.has('f2.epub'), isTrue);
      expect(customManager.has('f3.epub'), isTrue);

      // Boundary check: when count (2) == maxCount (2), pruneExpired does NOT prune anything
      customManager.pruneExpired(maxCount: 2);
      expect(customManager.count, equals(2));
      expect(customManager.has('f2.epub'), isTrue);
      expect(customManager.has('f3.epub'), isTrue);
    });

    test(
        'handleRequest preserves multi-segment paths for BookPlayerServer routes and returns 404 for unmapped single-segment tokens',
        () {
      // TempFileManager is mounted as the first check in BookPlayerServer._handleRequests.
      // 1. Multi-segment paths starting with /book/, /js/, /fonts/, /foliate-js/, /bgimg/
      //    contain slashes in token segment and must return `null` so BookPlayerServer handlers can handle them.
      expect(
        manager.handleRequest(shelf.Request('GET', Uri.parse('http://127.0.0.1/book/sample.epub'))),
        isNull,
        reason: '/book/... must not be intercepted by TempFileManager',
      );
      expect(
        manager.handleRequest(shelf.Request('GET', Uri.parse('http://127.0.0.1/js/reader.js'))),
        isNull,
        reason: '/js/... must not be intercepted by TempFileManager',
      );
      expect(
        manager.handleRequest(shelf.Request('GET', Uri.parse('http://127.0.0.1/fonts/noto.ttf'))),
        isNull,
        reason: '/fonts/... must not be intercepted by TempFileManager',
      );
      expect(
        manager.handleRequest(shelf.Request('GET', Uri.parse('http://127.0.0.1/foliate-js/index.html'))),
        isNull,
        reason: '/foliate-js/... must not be intercepted by TempFileManager',
      );
      expect(
        manager.handleRequest(shelf.Request('GET', Uri.parse('http://127.0.0.1/bgimg/cover.jpg'))),
        isNull,
        reason: '/bgimg/... must not be intercepted by TempFileManager',
      );
      expect(
        manager.handleRequest(shelf.Request('GET', Uri.parse('http://127.0.0.1/'))),
        isNull,
        reason: 'Root / must return null and fall through',
      );

      // 2. Unmapped single-segment tokens return 404:
      //    Temp files are served at the root as `/$serverFileName`. If a client makes a single-segment request
      //    for an unknown, released, or expired token, returning 404 ('Temp file not found') is intentional
      //    and avoids leaking unintended data or falling through to generic handlers.
      final resUnmapped = manager.handleRequest(
        shelf.Request('GET', Uri.parse('http://127.0.0.1/unmapped_token.epub')),
      );
      expect(resUnmapped, isNotNull);
      expect(resUnmapped!.statusCode, equals(404));
    });

    test('real HTTP shelf server concurrent verification over loopback',
        () async {
      final tokenA = manager.setTempFile(fileA);
      final tokenB = manager.setTempFile(fileB);

      // Mount manager handler on real shelf server
      shelf.Response appHandler(shelf.Request req) {
        final res = manager.handleRequest(req);
        if (res != null) return res;
        return shelf.Response.notFound('Not found');
      }

      final server = await io.serve(appHandler, '127.0.0.1', 0);
      final client = HttpClient();

      try {
        final uriA = Uri.parse('http://127.0.0.1:${server.port}/$tokenA');
        final uriB = Uri.parse('http://127.0.0.1:${server.port}/$tokenB');
        final uriUnknown =
            Uri.parse('http://127.0.0.1:${server.port}/unknown_token.epub');

        // Fire both concurrently
        final futureA = client.getUrl(uriA).then((req) => req.close());
        final futureB = client.getUrl(uriB).then((req) => req.close());

        final httpResA = await futureA;
        final httpResB = await futureB;

        expect(httpResA.statusCode, equals(200));
        expect(httpResB.statusCode, equals(200));

        final bodyA = await utf8.decodeStream(httpResA);
        final bodyB = await utf8.decodeStream(httpResB);

        expect(bodyA, equals('EPUB_CONTENT_OF_BOOK_A'));
        expect(bodyB, equals('EPUB_CONTENT_OF_BOOK_B'));
        expect(bodyA, isNot(equals(bodyB)));

        // Release A
        manager.releaseTempFile(tokenA);

        final httpResA2 = await (await client.getUrl(uriA)).close();
        final httpResB2 = await (await client.getUrl(uriB)).close();

        expect(httpResA2.statusCode, equals(404));
        expect(httpResB2.statusCode, equals(200));
        expect(await utf8.decodeStream(httpResB2),
            equals('EPUB_CONTENT_OF_BOOK_B'));

        // Unknown token returns 404
        final httpResUnknown = await (await client.getUrl(uriUnknown)).close();
        expect(httpResUnknown.statusCode, equals(404));
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    });

    test('releasing token does not delete underlying user file on disk', () {
      final tokenA = manager.setTempFile(fileA);
      expect(fileA.existsSync(), isTrue);

      manager.releaseTempFile(tokenA);
      expect(manager.has(tokenA), isFalse);
      expect(fileA.existsSync(), isTrue,
          reason: 'User file must not be deleted when releasing token');
    });

    test('Server.stop() clears temp manager even when server is not started', () async {
      final server = Server();
      server.setTempFile(fileA);
      expect(server.tempFileCount, greaterThan(0));

      // Server is not running (_server == null), but stop() must clear manager unconditionally
      await server.stop();
      expect(server.tempFileCount, equals(0));
    });
  });
}
