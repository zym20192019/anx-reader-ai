import 'package:anx_reader/theme/anx_ui_tokens.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';

abstract class AbstractSettingsSection extends StatelessWidget {
  const AbstractSettingsSection({super.key});
}

class SettingsSection extends AbstractSettingsSection {
  const SettingsSection({
    super.key,
    required this.tiles,
    this.margin,
    this.title,
  });

  final List<AbstractSettingsTile> tiles;
  final EdgeInsetsDirectional? margin;
  final Widget? title;

  @override
  Widget build(BuildContext context) {
    return buildSectionBody(context);
  }

  Widget buildSectionBody(BuildContext context) {
    final tileList = buildTileList();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (title == null) {
      return tileList;
    }

    return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(
          top: 12,
          bottom: 8,
          start: 20,
          end: 20,
        ),
        child: DefaultTextStyle(
          style: (theme.textTheme.labelLarge ??
                  theme.textTheme.bodyMedium ??
                  const TextStyle())
              .copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
          child: title!,
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: FilledContainer(
          radius: AnxUiTokens.surfaceRadius,
          padding: EdgeInsetsGeometry.zero,
          child: tileList,
        ),
      ),
    ],
  );
  }

  Widget buildTileList() {
    return Column(
      children: tiles,
    );
  }
}

class CustomSettingsSection extends AbstractSettingsSection {
  const CustomSettingsSection({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
