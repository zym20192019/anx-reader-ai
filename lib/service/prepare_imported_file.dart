import 'dart:io';

import 'package:path/path.dart' as path;

typedef TxtImportConverter = Future<File> Function(File source);

bool isTxtSource(File file) =>
    path.extension(file.path).toLowerCase() == '.txt';

/// Returns whether the caller explicitly owns this input and may delete it.
///
/// File extensions do not convey ownership: a shared EPUB is still user data,
/// while an app-created temporary copy may be safely removed.
bool shouldDeleteImportedInput(
  File file, {
  bool ownsFile = false,
}) {
  return ownsFile && file.path.isNotEmpty;
}

/// Prepares an imported file without deleting the caller's source file.
///
/// TXT conversion returns a temporary EPUB. The importer owns cleanup of that
/// generated artifact; the original TXT remains available for reprocessing.
Future<File> prepareImportedFile(
  File source, {
  required TxtImportConverter convertTxt,
}) {
  if (isTxtSource(source)) {
    return convertTxt(source);
  }
  return Future<File>.value(source);
}
