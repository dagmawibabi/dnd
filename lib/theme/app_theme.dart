import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Minimal dark palette: near-black surfaces, neutral text, one accent.
class AppColors {
  static const bg = Color(0xFF0A0A0B);
  static const surface = Color(0xFF121214);
  static const surface2 = Color(0xFF18181B);
  static const surface3 = Color(0xFF212125);
  static const border = Color(0xFF232327);
  static const borderStrong = Color(0xFF303036);

  static const text = Color(0xFFF4F4F5);
  static const textMuted = Color(0xFFA1A1AA);
  static const textFaint = Color(0xFF63636B);

  static const accent = Color(0xFF8B7CF6);
  static const accentSoft = Color(0x268B7CF6);

  static const success = Color(0xFF4ADE80);
  static const danger = Color(0xFFF87171);
  static const warning = Color(0xFFFBBF24);
  static const info = Color(0xFF60A5FA);
  static const hp = Color(0xFFF87171);
  static const xp = Color(0xFF8B7CF6);
}

/// Typography scale (Inter).
class T {
  /// High-contrast mode lifts muted and faint text one step brighter.
  static bool highContrast = false;

  /// Story text preferences: 'serif', 'sans' or 'mono', and a size multiplier.
  static String readingFont = 'serif';
  static double readingScale = 1.0;

  static TextStyle _story(double size, {Color color = AppColors.text, double height = 1.65}) {
    final s = size * readingScale;
    return switch (readingFont) {
      'mono' => TextStyle(fontFamily: 'JetBrainsMono', fontSize: s * 0.94, color: _c(color), height: height, fontVariations: _w(FontWeight.w400)),
      'sans' => _s(s, FontWeight.w400, color: color, height: height, spacing: -0.1),
      _ => TextStyle(fontFamily: 'serif', fontFamilyFallback: const ['Georgia', 'Noto Serif', 'Times New Roman'], fontSize: s * 1.03, color: _c(color), height: height),
    };
  }

  static Color _c(Color c) {
    if (!highContrast) return c;
    if (c == AppColors.textMuted) return const Color(0xFFE4E4E7);
    if (c == AppColors.textFaint) return const Color(0xFFB4B4BC);
    return c;
  }

  static List<FontVariation> _w(FontWeight w) => [FontVariation('wght', w.value.toDouble())];

  static TextStyle _s(double size, FontWeight w, {Color color = AppColors.text, double? height, double spacing = 0}) =>
      TextStyle(fontFamily: 'Inter', fontSize: size, fontWeight: w, fontVariations: _w(w), color: _c(color), height: height, letterSpacing: spacing);

  static TextStyle h1({Color color = AppColors.text}) => _s(28, FontWeight.w700, color: color, spacing: -0.8, height: 1.15);
  static TextStyle h2({Color color = AppColors.text}) => _s(21, FontWeight.w600, color: color, spacing: -0.4, height: 1.2);
  static TextStyle h3({Color color = AppColors.text}) => _s(15.5, FontWeight.w600, color: color, spacing: -0.1, height: 1.3);
  static TextStyle body({Color color = AppColors.text}) => _s(15, FontWeight.w400, color: color, height: 1.45);
  static TextStyle bodyMuted() => body(color: AppColors.textMuted);
  static TextStyle reading({Color color = AppColors.text}) => _story(16.5, color: color);

  /// Chat bubbles in stories and conversations (follows the reading font and size).
  static TextStyle chat({Color color = AppColors.text}) => readingFont == 'serif' ? _s(15 * readingScale, FontWeight.w400, color: color, height: 1.45) : _story(15, color: color, height: 1.45);

  /// Monospace story text (terminal layouts), scaled with the reading size.
  static TextStyle monoStory(double size, {Color color = AppColors.text}) => mono(size * readingScale, color: color);
  static TextStyle small({Color color = AppColors.textMuted}) => _s(13, FontWeight.w400, color: color, height: 1.4);
  static TextStyle caption({Color color = AppColors.textFaint}) => _s(12, FontWeight.w500, color: color, height: 1.3);
  static TextStyle overline({Color color = AppColors.textFaint}) => _s(11, FontWeight.w600, color: color, spacing: 0.8);
  static TextStyle number(double size, {Color color = AppColors.text}) =>
      _s(size, FontWeight.w600, color: color, spacing: -0.5).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  static TextStyle mono(double size, {Color color = AppColors.text}) =>
      TextStyle(fontFamily: 'JetBrainsMono', fontSize: size, color: _c(color), height: 1.6, fontVariations: _w(FontWeight.w400));
}

