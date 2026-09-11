import 'dart:async';
import 'dart:io';

import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/theme.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/current_reading_state.dart';
import 'package:anx_reader/page/home_page.dart';
import 'package:anx_reader/page/iap_page.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/providers/chapter_content_bridge.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/providers/iap.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/toc_search.dart';
import 'package:anx_reader/service/convert_to_epub/txt/convert_from_txt.dart';
import 'package:anx_reader/service/md5_service.dart';
import 'package:anx_reader/service/prepare_imported_file.dart';
import 'package:anx_reader/utils/webView/anx_headless_webview.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/utils/import_book.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/webView/gererate_url.dart';
import 'package:anx_reader/utils/webView/webview_console_message.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import 'book_player/book_player_server.dart';

final allowBookExtensions = ["epub", "mobi", "azw3", "fb2", "txt", "pdf"];

/// Import files with explicit ownership for app-created temporary copies.
void importBookList(
  List<File> fileList,
  BuildContext context,
  WidgetRef ref, {
  Set<String> ownedInputPaths = const <String>{},
}) {
  AnxLog.info('importBook fileList: ${fileList.toString()}');

  List<File> supportedFiles = fileList.where((file) {
    return allowBookExtensions
        .contains(file.path.split('.').last.toLowerCase());
  }).toList();

  List<File> unsupportedFiles = fileList.where((file) {
    return !allowBookExtensions
        .contains(file.path.split('.').last.toLowerCase());
  }).toList();

  _checkDuplicatesAndShowDialog(
    supportedFiles,
    unsupportedFiles,
    fileList,
    context,
    ref,
    ownedInputPaths,
  );
}

void _checkDuplicatesAndShowDialog(
    List<File> supportedFiles,
    List<File> unsupportedFiles,
    List<File> fileList,
    BuildContext context,
    WidgetRef ref,
    Set<String> ownedInputPaths) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(L10n.of(context).md5Calculating),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(L10n.of(context).md5Calculating),
        ],
      ),
    ),
  );

  try {
    final filePaths = supportedFiles.map((f) => f.path).toList();
    final checkResults = await MD5Service.checkImportFiles(filePaths);

    Navigator.of(context).pop();

    List<File> duplicateFiles = [];
    List<File> uniqueFiles = [];
    Map<String, Book> duplicateInfo = {};

    for (int i = 0; i < supportedFiles.length; i++) {
      final file = supportedFiles[i];
      final result = checkResults[i];

      if (result.isDuplicate && result.duplicateBook != null) {
        duplicateFiles.add(file);
        duplicateInfo[file.path] = result.duplicateBook!;
      } else {
        uniqueFiles.add(file);
      }
    }

    _showImportDialog(
      uniqueFiles,
      duplicateFiles,
      duplicateInfo,
      unsupportedFiles,
      fileList,
      ref,
      ownedInputPaths,
    );
  } catch (e) {
    Navigator.of(navigatorKey.currentContext!).pop();
    AnxLog.severe('MD5 check failed: $e');
    _showImportDialog(
      supportedFiles,
      [],
      {},
      unsupportedFiles,
      fileList,
      ref,
      ownedInputPaths,
    );
  }
}

