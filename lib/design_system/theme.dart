import 'package:flutter/material.dart';

/// The TorrentLens theme: a hand-tuned Material 3 scheme on the original teal
/// identity, IBM Plex Sans throughout, and tabular figures so speeds, sizes
/// and peer counts tick without the layout jittering.
class TorrentLensTheme {
  /// The original seed, kept for continuity; the full scheme below is
  /// hand-tuned rather than generated, so light and dark are both designed.
  static const Color seed = Color(0xFF2E7D6F);

  // Light palette — teal primary with a cool slate supporting cast.
  static const Color _lPrimary = Color(0xFF1F6B5E);
  static const Color _lOnPrimary = Color(0xFFFFFFFF);
  static const Color _lPrimaryContainer = Color(0xFFB2F0E2);
  static const Color _lOnPrimaryContainer = Color(0xFF00201A);
  static const Color _lSecondary = Color(0xFF4A635C);
  static const Color _lSecondaryContainer = Color(0xFFCCE8DF);
  static const Color _lOnSecondaryContainer = Color(0xFF07201A);
  static const Color _lTertiary = Color(0xFF3E6376);
  static const Color _lTertiaryContainer = Color(0xFFC2E8FE);
  static const Color _lOnTertiaryContainer = Color(0xFF001F2C);
  static const Color _lSurface = Color(0xFFF6FBF7);
  static const Color _lSurfaceLow = Color(0xFFF0F5F1);
  static const Color _lSurfaceMedium = Color(0xFFE9EFEB);
  static const Color _lSurfaceHigh = Color(0xFFE3EAE6);
  static const Color _lSurfaceHighest = Color(0xFFDDE4E0);
  static const Color _lOnSurface = Color(0xFF171D1B);
  static const Color _lOnSurfaceVariant = Color(0xFF404946);
  static const Color _lOutline = Color(0xFF707975);
  static const Color _lOutlineVariant = Color(0xFFC0C9C4);

  // Dark palette — deep slate-green surfaces so teal reads as signal.
  static const Color _dPrimary = Color(0xFF97D3C3);
  static const Color _dOnPrimary = Color(0xFF00382F);
  static const Color _dPrimaryContainer = Color(0xFF005145);
  static const Color _dOnPrimaryContainer = Color(0xFFB2F0E2);
  static const Color _dSecondary = Color(0xFFB0CCC3);
  static const Color _dSecondaryContainer = Color(0xFF324B44);
  static const Color _dOnSecondaryContainer = Color(0xFFCCE8DF);
  static const Color _dTertiary = Color(0xFFA6CBE0);
  static const Color _dTertiaryContainer = Color(0xFF234B5E);
  static const Color _dOnTertiaryContainer = Color(0xFFC2E8FE);
  static const Color _dSurface = Color(0xFF0E1513);
  static const Color _dSurfaceLow = Color(0xFF161D1B);
  static const Color _dSurfaceMedium = Color(0xFF1A2320);
  static const Color _dSurfaceHigh = Color(0xFF242E2B);
  static const Color _dSurfaceHighest = Color(0xFF2F3936);
  static const Color _dOnSurface = Color(0xFFDCE4E0);
  static const Color _dOnSurfaceVariant = Color(0xFFBEC9C5);
  static const Color _dOutline = Color(0xFF8A9490);
  static const Color _dOutlineVariant = Color(0xFF404946);

  static const String _fontFamily = 'IBMPlexSans';

  static ThemeData light() => _base(isLight: true);
  static ThemeData dark() => _base(isLight: false);

  /// State colours shared by the dashboard, task cards and status pills, so
  /// "downloading" is the same blue everywhere in the app.
  static Color stateColor(String state, Brightness brightness) {
    final light = brightness == Brightness.light;
    return switch (state) {
      'downloading' || 'resolvingMetadata' =>
        light ? const Color(0xFF2B6CB0) : const Color(0xFF8FBEE8),
      'seeding' || 'completed' =>
        light ? const Color(0xFF2F7D4F) : const Color(0xFF8FD4A8),
      'checking' => light ? const Color(0xFF7C6A2F) : const Color(0xFFD8C486),
      'paused' || 'queued' =>
        light ? const Color(0xFF5C6562) : const Color(0xFF9AA5A1),
      'failed' || 'unavailable' =>
        light ? const Color(0xFFB3261E) : const Color(0xFFF2B8B5),
      _ => light ? const Color(0xFF5C6562) : const Color(0xFF9AA5A1),
    };
  }

