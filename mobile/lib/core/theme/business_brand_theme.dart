import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:flutter/material.dart';

/// Default Aroll navy palette used when business branding is missing.
abstract final class BrandDefaults {
  static const primary = Color(0xFF1E466E);
  static const primaryDark = Color(0xFF1E3A5F);
  static const secondary = Color(0xFF284B73);
  static const accent = Color(0xFF3B82F6);
  static const button = Color(0xFF1E3A5F);
  static const scaffold = Color(0xFFF4F6F8);
  static const iconWell = Color(0xFFE7EEF5);
  static const textBody = Color(0xFF374151);
  static const textPrimary = Color(0xFF111827);
}

Color? parseBrandHex(String? value) {
  if (value == null || value.isEmpty) return null;
  final normalized = value.replaceFirst('#', '').trim();
  if (normalized.length != 6) return null;
  final parsed = int.tryParse('FF$normalized', radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}

/// Business theme colors from owner setup, exposed via [ThemeExtension].
@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({
    required this.primary,
    required this.secondary,
    required this.button,
    required this.accent,
    required this.sidebar,
    required this.saved,
  });

  final Color primary;
  final Color secondary;
  final Color button;
  final Color accent;
  final Color sidebar;

  /// True when a business theme object is present on the session.
  /// Logged-out screens have no theme object and keep AppColors.
  final bool saved;

  /// Brand primary. Application navy when no custom palette is saved.
  Color get tonePrimary => saved ? primary : BrandDefaults.primary;

  /// Brand button / emphasis. Application navy-dark when no custom palette.
  Color get toneButton => saved ? button : BrandDefaults.primaryDark;

  /// Soft brand fill. Exact default well when no custom palette is saved.
  Color get toneWell => saved ? iconWell : BrandDefaults.iconWell;

  Color get toneSecondary => saved ? secondary : BrandDefaults.secondary;

  Color get toneSidebar => saved ? sidebar : BrandDefaults.primary;

  static BrandColors of(BuildContext context) {
    return Theme.of(context).extension<BrandColors>() ??
        const BrandColors(
          primary: BrandDefaults.primary,
          secondary: BrandDefaults.secondary,
          button: BrandDefaults.button,
          accent: BrandDefaults.accent,
          sidebar: BrandDefaults.primaryDark,
          saved: false,
        );
  }

  Color get iconWell =>
      Color.lerp(primary, Colors.white, 0.88) ?? BrandDefaults.iconWell;

  LinearGradient get headerGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          primary,
          Color.lerp(primary, secondary, 0.55) ?? secondary,
        ],
      );

  @override
  BrandColors copyWith({
    Color? primary,
    Color? secondary,
    Color? button,
    Color? accent,
    Color? sidebar,
    bool? saved,
  }) {
    return BrandColors(
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      button: button ?? this.button,
      accent: accent ?? this.accent,
      sidebar: sidebar ?? this.sidebar,
      saved: saved ?? this.saved,
    );
  }

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    return BrandColors(
      primary: Color.lerp(primary, other.primary, t) ?? primary,
      secondary: Color.lerp(secondary, other.secondary, t) ?? secondary,
      button: Color.lerp(button, other.button, t) ?? button,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      sidebar: Color.lerp(sidebar, other.sidebar, t) ?? sidebar,
      saved: t < 0.5 ? saved : other.saved,
    );
  }
}

/// True when the session already carries a business theme.
/// Color values are not compared with AppColors. A saved palette that
/// happens to match an application default is still branding.
bool savedBusinessPalette(BusinessBrandingSettings? branding) =>
    branding != null;

BrandColors brandColorsFromSettings(BusinessBrandingSettings? branding) {
  final theme = branding?.theme;
  return BrandColors(
    primary:
        parseBrandHex(theme?.primaryColor) ?? BrandDefaults.primary,
    secondary:
        parseBrandHex(theme?.secondaryColor) ?? BrandDefaults.secondary,
    button: parseBrandHex(theme?.buttonColor) ??
        parseBrandHex(theme?.primaryColor) ??
        BrandDefaults.button,
    accent: parseBrandHex(theme?.accentColor) ?? BrandDefaults.accent,
    sidebar: parseBrandHex(theme?.sidebarColor) ??
        parseBrandHex(theme?.primaryColor) ??
        BrandDefaults.primaryDark,
    saved: savedBusinessPalette(branding),
  );
}

/// Material theme driven by owner business-setup branding.
ThemeData buildBusinessThemeData(BusinessBrandingSettings? branding) {
  final brand = brandColorsFromSettings(branding);
  final scheme = ColorScheme.fromSeed(
    seedColor: brand.primary,
    primary: brand.primary,
    secondary: brand.secondary,
    brightness: Brightness.light,
  ).copyWith(
    primary: brand.primary,
    secondary: brand.secondary,
    tertiary: brand.accent,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: BrandDefaults.scaffold,
    appBarTheme: const AppBarTheme(
      backgroundColor: BrandDefaults.scaffold,
      foregroundColor: BrandDefaults.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brand.button,
        foregroundColor: Colors.white,
        disabledBackgroundColor: brand.button.withValues(alpha: 0.6),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: brand.button,
        foregroundColor: Colors.white,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: brand.button,
      foregroundColor: Colors.white,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: brand.primary,
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: brand.toneWell,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: brand.tonePrimary);
        }
        return const IconThemeData(color: BrandDefaults.textBody);
      }),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: brand.toneButton),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: Colors.white,
      headerBackgroundColor: brand.tonePrimary,
      headerForegroundColor: Colors.white,
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return BrandDefaults.textPrimary;
      }),
      todayForegroundColor: WidgetStateProperty.all(brand.tonePrimary),
      rangeSelectionBackgroundColor: brand.toneWell,
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: Colors.white,
      hourMinuteColor: brand.toneWell,
      hourMinuteTextColor: brand.tonePrimary,
      dayPeriodColor: brand.toneWell,
      dayPeriodTextColor: brand.toneButton,
      dialHandColor: brand.tonePrimary,
      dialBackgroundColor: brand.toneWell,
      entryModeIconColor: brand.toneButton,
      helpTextStyle: TextStyle(color: brand.toneButton),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return brand.tonePrimary;
        return null;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return brand.tonePrimary;
        return null;
      }),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return brand.tonePrimary;
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return brand.tonePrimary.withValues(alpha: 0.45);
        }
        return null;
      }),
    ),
    extensions: <ThemeExtension<dynamic>>[brand],
  );
}
