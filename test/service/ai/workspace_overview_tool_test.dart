import 'dart:async';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/reading_time.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/ai/tools/models/workspace_overview.dart';
import 'package:anx_reader/service/ai/tools/repository/books_repository.dart';
import 'package:anx_reader/service/ai/tools/repository/notes_repository.dart';
import 'package:anx_reader/service/ai/tools/repository/reading_history_repository.dart';
import 'package:anx_reader/service/ai/tools/workspace_overview_tool.dart';
import 'package:test/test.dart';

void main() {
  test('parses snake_case limits and exposes a bounded input schema', () {
    final tool = WorkspaceOverviewTool(
      _BooksRepositoryFake(const [], _Probe()),
      _ReadingHistoryRepositoryFake(const [], _Probe()),
      _NotesRepositoryFake(const [], _Probe()),
    );

    final input = tool.parseInput({
      'recent_book_limit': 75,
      'recent_reading_limit': 0,
      'recent_note_limit': 4,
    });
    final properties = tool.inputJsonSchema['properties']! as Map;

    expect(input.recentBookLimit, 50);
    expect(input.recentReadingLimit, 1);
    expect(input.recentNoteLimit, 4);
    expect(properties.keys, containsAll([
      'recent_book_limit',
      'recent_reading_limit',
      'recent_note_limit',
    ]));
    expect(properties.keys, isNot(contains('recentBookLimit')));
  });

  test('registers the workspace overview definition', () {
    expect(AiToolRegistry.byId('workspace_overview'), isNotNull);
    expect(
      AiToolRegistry.defaultEnabledToolIds(),
      contains('workspace_overview'),
    );
  });

  test('keeps workspace overview metadata localized through the registry', () {
    final definition = AiToolRegistry.byId('workspace_overview');

    expect(definition, isNotNull);
    expect(definition!.displayNameBuilder, isA<Function>());
    expect(definition.descriptionBuilder, isA<Function>());
  });

  test(
      'aggregates bounded repository results concurrently with read-only metadata',
      () async {
    final probe = _Probe();
    final book = Book.mock();
    final note = BookNote(
      bookId: book.id,
      content: 'A saved highlight',
      cfi: 'epubcfi(/6/2)',
      chapter: 'Chapter 1',
      type: 'highlight',
      color: 'yellow',
      updateTime: DateTime(2026, 9, 9),
    );
    final reading = ReadingTime(
      bookId: book.id,
      date: '2026-09-09',
      readingTime: 60,
    );
    final booksRepository = _BooksRepositoryFake(
      [BookSearchResult(book)],
      probe,
    );
    final readingRepository = _ReadingHistoryRepositoryFake(
      [ReadingHistoryRecord(book: book, entry: reading)],
      probe,
    );
    final notesRepository = _NotesRepositoryFake(
      [NoteSearchResult(book: book, note: note)],
      probe,
    );
    final tool = WorkspaceOverviewTool(
      booksRepository,
      readingRepository,
      notesRepository,
    );

    final resultFuture = tool.run(
      WorkspaceOverviewInput(
        recentBookLimit: 75,
        recentReadingLimit: 0,
        recentNoteLimit: 3,
      ),
    );
    await probe.allStarted.future;

    expect(probe.started.toSet(), {'books', 'reading', 'notes'});
    expect(booksRepository.receivedLimit, 50);
    expect(readingRepository.receivedLimit, 1);
    expect(notesRepository.receivedLimit, 3);

    probe.release.complete();
    final result = await resultFuture;

    expect(result['scope'], 'read_only');
    expect(result['limits'], {
      'recentBookLimit': 50,
      'recentReadingLimit': 1,
      'recentNoteLimit': 3,
    });
    expect(result['counts'], {
      'recentBooks': 1,
      'recentReading': 1,
      'recentNotes': 1,
    });
    expect(result['recentBooks'], [BookSearchResult(book).toMap()]);
    expect(result['recentReading'], [
      ReadingHistoryRecord(book: book, entry: reading).toMap(),
    ]);
    expect(result['recentNotes'], [
      NoteSearchResult(book: book, note: note).toMap(),
    ]);
  });
}

class _Probe {
  final started = <String>[];
  final release = Completer<void>();
  final allStarted = Completer<void>();

  void start(String repository) {
    started.add(repository);
    if (started.length == 3) {
      allStarted.complete();
    }
  }
}

class _BooksRepositoryFake extends BooksRepository {
  _BooksRepositoryFake(this.results, this.probe);

  final List<BookSearchResult> results;
  final _Probe probe;
  int? receivedLimit;

  @override
  Future<List<BookSearchResult>> searchBooks({
    String? keyword,
    int? groupId,
    bool includeDeleted = false,
    int limit = 10,
  }) async {
    receivedLimit = limit;
    probe.start('books');
    await probe.release.future;
    return results;
  }
}

class _ReadingHistoryRepositoryFake extends ReadingHistoryRepository {
  _ReadingHistoryRepositoryFake(this.results, this.probe);

  final List<ReadingHistoryRecord> results;
  final _Probe probe;
  int? receivedLimit;

  @override
  Future<List<ReadingHistoryRecord>> fetchHistory({
    int? bookId,
    DateTime? from,
    DateTime? to,
    int limit = 20,
  }) async {
    receivedLimit = limit;
    probe.start('reading');
    await probe.release.future;
    return results;
  }
}

class _NotesRepositoryFake extends NotesRepository {
  _NotesRepositoryFake(this.results, this.probe);

  final List<NoteSearchResult> results;
  final _Probe probe;
  int? receivedLimit;

  @override
  Future<List<NoteSearchResult>> searchNotes({
    String? keyword,
    int? bookId,
    DateTime? from,
    DateTime? to,
    int limit = 10,
  }) async {
    receivedLimit = limit;
    probe.start('notes');
    await probe.release.future;
    return results;
  }
}
