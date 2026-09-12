import 'dart:io';
import 'dart:math';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_source.dart';
import 'package:anx_reader/page/book_detail.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/service/convert_to_epub/txt/convert_from_txt.dart';
import 'package:anx_reader/service/md5_service.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/txt_cache/txt_cache_key.dart';
import 'package:anx_reader/service/txt_cache/txt_cache_manager.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/share_file.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/delete_confirm.dart';
import 'package:anx_reader/widgets/icon_and_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:path/path.dart' as p;

class BookBottomSheet extends ConsumerWidget {
  const BookBottomSheet({
    super.key,
    required this.book,
  });

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> handleDelete(BuildContext context) async {
      Navigator.pop(context);
      await bookDao.updateBook(book.copyWith(
        isDeleted: true,
        updateTime: DateTime.now(),
      ));
      ref.read(bookListProvider.notifier).refresh();
      final sourceFile = File(book.fileFullPath);
      if (await sourceFile.exists()) {
        await sourceFile.delete();
      }
      final coverFile = File(book.coverFullPath);
      if (await coverFile.exists()) {
        await coverFile.delete();
      }

      if (isTxtSourceFormat(book.sourceFormat) &&
          isSafeCachePathToDelete(
            book.cacheFilePath,
            resolvedSyncPath: book.sourceFilePath ?? book.filePath,
            filePath: book.filePath,
          )) {
        try {
          final cacheFile =
              await TxtCacheManager.resolveBookCacheFile(book.cacheFilePath);
          if (cacheFile != null && await cacheFile.parent.exists()) {
            await cacheFile.parent.delete(recursive: true);
          }
        } on ArgumentError catch (_) {
          // Invalid cache metadata must not prevent book deletion.
        }
      }
    }