void _showImportDialog(
  List<File> uniqueFiles,
  List<File> duplicateFiles,
  Map<String, Book> duplicateInfo,
  List<File> unsupportedFiles,
  List<File> fileList,
  WidgetRef ref,
  Set<String> ownedInputPaths,
) {
  // Keep selected TXT sources intact; only discard temporary unsupported copies.
  for (var file in unsupportedFiles) {
    if (shouldDeleteImportedInput(
      file,
      ownsFile: ownedInputPaths.contains(file.path),
    )) {
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  BuildContext context = navigatorKey.currentContext!;

  Widget bookItem(
    String filePath,
    Widget icon, {
    bool isDuplicate = false,
    String? duplicateTitle,
    String? errorMessage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: icon,
            ),
            Expanded(
              child: Text(
                path.basename(filePath),
                style: TextStyle(
                  fontWeight: FontWeight.w300,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (errorMessage != null)
              IconButton(
                icon: const Icon(Icons.info_outline, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(L10n.of(context).commonError),
                      content: SelectableText(errorMessage),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(L10n.of(context).commonOk),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
        if (isDuplicate && duplicateTitle != null)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 2),
            child: Text(
              L10n.of(context).duplicateOf(duplicateTitle),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ),
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 2),
            child: Text(
              'Error: ${errorMessage.length > 50 ? "${errorMessage.substring(0, 50)}..." : errorMessage}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.red,
              ),
            ),
          ),
      ],
    );
  }

  final supportedFiles = [...uniqueFiles, ...duplicateFiles];
  bool skipDuplicates = true;

  showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        String currentHandlingFile = '';
        List<String> errorFiles = [];
        bool finished = false;
        Map<String, String> errorMessages = {};

        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text(L10n.of(context).importNBooksSelected(fileList.length)),
            contentPadding: const EdgeInsets.all(16),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L10n.of(context)
                      .importSupportTypes(allowBookExtensions.join(' / '))),

                  const SizedBox(height: 10),

                  // show unique files
                  for (var file in uniqueFiles)
                    file.path == currentHandlingFile
                        ? bookItem(
                            file.path,
                            Container(
                              padding: const EdgeInsets.all(3),
                              width: 20,
                              height: 20,
                              child: const CircularProgressIndicator(),
                            ))
                        : bookItem(
                            file.path,
                            errorFiles.contains(file.path)
                                ? const Icon(Icons.error)
                                : const Icon(Icons.done),
                            errorMessage: errorFiles.contains(file.path)
                                ? errorMessages[file.path]
                                : null,
                          ),

                  // show unsupported files
                  if (unsupportedFiles.isNotEmpty) ...[
                    Divider(),
                    SizedBox(height: 10),
                    Text(L10n.of(context)
                        .importNBooksNotSupport(unsupportedFiles.length))
                  ],
                  for (var file in unsupportedFiles)
                    bookItem(file.path, const Icon(Icons.error)),

                  // show duplicate files
                  if (duplicateFiles.isNotEmpty) ...[
                    Divider(),
                    const SizedBox(height: 10),
                    Text(L10n.of(context).duplicateFile),
                  ],
                  for (var file in duplicateFiles)
                    if (skipDuplicates)
                      bookItem(
                        file.path,
                        const Icon(Icons.double_arrow_rounded),
                        isDuplicate: true,
                        duplicateTitle: duplicateInfo[file.path]?.title,
                      )
                    else
                      file.path == currentHandlingFile
                          ? bookItem(
                              file.path,
                              Container(
                                padding: const EdgeInsets.all(3),
                                width: 20,
                                height: 20,
                                child: const CircularProgressIndicator(),
                              ),
                              isDuplicate: true,
                              duplicateTitle: duplicateInfo[file.path]?.title,
                            )
                          : bookItem(
                              file.path,
                              errorFiles.contains(file.path)
                                  ? const Icon(Icons.error)
                                  : const Icon(Icons.done),
                              isDuplicate: true,
                              duplicateTitle: duplicateInfo[file.path]?.title,
                              errorMessage: errorFiles.contains(file.path)
                                  ? errorMessages[file.path]
                                  : null,
                            ),

                  // select skip duplicates
                  if (duplicateFiles.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Checkbox(
                          value: skipDuplicates,
                          onChanged: (value) {
                            setState(() {
                              skipDuplicates = value ?? true;
                            });
                          },
                        ),
                        Expanded(
                          child: Text(L10n.of(context).skipDuplicateFiles),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  for (var file in supportedFiles) {
                    if (shouldDeleteImportedInput(
                      file,
                      ownsFile: ownedInputPaths.contains(file.path),
                    )) {
                      if (file.existsSync()) {
                        file.deleteSync();
                      }
                    }
                  }
                },
                child: Text(L10n.of(context).commonCancel),
              ),
              if (uniqueFiles.isNotEmpty ||
                  (duplicateFiles.isNotEmpty && !skipDuplicates))
                TextButton(
                    onPressed: () async {
                      if (finished) {
                        Navigator.of(context).pop('dialog');
                        return;
                      }

                      List<File> filesToImport = [...uniqueFiles];
                      if (!skipDuplicates) {
                        filesToImport.addAll(duplicateFiles);
                      }

                      for (var file in filesToImport) {
                        AnxToast.show(path.basename(file.path));
                        setState(() {
                          currentHandlingFile = file.path;
                        });
                        try {
                          await importBook(
                            file,
                            ref,
                            ownsInput: ownedInputPaths.contains(file.path),
                          );
                          setState(() {
                            currentHandlingFile = '';
                          });
                        } catch (e, stackTrace) {
                          AnxLog.severe('Failed to import ${file.path}: $e');
                          AnxLog.severe('Stack trace: $stackTrace');
                          setState(() {
                            errorFiles.add(file.path);
                            errorMessages[file.path] = e.toString();
                          });
                        }
                      }

                      // duplicateFiles will be deleted if skipDuplicates is true
                      // if skipDuplicates is false, they will be imported
                      if (skipDuplicates) {
                        for (var file in duplicateFiles) {
                          if (shouldDeleteImportedInput(
                            file,
                            ownsFile: ownedInputPaths.contains(file.path),
                          )) {
                            if (file.existsSync()) {
                              file.deleteSync();
                            }
                          }
                        }
                      }

                      setState(() {
                        finished = true;
                      });
                      ref.read(syncProvider.notifier).syncData(
                          SyncDirection.upload, ref,
                          trigger: SyncTrigger.auto);
                    },
                    child: Text(finished
                        ? L10n.of(context).commonOk
                        : L10n.of(context).importImportNBooks(
                            uniqueFiles.length +
                                (skipDuplicates ? 0 : duplicateFiles.length) -
                                errorFiles.length))),
            ],
          );
        });
      });
}

