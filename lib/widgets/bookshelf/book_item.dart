import 'dart:ui';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/book_sync_status.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/theme/anx_ui_tokens.dart';
import 'package:anx_reader/widgets/bookshelf/book_bottom_sheet.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/bookshelf/book_sync_status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookItem extends ConsumerWidget {
  const BookItem({
    super.key,
    required this.book,
  });

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> handleLongPress(BuildContext context) async {
      showModalBottomSheet(
          context: context,
          builder: (BuildContext context) {
            return BookBottomSheet(book: book);
          });
    }

    BookSyncStatusEnum bookSyncStatus =
        ref.watch(syncStatusProvider).whenOrNull(data: (data) {
              if (data.downloading.contains(book.id)) {
                return BookSyncStatusEnum.downloading;
              } else if (data.uploading.contains(book.id)) {
                return BookSyncStatusEnum.uploading;
              } else if (data.localOnly.contains(book.id)) {
                return BookSyncStatusEnum.localOnly;
              } else if (data.remoteOnly.contains(book.id)) {
                return BookSyncStatusEnum.remoteOnly;
              } else if (data.both.contains(book.id)) {
                return BookSyncStatusEnum.both;
              } else if (data.nonExistent.contains(book.id)) {
                return BookSyncStatusEnum.nonExistent;
              } else {
                return BookSyncStatusEnum.checking;
              }
            }) ??
            BookSyncStatusEnum.checking;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final coverRadius = BorderRadius.circular(AnxUiTokens.controlRadius);

    return GestureDetector(
      onTap: () {
        pushToReadingPage(ref, context, book);
      },
      onLongPress: () {
        handleLongPress(context);
      },
      onSecondaryTap: () {
        handleLongPress(context);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Hero(
              tag: book.coverFullPath,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: coverRadius,
                  border: Border.all(
                    color: AnxUiTokens.quietBorder(scheme),
                    width: 0.7,
                  ),
                  boxShadow: [
                    if (!Prefs().eInkMode)
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: coverRadius,
                  child: Row(
                    children: [
                      Expanded(
                        child: BookCover(book: book),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                      ),
                      if (Prefs().webdavStatus)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 4),
                          child: SizedBox(
                            height: 20,
                            width: 20,
                            child: BookSyncStatusIcon(
                              syncStatus: bookSyncStatus,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          book.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AnxUiTokens.quietText(scheme),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${(book.readingPercentage * 100).toStringAsFixed(0)}%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AnxUiTokens.quietText(scheme),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AnxUiTokens.pillRadius),
                    child: LinearProgressIndicator(
                      value: book.readingPercentage.clamp(0.0, 1.0).toDouble(),
                      minHeight: 3,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
