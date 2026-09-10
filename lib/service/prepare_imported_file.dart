import 'dart:io';

import 'package:path/path.dart' as path;

typedef TxtImportConverter = Future<File> Function(File source);

bool isTxtSource(File file) =>
    path.extension(file.path).toLowerCase() == '.txt';

bool shouldDeleteImportedInput(File file) => !isTxtSource(file);

/// Prepares an imported file without deleting the caller's source file.
///
/// TXT conversion returns a temporary EPUB. The caller owns cleanup of that
/// generated artifact; the original TXT remains available for reprocessing.
Future<File> prepareImportedFile(
  File source, {
  required TxtImportConverter convertTxt,
}) {
  if (path.extension(source.path).toLowerCase() == '.txt') {
    return convertTxt(source);
  }
  return Future<File>.value(source);
}