Future<void> importBook(
  File file,
  WidgetRef ref, {
  bool ownsInput = false,
}) async {
  final sourceFile = file;
  File? preparedFile;
  try {
    final sourceMd5 = await MD5Service.calculateFileMd5(sourceFile.path);
    preparedFile = await prepareImportedFile(
      sourceFile,
      convertTxt: convertFromTxt,
    );
    final String? fileMd5;
    if (preparedFile.path == sourceFile.path) {
      fileMd5 = sourceMd5;
    } else {
      fileMd5 = await MD5Service.calculateFileMd5(preparedFile.path);
    }
    await getBookMetadata(
      preparedFile,
      md5: fileMd5,
      fileMd5: fileMd5,
      sourceMd5: sourceMd5,
      ref: ref,
    );
    ref.read(bookListProvider.notifier).refresh();
  } finally {
    if (preparedFile != null &&
        preparedFile.path != sourceFile.path &&
        await preparedFile.exists()) {
      await preparedFile.delete();
    }
    if (shouldDeleteImportedInput(sourceFile, ownsFile: ownsInput) &&
        await sourceFile.exists()) {
      await sourceFile.delete();
    }
  }
}

Future<void> pushToReadingPage(
  WidgetRef ref,
  BuildContext context,
  Book book, {
  String? cfi,
  String? heroTag,
}) async {
  if (book.isDeleted) {
    AnxToast.show(L10n.of(context).bookDeleted);
    return;
  }

  if (!File(book.fileFullPath).existsSync()) {
    ref.read(syncProvider.notifier).downloadBook(book);
    return;
  }

  if (EnvVar.enableInAppPurchase) {
    final iapAsync = ref.read(iapProvider);
    final isFeatureAvailable = iapAsync.maybeWhen(
      data: (state) => state.isFeatureAvailable,
      orElse: () => ref.read(iapProvider.notifier).cachedFeatureAvailable(),
    );

    if (!isFeatureAvailable) {
      Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (context) => const IAPPage(),
        ),
      );
      return;
    }
  }
  ref.read(aiChatProvider.notifier).clear();
  final initialThemes = await themeDao.selectThemes();
  ref.read(currentReadingProvider.notifier).start(
        CurrentReadingState(
          book: book,
          cfi: cfi,
        ),
      );

  final currentReading = ref.read(currentReadingProvider.notifier);
  final chapterContentBridge = ref.read(chapterContentBridgeProvider.notifier);
  final tocSearch = ref.read(tocSearchProvider.notifier);

  await Navigator.push(
    navigatorKey.currentContext!,
    CupertinoPageRoute(
      builder: (c) => ReadingPage(
        key: readingPageKey,
        book: book,
        cfi: cfi,
        initialThemes: initialThemes,
        heroTag: heroTag,
      ),
    ),
  ).then((_) {
    AnxLog.info('ReadingPage: poped: ${book.title}');
    currentReading.finish();
    chapterContentBridge.state = null;
    tocSearch.clear();
    AnxLog.info('Pop successfully ReadingPage: ${book.title}');
  });
}

void updateBookRating(Book book, double rating) {
  book.rating = rating;
  bookDao.updateBook(book);
}

Future<void> resetBookCover(Book book) async {
  final file = File(book.fileFullPath);
  await getBookMetadata(
    file,
    book: book,
    md5: book.fileMd5 ?? book.md5,
    fileMd5: book.fileMd5 ?? book.md5,
    sourceMd5: book.sourceMd5,
  );
}

class BookMd5Resolution {
  final String? fileMd5;
  final String? sourceMd5;