  static ThemeData _base({required bool isLight}) {
    final scheme = isLight
        ? const ColorScheme(
            brightness: Brightness.light,
            primary: _lPrimary,
            onPrimary: _lOnPrimary,
            primaryContainer: _lPrimaryContainer,
            onPrimaryContainer: _lOnPrimaryContainer,
            secondary: _lSecondary,
            onSecondary: Color(0xFFFFFFFF),
            secondaryContainer: _lSecondaryContainer,
            onSecondaryContainer: _lOnSecondaryContainer,
            tertiary: _lTertiary,
            onTertiary: Color(0xFFFFFFFF),
            tertiaryContainer: _lTertiaryContainer,
            onTertiaryContainer: _lOnTertiaryContainer,
            error: Color(0xFFBA1A1A),
            onError: Color(0xFFFFFFFF),
            errorContainer: Color(0xFFFFDAD6),
            onErrorContainer: Color(0xFF410002),
            surface: _lSurface,
            onSurface: _lOnSurface,
            onSurfaceVariant: _lOnSurfaceVariant,
            outline: _lOutline,
            outlineVariant: _lOutlineVariant,
            shadow: Color(0xFF000000),
            scrim: Color(0xFF000000),
            inverseSurface: _lOnSurface,
            onInverseSurface: _lSurface,
            inversePrimary: Color(0xFF87D4C4),
            surfaceContainerLowest: Color(0xFFFFFFFF),
            surfaceContainerLow: _lSurfaceLow,
            surfaceContainer: _lSurfaceMedium,
            surfaceContainerHigh: _lSurfaceHigh,
            surfaceContainerHighest: _lSurfaceHighest,
          )
        : const ColorScheme(
            brightness: Brightness.dark,
            primary: _dPrimary,
            onPrimary: _dOnPrimary,
            primaryContainer: _dPrimaryContainer,
            onPrimaryContainer: _dOnPrimaryContainer,
            secondary: _dSecondary,
            onSecondary: Color(0xFF1C352E),
            secondaryContainer: _dSecondaryContainer,
            onSecondaryContainer: _dOnSecondaryContainer,
            tertiary: _dTertiary,
            onTertiary: Color(0xFF072F40),
            tertiaryContainer: _dTertiaryContainer,
            onTertiaryContainer: _dOnTertiaryContainer,
            error: Color(0xFFFFB4AB),
            onError: Color(0xFF690005),
            errorContainer: Color(0xFF93000A),
            onErrorContainer: Color(0xFFFFDAD6),
            surface: _dSurface,
            onSurface: _dOnSurface,
            onSurfaceVariant: _dOnSurfaceVariant,
            outline: _dOutline,
            outlineVariant: _dOutlineVariant,
            shadow: Color(0xFF000000),
            scrim: Color(0xFF000000),
            inverseSurface: _dOnSurface,
            onInverseSurface: _dSurface,
            inversePrimary: _lPrimary,
            surfaceContainerLowest: Color(0xFF090F0D),
            surfaceContainerLow: _dSurfaceLow,
            surfaceContainer: _dSurfaceMedium,
            surfaceContainerHigh: _dSurfaceHigh,
            surfaceContainerHighest: _dSurfaceHighest,
          );

    final textTheme = _textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: _fontFamily,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
        color: isLight ? scheme.surfaceContainerLowest : scheme.surfaceContainerLow,
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 10,
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: isLight ? scheme.surfaceContainerLowest : scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
              size: 22,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => textTheme.labelMedium!.copyWith(
              color: states.contains(WidgetState.selected)
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            )),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentTextStyle: textTheme.bodyMedium!.copyWith(color: scheme.onInverseSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        isDense: true,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearMinHeight: 5,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHigh,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: textTheme.labelLarge,
          side: BorderSide(color: scheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: textTheme.labelLarge,
      ),
      dialogTheme: DialogThemeData(
        elevation: 2,
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        labelStyle: textTheme.titleSmall,
        unselectedLabelStyle: textTheme.titleSmall,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
    );
  }

  /// IBM Plex Sans with slightly tightened tracking, and tabular figures on
  /// every style so numeric readouts never reflow as digits change.
  static TextTheme _textTheme(ColorScheme scheme) {
    const tabular = <FontFeature>[FontFeature.tabularFigures()];

    TextStyle build(
      double size, {
      FontWeight weight = FontWeight.w400,
      double? height,
      double? letterSpacing,
      Color? color,
    }) =>
        TextStyle(
          fontFamily: _fontFamily,
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: letterSpacing,
          color: color ?? scheme.onSurface,
          fontFeatures: tabular,
        );

    return TextTheme(
      displayLarge: build(57, height: 1.12, letterSpacing: -0.5),
      displayMedium: build(45, height: 1.12, letterSpacing: -0.4),
      displaySmall: build(36, height: 1.15, letterSpacing: -0.3),
      headlineLarge: build(32, weight: FontWeight.w600, height: 1.2, letterSpacing: -0.3),
      headlineMedium: build(28, weight: FontWeight.w600, height: 1.25, letterSpacing: -0.2),
      headlineSmall: build(24, weight: FontWeight.w600, height: 1.3, letterSpacing: -0.1),
      titleLarge: build(22, weight: FontWeight.w600, height: 1.3, letterSpacing: -0.1),
      titleMedium: build(16, weight: FontWeight.w600, height: 1.35),
      titleSmall: build(14, weight: FontWeight.w600, height: 1.35),
      bodyLarge: build(16, height: 1.5),
      bodyMedium: build(14, height: 1.5),
      bodySmall: build(12, height: 1.45, color: scheme.onSurfaceVariant),
      labelLarge: build(14, weight: FontWeight.w600, letterSpacing: 0.1),
      labelMedium: build(12, weight: FontWeight.w500, letterSpacing: 0.2),
      labelSmall: build(11, weight: FontWeight.w500, letterSpacing: 0.3, color: scheme.onSurfaceVariant),
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  }
}
