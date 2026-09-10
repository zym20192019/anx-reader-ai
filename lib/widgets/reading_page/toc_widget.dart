import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/theme/anx_ui_tokens.dart';
import 'package:anx_reader/widgets/reading_page/widgets/book_toc.dart';
import 'package:anx_reader/widgets/reading_page/widgets/bookmark.dart';
import 'package:flutter/material.dart';

class TocWidget extends StatefulWidget {
  const TocWidget({
    super.key,
    required this.epubPlayerKey,
    required this.hideAppBarAndBottomBar,
    required this.closeDrawer,
  });

  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final Function hideAppBarAndBottomBar;
  final VoidCallback closeDrawer;

  @override
  State<TocWidget> createState() => _TocWidgetState();
}

class _TocWidgetState extends State<TocWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(color: AnxUiTokens.quietBorder(scheme)),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorSize: TabBarIndicatorSize.tab,
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            tabs: [
              Tab(text: L10n.of(context).readingContents),
              Tab(text: L10n.of(context).readingBookmark),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: TabBarView(
              controller: _tabController,
              children: [
                buildBookToc(),
                buildBookmarkList(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildBookmarkList() {
    return BookmarkWidget(
      epubPlayerKey: widget.epubPlayerKey,
      onNavigate: () {
        widget.hideAppBarAndBottomBar(false);
        widget.closeDrawer();
      },
    );
  }

  BookToc buildBookToc() {
    return BookToc(
      epubPlayerKey: widget.epubPlayerKey,
      hideAppBarAndBottomBar: widget.hideAppBarAndBottomBar,
      closeDrawer: widget.closeDrawer,
    );
  }
}