  const BookMd5Resolution({
    this.fileMd5,
    this.sourceMd5,
  });
}

BookMd5Resolution resolveBookMd5OnSave({
  required bool isExistingBook,
  String? effectiveFileMd5,
  String? effectiveSourceMd5,
  Book? provideBook,
}) {
  if (isExistingBook && provideBook != null) {
    // When saving an existing book without overwriting the actual book library file,
    // do NOT overwrite fileMd5 with the temporary prepared file's MD5.
    final fileMd5 = provideBook.fileMd5;

    // sourceMd5: if effectiveSourceMd5 is provided, retain existing sourceMd5
    // or update if provideBook.sourceMd5 was null/empty.
    final String? sourceMd5;
    if (effectiveSourceMd5 != null && effectiveSourceMd5.isNotEmpty) {
      sourceMd5 = (provideBook.sourceMd5 != null &&
              provideBook.sourceMd5!.isNotEmpty)
          ? provideBook.sourceMd5
          : effectiveSourceMd5;
    } else {
      sourceMd5 = provideBook.sourceMd5;
    }
    return BookMd5Resolution(fileMd5: fileMd5, sourceMd5: sourceMd5);
  } else {
    // New book import: use prepared fileMd5 and sourceMd5
    return BookMd5Resolution(
      fileMd5: effectiveFileMd5,
      sourceMd5: effectiveSourceMd5,
    );
  }
}

BookMd5Resolution resolveBookMd5OnReplace({
  required bool isTxt,
  required String? newSourceFileMd5,
  required String? newProcessedFileMd5,
}) {
  if (isTxt) {
    return BookMd5Resolution(
      fileMd5: newProcessedFileMd5,
      sourceMd5: newSourceFileMd5,
    );
  } else {
    // For non-TXT replacements, the new file is the source itself.
    // Ensure old source hash is never retained.
    final hash = newProcessedFileMd5 ?? newSourceFileMd5;
    return BookMd5Resolution(
      fileMd5: hash,
      sourceMd5: hash,
    );
  }
}

Future<void> saveBook(
  File file,
  String title,
  String author,
  String description,
  String? md5,
  String cover, {
  String? fileMd5,
  String? sourceMd5,
  Book? provideBook,
}) async {
  final effectiveFileMd5 = fileMd5 ?? md5;
  final effectiveSourceMd5 = sourceMd5 ?? md5;

  // Extract original filename (without extension)
  final fileNameWithoutExt = path.basenameWithoutExtension(file.path);

  // Use original filename if title is invalid
  final effectiveTitle =
      (title == 'Unknown' || title.trim().isEmpty) ? fileNameWithoutExt : title;

  final newBookName =
      '${effectiveTitle.length > 20 ? effectiveTitle.substring(0, 20) : effectiveTitle}-${DateTime.now().millisecondsSinceEpoch}'
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
          .replaceAll('\n', '')
          .replaceAll('\r', '')
          .trim();

  final extension = file.path.split('.').last;

  if (provideBook == null && effectiveSourceMd5 != null) {
    provideBook = await bookDao.getBookBySourceMd5(effectiveSourceMd5);
    if (provideBook == null) {
      provideBook = await bookDao.getLegacyBookByFileMd5(effectiveSourceMd5);
    }
  }

  final bool isExistingBook = provideBook != null;
  final String dbFilePath;
  if (isExistingBook) {
    dbFilePath = provideBook.filePath;
  } else {
    dbFilePath = 'file/$newBookName.$extension';
    final filePath = getBasePath(dbFilePath);
    await file.copy(filePath);
  }

  String? dbCoverPath = 'cover/$newBookName';
  dbCoverPath = await saveImageToLocal(cover, dbCoverPath);

  final md5Resolution = resolveBookMd5OnSave(
    isExistingBook: isExistingBook,
    effectiveFileMd5: effectiveFileMd5,
    effectiveSourceMd5: effectiveSourceMd5,
    provideBook: provideBook,
  );

  Book book = Book(
      id: provideBook != null ? provideBook.id : -1,
      title: provideBook?.title ?? effectiveTitle,
      coverPath: dbCoverPath,
      filePath: provideBook?.filePath ?? dbFilePath,
      lastReadPosition: provideBook?.lastReadPosition ?? '',
      readingPercentage: provideBook?.readingPercentage ?? 0,
      author: provideBook?.author ?? author,
      description:
          description.isNotEmpty ? description : provideBook?.description,
      isDeleted: false,
      rating: provideBook?.rating ?? 0.0,
      groupId: provideBook?.groupId ?? 0,
      fileMd5: md5Resolution.fileMd5,
      sourceMd5: md5Resolution.sourceMd5,
      createTime: provideBook?.createTime ?? DateTime.now(),
      updateTime: DateTime.now());

  book.id = await bookDao.insertBook(book);
  if (navigatorKey.currentContext != null) {
    AnxToast.show(L10n.of(navigatorKey.currentContext!).serviceImportSuccess);
  }
}

