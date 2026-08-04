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
  });

  final Color primary;
  final Color secondary;
  final Color button;
  final Color accent;
  final Color sidebar;

  static BrandColors of(BuildContext context) {
    return Theme.of(context).extension<BrandColors>() ??
        const BrandColors(
          primary: BrandDefaults.primary,
          secondary: BrandDefaults.secondary,
          button: BrandDefaults.button,
          accent: BrandDefaults.accent,
          sidebar: BrandDefaults.primaryDark,
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
  }) {
    return BrandColors(
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      button: button ?? this.button,
      accent: accent ?? this.accent,
      sidebar: sidebar ?? this.sidebar,
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
    );
  }
}

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
      indicatorColor: brand.iconWell,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: brand.primary);
        }
        return const IconThemeData(color: BrandDefaults.textBody);
      }),
    ),
    extensions: <ThemeExtension<dynamic>>[brand],
  );
}
