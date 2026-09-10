import 'dart:async';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/ai/tools/models/workspace_overview.dart';
import 'package:anx_reader/service/ai/tools/repository/books_repository.dart';
import 'package:anx_reader/service/ai/tools/repository/notes_repository.dart';
import 'package:anx_reader/service/ai/tools/repository/reading_history_repository.dart';

import 'base_tool.dart';

const _workspaceOverviewToolId = 'workspace_overview';

class WorkspaceOverviewTool
    extends RepositoryTool<WorkspaceOverviewInput, Map<String, dynamic>> {
  WorkspaceOverviewTool(
    this._booksRepository,
    this._readingHistoryRepository,
    this._notesRepository,
  ) : super(
          name: _workspaceOverviewToolId,
          description:
              'Read-only aggregate overview of the user workspace. Returns bounded recent books, reading history, and notes from local repositories without changing any data.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'recent_book_limit': {
                'type': 'integer',
                'description':
                    'Optional. Maximum number of recent books to return (range 1-50; default 10).',
              },
              'recent_reading_limit': {
                'type': 'integer',
                'description':
                    'Optional. Maximum number of recent reading records to return (range 1-50; default 10).',
              },
              'recent_note_limit': {
                'type': 'integer',
                'description':
                    'Optional. Maximum number of recent notes to return (range 1-50; default 10).',
              },
            },
          },
          timeout: const Duration(seconds: 8),
        );

  final BooksRepository _booksRepository;
  final ReadingHistoryRepository _readingHistoryRepository;
  final NotesRepository _notesRepository;

  @override
  WorkspaceOverviewInput parseInput(Map<String, dynamic> json) {
    return WorkspaceOverviewInput.fromJson(json);
  }

  @override
  Future<Map<String, dynamic>> run(WorkspaceOverviewInput input) async {
    final results = await Future.wait<dynamic>([
      _booksRepository.searchBooks(
        keyword: null,
        includeDeleted: false,
        limit: input.recentBookLimit,
      ),
      _readingHistoryRepository.fetchHistory(
        limit: input.recentReadingLimit,
      ),
      _notesRepository.searchNotes(
        keyword: null,
        limit: input.recentNoteLimit,
      ),
    ]);

    final recentBooks = (results[0] as List<BookSearchResult>)
        .map((entry) => entry.toMap())
        .toList(growable: false);
    final recentReading = (results[1] as List<ReadingHistoryRecord>)
        .map((entry) => entry.toMap())
        .toList(growable: false);
    final recentNotes = (results[2] as List<NoteSearchResult>)
        .map((entry) => entry.toMap())
        .toList(growable: false);

    return {
      'scope': 'read_only',
      'limits': input.toJson(),
      'counts': {
        'recentBooks': recentBooks.length,
        'recentReading': recentReading.length,
        'recentNotes': recentNotes.length,
      },
      'recentBooks': recentBooks,
      'recentReading': recentReading,
      'recentNotes': recentNotes,
    };
  }

  @override
  bool shouldLogError(Object error) {
    return error is! TimeoutException;
  }
}

final AiToolDefinition workspaceOverviewToolDefinition = AiToolDefinition(
  id: _workspaceOverviewToolId,
  displayNameBuilder: (L10n l10n) => l10n.aiToolWorkspaceOverviewName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolWorkspaceOverviewDescription,
  build: (context) => WorkspaceOverviewTool(
    context.booksRepository,
    context.readingHistoryRepository,
    context.notesRepository,
  ).tool,
);
