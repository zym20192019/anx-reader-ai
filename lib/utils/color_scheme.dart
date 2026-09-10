import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/theme/anx_ui_tokens.dart';
import 'package:chinese_font_library/chinese_font_library.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

ThemeData colorSchema(
  Prefs prefsNotifier,
  BuildContext context,
  Brightness brightness,
) {
  brightness = prefsNotifier.eInkMode
      ? Brightness.light
      : switch (prefsNotifier.themeMode) {
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
          ThemeMode.system => MediaQuery.platformBrightnessOf(context),
        };
  Color seedColor = prefsNotifier.themeColor;
  final isDark = brightness == Brightness.dark;
  final isEinkMode = prefsNotifier.eInkMode;

  final lightGropedBackground = const Color(0xFFF2F2F7);
  final darkGropedBackground =
      prefsNotifier.trueDarkMode ? Color(0xFF000000) : Color(0xFF1C1C1E);
  final gropedBackgroundColor = isEinkMode
      ? Colors.white
      : isDark
          ? darkGropedBackground
          : lightGropedBackground;

  final colorScheme = isEinkMode
      ? const ColorScheme.light(
          primary: Colors.black,
          onPrimary: Colors.white,
          primaryContainer: Colors.grey,
          onPrimaryContainer: Colors.black,
          secondary: Colors.grey,
          onSecondary: Colors.white,
          secondaryContainer: Colors.black12,
          onSecondaryContainer: Colors.black,
          surface: Colors.white,
          onSurface: Colors.black,
        )
      : switch (brightness) {
          Brightness.light => ColorScheme.fromSeed(
              seedColor: seedColor,
              brightness: Brightness.light,
              surfaceContainer: Color(0xFFFFFFFF),
              surface: lightGropedBackground,
            ),
          Brightness.dark => ColorScheme.fromSeed(
              seedColor: seedColor,
              brightness: Brightness.dark,
              surfaceContainer: Color(0xFF2C2C2E),
              surface: darkGropedBackground,
            ),
        };

  ThemeData themeData = isEinkMode
      ? FlexThemeData.light(
          useMaterial3: true,
          swapLegacyOnMaterial3: true,
          colorScheme: colorScheme)
      : switch (brightness) {
          Brightness.light => FlexThemeData.light(
              useMaterial3: true,
              swapLegacyOnMaterial3: true,
              colorScheme: colorScheme,
            ),
          Brightness.dark => FlexThemeData.dark(
              useMaterial3: true,
              swapLegacyOnMaterial3: true,
              darkIsTrueBlack: prefsNotifier.trueDarkMode,
              colorScheme: colorScheme,
            )
        };

  final themedData = themeData.copyWith(
    scaffoldBackgroundColor: gropedBackgroundColor,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 20,
    ),
    cardTheme: CardThemeData(
      color: AnxUiTokens.raisedSurface(colorScheme),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(AnxUiTokens.surfaceRadius),
        side: BorderSide(
          color: AnxUiTokens.quietBorder(colorScheme),
          width: 0.6,
        ),
      ),
    ),
    chipTheme: ChipThemeData.fromDefaults(
      brightness: brightness,
      secondaryColor: colorScheme.primary,
      labelStyle: themeData.textTheme.labelMedium ?? const TextStyle(),
    ).copyWith(
      backgroundColor: colorScheme.surfaceContainer,
      selectedColor: colorScheme.primaryContainer,
      secondarySelectedColor: colorScheme.secondaryContainer,
      side: BorderSide(color: AnxUiTokens.quietBorder(colorScheme)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AnxUiTokens.pillRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      elevation: 0,
      pressElevation: 0,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      horizontalTitleGap: 12,
      minVerticalPadding: 8,
      iconColor: colorScheme.onSurfaceVariant,
      textColor: colorScheme.onSurface,
      selectedColor: colorScheme.primary,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AnxUiTokens.controlRadius),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      useIndicator: true,
      indicatorColor: colorScheme.secondaryContainer,
      minWidth: 72,
      selectedIconTheme: IconThemeData(color: colorScheme.onSecondaryContainer),
      unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      selectedItemColor: colorScheme.primary,
      unselectedItemColor: colorScheme.onSurfaceVariant,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
      type: BottomNavigationBarType.fixed,
    ),
    sliderTheme: const SliderThemeData(year2023: false),
    progressIndicatorTheme: const ProgressIndicatorThemeData(year2023: false),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AnxUiTokens.controlRadius),
        borderSide: BorderSide(color: AnxUiTokens.quietBorder(colorScheme)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AnxUiTokens.controlRadius),
        borderSide: BorderSide(color: AnxUiTokens.quietBorder(colorScheme)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AnxUiTokens.controlRadius),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AnxUiTokens.raisedSurface(colorScheme),
      elevation: 4,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(AnxUiTokens.controlRadius),
        side: BorderSide(color: AnxUiTokens.quietBorder(colorScheme)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: AnxUiTokens.quietBorder(colorScheme),
      thickness: 0.6,
      space: 1,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: gropedBackgroundColor,
      modalBackgroundColor: gropedBackgroundColor,
      showDragHandle: true,
      dragHandleColor: colorScheme.outlineVariant,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: gropedBackgroundColor,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: gropedBackgroundColor,
      elevation: 6,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(AnxUiTokens.surfaceRadius),
        side: BorderSide(color: AnxUiTokens.quietBorder(colorScheme)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    ),
  );

  return themedData.useSystemChineseFont(brightness);
}
