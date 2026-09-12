class BookSourceFormat {
  static const String txt = 'txt';
  static const String epub = 'epub';
  static const String pdf = 'pdf';
  static const String mobi = 'mobi';
  static const String azw3 = 'azw3';
  static const String fb2 = 'fb2';
  static const String comicZip = 'cbz';

  static const Set<String> supportedFormats = {
    txt,
    epub,
    pdf,
    mobi,
    azw3,
    fb2,
    comicZip,
  };

  /// Normalizes a format string by trimming whitespace, stripping any leading dot,
  /// and converting characters to lowercase. Returns empty string if format is null.
  static String normalize(String? format) {
    if (format == null) return '';
    var cleaned = format.trim();
    if (cleaned.startsWith('.')) {
      cleaned = cleaned.substring(1).trim();
    }
    return cleaned.toLowerCase();
  }

  /// Case-insensitive check if [format] represents a TXT format.
  static bool isTxt(String? format) {
    return normalize(format) == txt;
  }
}

/// Standalone helper for case-insensitive TXT format check.
bool isTxtSourceFormat(String? format) => BookSourceFormat.isTxt(format);

/// Pure data contract representing a book's source file and format information.
class BookSource {
  final String filePath;
  final String format;
  final String? sourceMd5;
  final int? length;
  final String? encoding;

  const BookSource({
    required this.filePath,
    required this.format,
    this.sourceMd5,
    this.length,
    this.encoding,
  });

  /// Creates a [BookSource] by inferring format from [filePath] unless explicitly provided.
  factory BookSource.fromFilePath(
    String filePath, {
    String? format,
    String? sourceMd5,
    int? length,
    String? encoding,
  }) {
    String detectedFormat = format ?? '';
    if (detectedFormat.isEmpty && filePath.contains('.')) {
      detectedFormat = filePath.split('.').last;
    }
    return BookSource(
      filePath: filePath,
      format: detectedFormat,
      sourceMd5: sourceMd5,
      length: length,
      encoding: encoding,
    );
  }

  /// Whether this source format is TXT (case-insensitive).
  bool get isTxt => isTxtSourceFormat(format);

  /// Lowercase, dot-free format string.
  String get normalizedFormat => BookSourceFormat.normalize(format);

  Map<String, dynamic> toMap() {
    return {
      'filePath': filePath,
      'format': format,
      if (sourceMd5 != null) 'sourceMd5': sourceMd5,
      if (length != null) 'length': length,
      if (encoding != null) 'encoding': encoding,
    };
  }

  factory BookSource.fromMap(Map<String, dynamic> map) {
    return BookSource(
      filePath: map['filePath'] as String? ?? '',
      format: map['format'] as String? ?? '',
      sourceMd5: map['sourceMd5'] as String?,
      length: map['length'] as int?,
      encoding: map['encoding'] as String?,
    );
  }

  BookSource copyWith({
    String? filePath,
    String? format,
    String? sourceMd5,
    int? length,
    String? encoding,
  }) {
    return BookSource(
      filePath: filePath ?? this.filePath,
      format: format ?? this.format,
      sourceMd5: sourceMd5 ?? this.sourceMd5,
      length: length ?? this.length,
      encoding: encoding ?? this.encoding,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookSource &&
          runtimeType == other.runtimeType &&
          filePath == other.filePath &&
          normalizedFormat == other.normalizedFormat &&
          sourceMd5 == other.sourceMd5 &&
          length == other.length &&
          encoding == other.encoding;

  @override
  int get hashCode => Object.hash(
        filePath,
        normalizedFormat,
        sourceMd5,
        length,
        encoding,
      );

  @override
  String toString() {
    return 'BookSource(filePath: $filePath, format: $format, sourceMd5: $sourceMd5, length: $length, encoding: $encoding)';
  }
}