ThemeData buildAppTheme({bool highContrast = false}) {
  T.highContrast = highContrast;
  final edge = highContrast ? const Color(0xFF6B6B75) : AppColors.border;
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: const ColorScheme.dark(
      primary: AppColors.text,
      onPrimary: AppColors.bg,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      tertiary: AppColors.accent,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      surfaceContainerHighest: AppColors.surface3,
      surfaceContainerHigh: AppColors.surface2,
      surfaceContainer: AppColors.surface,
      error: AppColors.danger,
      outline: AppColors.borderStrong,
      outlineVariant: AppColors.border,
    ),
    dividerColor: edge,
    scaffoldBackgroundColor: AppColors.bg,
  );
  OutlineInputBorder border(Color c) => OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c));
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: T.h3(),
      iconTheme: const IconThemeData(color: AppColors.text, size: 22),
    ),
    iconTheme: const IconThemeData(color: AppColors.textMuted, size: 20),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface2,
      hintStyle: T.body(color: AppColors.textFaint),
      labelStyle: T.small(),
      floatingLabelStyle: T.small(color: AppColors.text),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(AppColors.border),
      enabledBorder: border(edge),
      focusedBorder: border(AppColors.textMuted),
      disabledBorder: border(AppColors.border),
      isDense: true,
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: AppColors.text, selectionColor: AppColors.accentSoft, selectionHandleColor: AppColors.accent),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.text,
      inactiveTrackColor: AppColors.surface3,
      thumbColor: AppColors.text,
      overlayColor: Colors.white.withValues(alpha: 0.08),
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      valueIndicatorColor: AppColors.surface3,
      valueIndicatorTextStyle: T.small(color: AppColors.text),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return AppColors.textFaint;
        return s.contains(WidgetState.selected) ? Colors.white : AppColors.textMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return AppColors.surface2;
        return s.contains(WidgetState.selected) ? AppColors.accent : AppColors.surface3;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) && !s.contains(WidgetState.disabled) ? AppColors.accent : AppColors.borderStrong),
      trackOutlineWidth: WidgetStateProperty.all(1),
      overlayColor: WidgetStateProperty.all(AppColors.accentSoft),
      thumbIcon: WidgetStateProperty.all(null),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.accent : Colors.transparent),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surface3,
      contentTextStyle: T.body(),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.borderStrong)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.border)),
      titleTextStyle: T.h3(),
      contentTextStyle: T.bodyMuted(),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      modalBackgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: AppColors.borderStrong,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.text,
      unselectedLabelColor: AppColors.textFaint,
      indicatorColor: AppColors.text,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.border,
      labelStyle: T.h3(),
      unselectedLabelStyle: T.h3(),
      tabAlignment: TabAlignment.start,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
    ),
    chipTheme: ChipThemeData(
      // Selected chips: soft accent fill, accent outline, readable light label.
      color: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return AppColors.surface;
        return s.contains(WidgetState.selected) ? const Color(0x408B7CF6) : AppColors.surface2;
      }),
      checkmarkColor: AppColors.text,
      side: WidgetStateBorderSide.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return const BorderSide(color: AppColors.accent, width: 1.2);
        return BorderSide(color: edge);
      }),
      labelStyle: WidgetStateTextStyle.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return T.small(color: AppColors.textFaint);
        return T.small(color: AppColors.text).copyWith(fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400);
      }),
      secondaryLabelStyle: T.small(color: AppColors.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) && !s.contains(WidgetState.disabled) ? AppColors.surface3 : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return AppColors.textFaint;
          return s.contains(WidgetState.selected) ? AppColors.text : AppColors.textMuted;
        }),
        iconColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return AppColors.textFaint;
          return s.contains(WidgetState.selected) ? AppColors.text : AppColors.textMuted;
        }),
        side: WidgetStateProperty.all(const BorderSide(color: AppColors.border)),
        textStyle: WidgetStateProperty.all(T.small(color: AppColors.text)),
        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        visualDensity: VisualDensity.compact,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.accentSoft,
      indicatorShape: const StadiumBorder(),
      height: 70,
      elevation: 0,
      labelPadding: const EdgeInsets.only(top: 2),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => T.caption(color: s.contains(WidgetState.selected) ? AppColors.text : AppColors.textFaint).copyWith(
            fontSize: 11.5,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            letterSpacing: 0.1,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.accent : AppColors.textFaint, size: 23)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.bg,
      indicatorColor: AppColors.surface3,
      selectedIconTheme: const IconThemeData(color: AppColors.text),
      unselectedIconTheme: const IconThemeData(color: AppColors.textFaint),
      selectedLabelTextStyle: T.caption(color: AppColors.text),
      unselectedLabelTextStyle: T.caption(),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.textMuted,
      titleTextStyle: T.body(),
      subtitleTextStyle: T.small(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface2,
      surfaceTintColor: Colors.transparent,
      textStyle: T.body(),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.text, linearTrackColor: AppColors.surface3),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.text, textStyle: T.h3())),
    tooltipTheme: TooltipThemeData(decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(8)), textStyle: T.small(color: AppColors.text)),
    badgeTheme: const BadgeThemeData(backgroundColor: AppColors.accent),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