Future<void> getBookMetadata(
  File file, {
  Book? book,
  String? md5,
  String? fileMd5,
  String? sourceMd5,
  WidgetRef? ref,
}) async {
  final String serverFileName = Server().setTempFile(file);

  try {
    String cfi = '';

    String bookUrl = "http://127.0.0.1:${Server().port}/$serverFileName";
    AnxLog.info("import start: book url: $bookUrl");

    final effectiveFileMd5 = fileMd5 ?? md5;
    final effectiveSourceMd5 = sourceMd5 ?? md5;

    final completer = Completer<void>();
    bool isHandlingMetadata = false;
    Future<void>? saveFuture;

    late final AnxHeadlessWebView webview;
    webview = AnxHeadlessWebView(
    webViewEnvironment: webViewEnvironment,
    initialUrlRequest: URLRequest(
        url: WebUri(generateUrl(
      bookUrl,
      cfi,
      importing: true,
    ))),
    onLoadStop: (controller, url) async {
      controller.addJavaScriptHandler(
          handlerName: 'onMetadata',
          callback: (args) async {
            if (isHandlingMetadata) {
              return;
            }
            isHandlingMetadata = true;

            saveFuture = () async {
              try {
                Map<String, dynamic> metadata =
                    args.isNotEmpty && args[0] is Map
                        ? (args[0] is Map<String, dynamic>
                            ? args[0] as Map<String, dynamic>
                            : Map<String, dynamic>.from(args[0] as Map))
                        : <String, dynamic>{};
                String title = metadata['title']?.toString() ?? 'Unknown';
                dynamic authorData = metadata['author'];
                String author = authorData is String
                    ? authorData
                    : authorData is Iterable
                        ? authorData
                            .map((author) => author is String
                                ? author
                                : (author is Map
                                        ? author['name']?.toString()
                                        : null) ??
                                    'Unknown')
                            .join(', ')
                        : 'Unknown';

                // base64 cover
                String cover = metadata['cover']?.toString() ?? '';
                String description = metadata['description']?.toString() ?? '';
                await saveBook(
                  file,
                  title,
                  author,
                  description,
                  effectiveFileMd5,
                  cover,
                  fileMd5: effectiveFileMd5,
                  sourceMd5: effectiveSourceMd5,
                  provideBook: book,
                );
                ref?.read(bookListProvider.notifier).refresh();
                if (!completer.isCompleted) {
                  completer.complete();
                }
              } catch (e, stackTrace) {
                AnxLog.severe('Error in onMetadata handler: $e\n$stackTrace');
                if (!completer.isCompleted) {
                  completer.completeError(e, stackTrace);
                }
                rethrow;
              }
            }();
            await saveFuture;
          });
    },
    onConsoleMessage: (controller, consoleMessage) {
      if (consoleMessage.messageLevel == ConsoleMessageLevel.ERROR) {
        if (!isHandlingMetadata && !completer.isCompleted) {
          completer.completeError(
            Exception('Webview: ${consoleMessage.message}'),
          );
        }
      }
      webviewConsoleMessage(controller, consoleMessage);
    },
    onLoadError: (controller, url, code, message) {
      if (!isHandlingMetadata && !completer.isCompleted) {
        completer.completeError(
          Exception('Webview load error: $message ($code)'),
        );
      }
    },
    onLoadHttpError: (controller, url, statusCode, description) {
      if (!isHandlingMetadata && !completer.isCompleted) {
        completer.completeError(
          Exception('Webview HTTP error: $description ($statusCode)'),
        );
      }
    },
  );

    try {
      await webview.run();
      try {
        await completer.future.timeout(const Duration(seconds: 30));
      } on TimeoutException {
        if (saveFuture != null) {
          await saveFuture;
        } else {
          throw Exception('Import: Get book metadata timeout');
        }
      }
    } finally {
      if (saveFuture != null) {
        try {
          await saveFuture;
        } catch (_) {
          // Any error was already reported through completer.
        }
      }
      await webview.dispose();
    }
  } finally {
    Server().releaseTempFile(serverFileName);
  }
}
