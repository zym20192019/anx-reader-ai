import 'package:anx_reader/service/ai/tools/models/workspace_overview.dart';
import 'package:test/test.dart';

void main() {
  group('WorkspaceOverviewInput', () {
    test('uses default limits and serializes normalized values', () {
      final input = WorkspaceOverviewInput();

      expect(input.recentBookLimit, 10);
      expect(input.recentReadingLimit, 10);
      expect(input.recentNoteLimit, 10);
      expect(input.toJson(), {
        'recentBookLimit': 10,
        'recentReadingLimit': 10,
        'recentNoteLimit': 10,
      });
    });

    test('clamps every limit to the inclusive range 1 through 50', () {
      final input = WorkspaceOverviewInput(
        recentBookLimit: 0,
        recentReadingLimit: -4,
        recentNoteLimit: 51,
      );

      expect(input.recentBookLimit, 1);
      expect(input.recentReadingLimit, 1);
      expect(input.recentNoteLimit, 50);
      expect(
        WorkspaceOverviewInput(
          recentBookLimit: 50,
          recentReadingLimit: 1,
          recentNoteLimit: 50,
        ).toJson(),
        {
          'recentBookLimit': 50,
          'recentReadingLimit': 1,
          'recentNoteLimit': 50,
        },
      );
    });

    test('normalizes values when created from JSON', () {
      final input = WorkspaceOverviewInput.fromJson({
        'recentBookLimit': 75,
        'recentReadingLimit': 0,
      });

      expect(input.recentBookLimit, 50);
      expect(input.recentReadingLimit, 1);
      expect(input.recentNoteLimit, 10);
      expect(input.toJson(), {
        'recentBookLimit': 50,
        'recentReadingLimit': 1,
        'recentNoteLimit': 10,
      });
    });

    test('accepts snake_case JSON while preserving camelCase compatibility', () {
      final input = WorkspaceOverviewInput.fromJson({
        'recent_book_limit': 75,
        'recent_reading_limit': 0,
        'recent_note_limit': 4,
      });

      expect(input.toJson(), {
        'recentBookLimit': 50,
        'recentReadingLimit': 1,
        'recentNoteLimit': 4,
      });
    });

    test('falls back to defaults for non-int JSON limits', () {
      final input = WorkspaceOverviewInput.fromJson({
        'recentBookLimit': '25',
        'recentReadingLimit': 12.5,
        'recentNoteLimit': null,
      });

      expect(input.toJson(), {
        'recentBookLimit': 10,
        'recentReadingLimit': 10,
        'recentNoteLimit': 10,
      });
    });
  });
}
