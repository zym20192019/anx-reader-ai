import 'package:anx_reader/service/book_filename_allocator.dart';
import 'package:test/test.dart';

void main() {
  group('sanitizeFilenameBase', () {
    test('removes Windows illegal characters <>:"/\\|?*', () {
      expect(
        sanitizeFilenameBase('My<Book>: "Epic" / Journey\\ | Part? *'),
        equals('MyBook Epic Journey Part'),
      );
    });

    test('removes newlines, carriage returns, and control characters', () {
      expect(
        sanitizeFilenameBase("Title\nWith\r\nLines\tTab"),
        equals('TitleWith Lines Tab'),
      );
    });

    test('trims leading and trailing whitespace and trailing dots/spaces', () {
      expect(
        sanitizeFilenameBase('   My Book...   '),
        equals('My Book'),
      );
    });

    test('falls back to default fallback for empty, whitespace-only, or all-illegal input', () {
      expect(sanitizeFilenameBase(''), equals(kDefaultFallbackTitle));
      expect(sanitizeFilenameBase('   '), equals(kDefaultFallbackTitle));
      expect(sanitizeFilenameBase('***:::???'), equals(kDefaultFallbackTitle));
    });

    test('falls back to default fallback for "Unknown" case-insensitively', () {
      expect(sanitizeFilenameBase('Unknown'), equals(kDefaultFallbackTitle));
      expect(sanitizeFilenameBase('unknown'), equals(kDefaultFallbackTitle));
      expect(sanitizeFilenameBase('  UNKNOWN  '), equals(kDefaultFallbackTitle));
    });

    test('supports custom fallback string', () {
      expect(sanitizeFilenameBase('', fallback: 'CustomBook'), equals('CustomBook'));
      expect(sanitizeFilenameBase('Unknown', fallback: 'CustomBook'), equals('CustomBook'));
    });
  });

  group('allocateBookFilename', () {
    test('allocates clean title directly when no conflict exists', () {
      final allocated = allocateBookFilename(
        title: '三国演义',
        extension: 'txt',
        existingPaths: [],
      );
      expect(allocated, equals('三国演义.txt'));
    });

    test('handles leading dot in extension and normalizes extension case', () {
      final allocated = allocateBookFilename(
        title: 'Simple',
        extension: '.TXT',
        existingPaths: [],
      );
      expect(allocated, equals('Simple.txt'));
    });

    test('conflict resolution allocates (1), (2) incrementally', () {
      final allocated1 = allocateBookFilename(
        title: '三体',
        extension: 'txt',
        existingPaths: ['三体.txt'],
      );
      expect(allocated1, equals('三体 (1).txt'));

      final allocated2 = allocateBookFilename(
        title: '三体',
        extension: 'txt',
        existingPaths: ['三体.txt', '三体 (1).txt'],
      );
      expect(allocated2, equals('三体 (2).txt'));
    });

    test('detects conflicts against full paths and relative paths', () {
      final allocated = allocateBookFilename(
        title: '三体',
        extension: 'txt',
        existingPaths: [
          'file/三体.txt',
          'C:\\Users\\reader\\books\\三体 (1).txt',
        ],
      );
      expect(allocated, equals('三体 (2).txt'));
    });

    test('conflict detection is case-insensitive for both filename and extension', () {
      final allocated = allocateBookFilename(
        title: 'Book',
        extension: 'txt',
        existingPaths: ['book.TXT', 'BOOK (1).txt'],
      );
      expect(allocated, equals('Book (2).txt'));
    });

    test('cleans illegal characters and falls back on Unknown or empty', () {
      final allocatedUnknown = allocateBookFilename(
        title: 'Unknown',
        extension: 'txt',
        existingPaths: [],
      );
      expect(allocatedUnknown, equals('book.txt'));

      final allocatedIllegal = allocateBookFilename(
        title: '   <Illegal>?*   ',
        extension: 'epub',
        existingPaths: [],
      );
      expect(allocatedIllegal, equals('Illegal.epub'));

      final allocatedAllIllegal = allocateBookFilename(
        title: '<>?*',
        extension: 'txt',
        existingPaths: ['book.txt'],
      );
      expect(allocatedAllIllegal, equals('book (1).txt'));
    });

    test('respects maxBaseNameLength and does not truncate extension or collision suffix', () {
      const longTitle = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789';
      final allocated0 = allocateBookFilename(
        title: longTitle,
        extension: 'txt',
        existingPaths: [],
        maxBaseNameLength: 20,
      );
      expect(allocated0, equals('abcdefghijklmnopqrstu.txt'.substring(0, 20) + '.txt'));
      expect(allocated0.length, equals(20 + 4));

      final allocated1 = allocateBookFilename(
        title: longTitle,
        extension: 'txt',
        existingPaths: [allocated0],
        maxBaseNameLength: 20,
      );
      // Suffix is ' (1)' which has length 4, so base is truncated to 20 - 4 = 16
      expect(allocated1, equals('${longTitle.substring(0, 16)} (1).txt'));
      expect(allocated1.endsWith('.txt'), isTrue);

      final allocated2 = allocateBookFilename(
        title: longTitle,
        extension: 'txt',
        existingPaths: [allocated0, allocated1],
        maxBaseNameLength: 20,
      );
      expect(allocated2, equals('${longTitle.substring(0, 16)} (2).txt'));
    });

    test('handles extension without dot and empty extension', () {
      final allocatedNoExt = allocateBookFilename(
        title: 'NoExtension',
        extension: '',
        existingPaths: ['NoExtension'],
      );
      expect(allocatedNoExt, equals('NoExtension (1)'));
    });

    test('does not produce timestamp or uuid anywhere in output', () {
      final allocated = allocateBookFilename(
        title: 'Normal Title',
        extension: 'txt',
        existingPaths: ['Normal Title.txt'],
      );
      expect(allocated, equals('Normal Title (1).txt'));
      expect(allocated.contains('-'), isFalse);
    });

    test('BookFilenameAllocator class API operates identically to top-level helper', () {
      const allocator = BookFilenameAllocator(defaultMaxBaseNameLength: 25);
      final allocated = allocator.allocate(
        title: 'Clean Architecture',
        extension: 'epub',
        existingPaths: ['file/Clean Architecture.epub'],
      );
      expect(allocated, equals('Clean Architecture (1).epub'));
    });
  });
}
