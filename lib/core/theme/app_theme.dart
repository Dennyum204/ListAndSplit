import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';

abstract final class AppTheme {
  static final ThemeData light = _theme(Brightness.light);
  static final ThemeData dark = _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final background = isDark ? AppPalette.dark : AppPalette.cream;
    final foreground = isDark ? AppPalette.lightText : AppPalette.navy;
    final card = isDark ? AppPalette.darkCard : AppPalette.cardBlue;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppPalette.navy,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? AppPalette.orange : AppPalette.navy,
      onPrimary: isDark ? AppPalette.navy : AppPalette.lightText,
      primaryContainer: AppPalette.orange,
      onPrimaryContainer: AppPalette.navy,
      secondary: AppPalette.orange,
      onSecondary: AppPalette.navy,
      secondaryContainer: isDark ? AppPalette.darkCard : AppPalette.inputCream,
      onSecondaryContainer: foreground,
      surface: background,
      onSurface: foreground,
      onSurfaceVariant:
          isDark ? const Color(0xFFD2D2D2) : const Color(0xFF435665),
      outline: isDark ? const Color(0xFFAAAAAA) : const Color(0xFF657786),
      outlineVariant:
          isDark ? const Color(0xFF5B5B5B) : const Color(0xFFC2CDD4),
      error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFB3261E),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppPalette.orange, width: 1.5),
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        titleLarge:
            base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium:
            base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        headlineMedium: base.textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        centerTitle: false,
        backgroundColor: isDark ? AppPalette.darkCard : AppPalette.navy,
        foregroundColor: AppPalette.lightText,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: AppPalette.lightText,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: AppPalette.inputCream,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: AppPalette.navy, width: 2)),
        errorBorder: border.copyWith(
            borderSide: BorderSide(color: colorScheme.error, width: 2)),
        focusedErrorBorder: border.copyWith(
            borderSide: BorderSide(color: colorScheme.error, width: 2)),
        disabledBorder:
            border.copyWith(borderSide: BorderSide(color: colorScheme.outline)),
        labelStyle: const TextStyle(color: AppPalette.navy),
        floatingLabelStyle:
            TextStyle(color: foreground, backgroundColor: background),
        hintStyle: const TextStyle(color: Color(0xFF5C6470)),
        prefixIconColor: AppPalette.navy,
        suffixIconColor: AppPalette.navy,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        backgroundColor: AppPalette.orange,
        foregroundColor: AppPalette.navy,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: base.textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side:
            BorderSide(color: isDark ? colorScheme.outline : AppPalette.orange),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      )),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      )),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        backgroundColor: isDark ? AppPalette.lightText : AppPalette.navy,
        foregroundColor: isDark ? AppPalette.ink : AppPalette.lightText,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: base.textTheme.titleLarge
            ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppPalette.orange,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: card,
        selectedColor: isDark ? AppPalette.orange : AppPalette.navy,
        labelStyle: base.textTheme.labelLarge?.copyWith(color: foreground),
        secondaryLabelStyle: base.textTheme.labelLarge?.copyWith(
          color: isDark ? AppPalette.navy : AppPalette.lightText,
        ),
        checkmarkColor: isDark ? AppPalette.navy : AppPalette.lightText,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: card,
          selectedForegroundColor:
              isDark ? AppPalette.navy : AppPalette.lightText,
          selectedBackgroundColor: isDark ? AppPalette.orange : AppPalette.navy,
          minimumSize: const Size(48, 48),
          side: BorderSide.none,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
        color: colorScheme.primary,
        linearTrackColor: isDark ? AppPalette.lightText : AppPalette.cream,
      ),
      dividerTheme: base.dividerTheme
          .copyWith(color: colorScheme.outlineVariant, space: 24),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: isDark ? AppPalette.darkCard : AppPalette.cream,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppPalette.navy,
        selectionColor: Color(0x73F4AE45),
        selectionHandleColor: AppPalette.navy,
      ),
    );
  }
}
