import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/theme/anx_ui_tokens.dart';
import 'package:flutter/material.dart';

class HintBanner extends StatefulWidget {
  const HintBanner({
    super.key,
    required this.child,
    this.icon,
    this.hintKey,
    this.onClose,
    this.margin,
    this.padding,
  });

  final Widget child;
  final Widget? icon;
  final HintKey? hintKey;
  final VoidCallback? onClose;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  @override
  State<HintBanner> createState() => _HintBannerState();
}

class _HintBannerState extends State<HintBanner>
    with SingleTickerProviderStateMixin {
  late bool _visible;

  @override
  void initState() {
    super.initState();
    _visible =
        widget.hintKey == null ? true : Prefs().shouldShowHint(widget.hintKey!);
  }

  void _handleClose() {
    if (!_visible) return;

    widget.onClose?.call();

    if (widget.hintKey != null) {
      Prefs().setShowHint(widget.hintKey!, false);
    }

    AnxToast.show(L10n.of(context).hintBannerRestoreToast);

    setState(() {
      _visible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final backgroundColor = scheme.primaryContainer.withValues(alpha: 0.62);

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: _visible
          ? FilledContainer(
              radius: AnxUiTokens.controlRadius,
              margin: widget.margin,
              padding: widget.padding ??
                  const EdgeInsets.fromLTRB(12, 12, 32, 12),
              color: backgroundColor,
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.zero,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (widget.icon != null) ...[
                          IconTheme(
                            data: IconTheme.of(context).copyWith(
                              color: scheme.onPrimaryContainer,
                            ),
                            child: widget.icon!,
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(child: widget.child),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      onPressed: _handleClose,
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: scheme.onPrimaryContainer,
                      ),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 32, height: 32),
                      splashRadius: 18,
                      tooltip: L10n.of(context).close,
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