    void handleDetail(BuildContext context) {
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BookDetail(book: book),
        ),
      );
    }

    void handleUpload(BuildContext context) {
      Future<void> core() async {
        await ref.read(syncProvider.notifier).releaseBook(book);
        ref.read(syncStatusProvider.notifier).refresh();
      }

      if (Prefs().shouldShowHint(HintKey.releaseLocalSpace)) {
        SmartDialog.show(
          builder: (context) => AlertDialog(
            title: Text(L10n.of(context).bookSyncStatusReleaseSpaceDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(L10n.of(context).bookSyncStatusReleaseSpaceDialogContent),
                Row(
                  children: [
                    StatefulBuilder(builder: (context, setState) {
                      return Checkbox(
                          value: !Prefs()
                              .shouldShowHint(HintKey.releaseLocalSpace),
                          onChanged: (value) {
                            value = !(value ?? false);
                            Prefs()
                                .setShowHint(HintKey.releaseLocalSpace, value);
                            setState(() {});
                          });
                    }),
                    Text(L10n.of(context).bookSyncStatusDoNotShowAgain),
                  ],
                )
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  SmartDialog.dismiss();
                },
                child: Text(L10n.of(context).commonCancel),
              ),
              TextButton(
                onPressed: () {
                  SmartDialog.dismiss();
                  core();
                },
                child: Text(L10n.of(context).commonConfirm),
              ),
            ],
          ),
        );
      } else {
        ref.read(syncProvider.notifier).releaseBook(book);
      }
    }

    Future<void> handleShare() async {
      await shareFile(
        title: '${book.title}.${book.filePath.split('.').last}',
        filePath: book.fileFullPath,
      );
    }

    String formatSize(int bytes) {
      if (bytes <= 0) return '0 B';
      const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
      var i = (log(bytes) / log(1024)).floor();
      return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
    }

    Future<void> handleReplace(BuildContext context) async {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null) return;
      PlatformFile newFile = result.files.first;
      String extension =
          p.extension(newFile.name).replaceAll('.', '').toLowerCase();
      if (!allowBookExtensions.contains(extension)) {
        AnxToast.show(
            L10n.of(context).bookBottomSheetUnsupportedFileFormat(extension));
        return;
      }

      File newFileObj = File(newFile.path!);

      if (!context.mounted) return;

      int newSize = await newFileObj.length();
      int oldSize = 0;
      if (await File(book.fileFullPath).exists()) {
        oldSize = await File(book.fileFullPath).length();
      }

      bool? confirm = await SmartDialog.show(
        builder: (context) => AlertDialog(
          title: Text(L10n.of(context).commonAttention),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.of(context)
                  .bookBottomSheetOriginalFileSize(formatSize(oldSize))),
              Text(L10n.of(context)
                  .bookBottomSheetNewFileSize(formatSize(newSize))),
              const SizedBox(height: 10),
              Text(
                L10n.of(context).bookBottomSheetReplaceWarning,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                SmartDialog.dismiss(result: false);
              },
              child: Text(L10n.of(context).commonCancel),
            ),
            TextButton(
              onPressed: () {
                SmartDialog.dismiss(result: true);
              },
              child: Text(L10n.of(context).commonConfirm),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      try {
        final rawExtension = p.extension(newFile.name).toLowerCase();
        final isTxt = isTxtSourceFormat(rawExtension) || rawExtension == '.txt';
        final newSourceMd5 = await MD5Service.calculateFileMd5(newFileObj.path);

        final String newRelativePath;
        final String newDestPath;
        final BookMd5Resolution md5Resolution;
        String? cacheRelativePath;
        String? cacheFingerprint;
        int? sourceTextLength;

        if (isTxt) {
          final activeRule = Prefs().activeChapterSplitRule;
          cacheFingerprint = generateTxtCacheFingerprint(
            sourceMd5: newSourceMd5,
            rule: activeRule,
            parserVersion: kTxtParserVersion,
          );
          final cacheManager = await TxtCacheManager.create();
          if (cacheFingerprint != null && cacheFingerprint.isNotEmpty) {
            await cacheManager.ensureCache(
              source: newFileObj,
              fingerprint: cacheFingerprint,
              converter: convertFromTxt,
            );
            cacheRelativePath =
                cacheManager.relativeCachePathFor(cacheFingerprint);
          }
          try {
            sourceTextLength = getNormalizedTxtLength(newFileObj);
          } catch (_) {}

          newRelativePath = resolveReplaceFilePath(
            existingFilePath: book.filePath,
            isTxt: true,
            title: book.title,
            extension: '.txt',
          );
          newDestPath = getBasePath(newRelativePath);

          // Copy raw TXT as formal file
          await newFileObj.copy(newDestPath);

          md5Resolution = resolveBookMd5OnReplace(
            isTxt: true,
            newSourceFileMd5: newSourceMd5,
            newProcessedFileMd5: newSourceMd5,
          );

          final updatedBook = book.copyWith(
            filePath: newRelativePath,
            sourceFilePath: newRelativePath,
            sourceFormat: 'txt',
            cacheFilePath: cacheRelativePath,
            cacheFingerprint: cacheFingerprint,
            sourceTextLength: sourceTextLength,
            sourceTextOffset: 0,
            fileMd5: md5Resolution.fileMd5,
            sourceMd5: md5Resolution.sourceMd5,
            updateTime: DateTime.now(),
          );
          updatedBook.sourceMd5 = md5Resolution.sourceMd5;
          await bookDao.updateBook(updatedBook);
        } else {
          File fileToProcess = newFileObj;
          String extension = p.extension(newFile.name);

          newRelativePath = resolveReplaceFilePath(
            existingFilePath: book.filePath,
            isTxt: false,
            title: book.title,
            extension: extension,
          );
          newDestPath = getBasePath(newRelativePath);

          // Copy new file
          await fileToProcess.copy(newDestPath);

          // Calculate MD5 of destination file
          String? newFileMd5 = await MD5Service.calculateFileMd5(newDestPath);

          md5Resolution = resolveBookMd5OnReplace(
            isTxt: false,
            newSourceFileMd5: newSourceMd5,
            newProcessedFileMd5: newFileMd5,
          );

          final normalizedExt = BookSourceFormat.normalize(extension);
          final updatedBook = book.copyWith(
            filePath: newRelativePath,
            sourceFilePath: newRelativePath,
            sourceFormat: normalizedExt.isNotEmpty ? normalizedExt : null,
            fileMd5: md5Resolution.fileMd5,
            sourceMd5: md5Resolution.sourceMd5,
            updateTime: DateTime.now(),
          );
          // copyWith uses null as "keep existing" for compatibility. Explicitly
          // clear TXT-only cache metadata when the replacement is non-TXT.
          updatedBook.cacheFilePath = null;
          updatedBook.cacheFingerprint = null;
          updatedBook.sourceTextOffset = null;
          updatedBook.sourceTextLength = null;
          updatedBook.positionContext = null;
          updatedBook.sourceMd5 = md5Resolution.sourceMd5;
          await bookDao.updateBook(updatedBook);
        }

        // Delete old file if path is different
        if (book.fileFullPath != newDestPath) {
          final oldFile = File(book.fileFullPath);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        }

        ref.read(bookListProvider.notifier).refresh();
        if (context.mounted) Navigator.pop(context);

        if (Prefs().webdavStatus) {
          ref.read(syncProvider.notifier).syncData(SyncDirection.upload, ref);
        }
      } catch (e) {
        AnxToast.show(
            L10n.of(context).bookBottomSheetReplaceFailed(e.toString()));
      }
    }

    final actions = [
      {
        "icon": EvaIcons.share,
        "text": L10n.of(context).shareFile,
        "onTap": () => handleShare()
      },
      {
        "icon": EvaIcons.refresh,
        "text": L10n.of(context).bookBottomSheetReplaceFile,
        "onTap": () => handleReplace(context)
      },
      {
        "icon": EvaIcons.cloud_upload,
        "text": L10n.of(context).bookSyncStatusReleaseSpace,
        "onTap": () => handleUpload(context)
      },
      {
        "icon": EvaIcons.more_vertical,
        "text": L10n.of(context).notesPageDetail,
        "onTap": () => handleDetail(context)
      },
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      height: 100,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BookCover(book: book, width: 40),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Text(book.title,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          DeleteConfirm(
            delete: () {
              handleDelete(context);
            },
            deleteIcon: IconAndText(
              icon: const Icon(EvaIcons.trash),
              text: L10n.of(context).commonDelete,
            ),
            confirmIcon: IconAndText(
              icon: const Icon(
                EvaIcons.checkmark_circle_2,
                color: Colors.red,
              ),
              text: L10n.of(context).commonConfirm,
            ),
          ),
          PopupMenuButton(
              itemBuilder: (context) {
                return actions.map((action) {
                  return PopupMenuItem(
                      onTap: () {
                        (action["onTap"] as Function())();
                      },
                      child: Row(
                        children: [
                          Icon(action["icon"] as IconData),
                          const SizedBox(width: 8),
                          Text(action["text"] as String),
                        ],
                      ));
                }).toList();
              },
              child: IconAndText(
                icon: const Icon(EvaIcons.more_vertical),
                text: L10n.of(context).more,
              ))
        ],
      ),
    );
  }
}
