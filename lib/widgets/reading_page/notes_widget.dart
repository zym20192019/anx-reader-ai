import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/anx_ui_tokens.dart';
import 'package:anx_reader/widgets/book_notes/book_notes_list.dart';
import 'package:anx_reader/widgets/reading_page/widget_title.dart';
import 'package:flutter/material.dart';

import 'package:anx_reader/models/book.dart';

class ReadingNotes extends StatelessWidget {
  const ReadingNotes({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.58,
      ),
      decoration: BoxDecoration(
        color: AnxUiTokens.raisedSurface(scheme),
        borderRadius: BorderRadius.circular(AnxUiTokens.surfaceRadius),
        border: Border.all(color: AnxUiTokens.quietBorder(scheme)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widgetTitle(L10n.of(context).navBarNotes, null),
          Expanded(
            child:
                ListView(children: [BookNotesList(book: book, reading: true)]),
          ),
        ],
      ),
    );
  }
}
