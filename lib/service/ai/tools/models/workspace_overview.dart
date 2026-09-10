/// Bounded input for the read-only workspace overview tool.
const _defaultLimit = 10;

class WorkspaceOverviewInput {
  WorkspaceOverviewInput({
    int recentBookLimit = _defaultLimit,
    int recentReadingLimit = _defaultLimit,
    int recentNoteLimit = _defaultLimit,
  })  : recentBookLimit = _normalizeLimit(recentBookLimit),
        recentReadingLimit = _normalizeLimit(recentReadingLimit),
        recentNoteLimit = _normalizeLimit(recentNoteLimit);

  factory WorkspaceOverviewInput.fromJson(Map<String, dynamic> json) {
    return WorkspaceOverviewInput(
      recentBookLimit: _readLimit(
        json['recent_book_limit'] ?? json['recentBookLimit'],
        _defaultLimit,
      ),
      recentReadingLimit: _readLimit(
        json['recent_reading_limit'] ?? json['recentReadingLimit'],
        _defaultLimit,
      ),
      recentNoteLimit: _readLimit(
        json['recent_note_limit'] ?? json['recentNoteLimit'],
        _defaultLimit,
      ),
    );
  }

  final int recentBookLimit;
  final int recentReadingLimit;
  final int recentNoteLimit;

  Map<String, dynamic> toJson() {
    return {
      'recentBookLimit': recentBookLimit,
      'recentReadingLimit': recentReadingLimit,
      'recentNoteLimit': recentNoteLimit,
    };
  }

  static int _readLimit(Object? value, int fallback) {
    return value is int ? value : fallback;
  }

  static int _normalizeLimit(int value) => value.clamp(1, 50).toInt();
}
