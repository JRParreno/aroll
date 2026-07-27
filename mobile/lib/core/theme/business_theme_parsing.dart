import 'package:aroll_mobile/core/theme/schedule_theme.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';

BusinessBrandingSettings? businessBrandingFromJson(Map<String, dynamic>? data) {
  if (data == null) return null;
  final theme = data['theme'];
  final themeMap = theme is Map<String, dynamic> ? theme : <String, dynamic>{};
  return BusinessBrandingSettings(
    logoUrl: data['logo_url'] as String?,
    ownerProfileImageUrl: data['owner_profile_image_url'] as String?,
    displayImageUrl: data['display_image_url'] as String?,
    theme: businessThemeSettingsFromJson(themeMap),
  );
}

BusinessThemeSettings businessThemeSettingsFromJson(Map<String, dynamic> themeMap) {
  return BusinessThemeSettings(
    primaryColor: (themeMap['primary_color'] as String?) ?? '#1E3A5F',
    secondaryColor: (themeMap['secondary_color'] as String?) ?? '#284B73',
    sidebarColor: (themeMap['sidebar_color'] as String?) ?? '#1E3A5F',
    accentColor: (themeMap['accent_color'] as String?) ?? '#3B82F6',
    buttonColor: (themeMap['button_color'] as String?) ?? '#1E3A5F',
    cardStyle: (themeMap['card_style'] as String?) ?? 'soft',
    fontSize: (themeMap['font_size'] as String?) ?? 'comfortable',
    colorMode: (themeMap['color_mode'] as String?) ?? 'light',
    layoutDensity: (themeMap['layout_density'] as String?) ?? 'rounded',
    scheduleColors: ScheduleTableColors.fromJson(
      themeMap['schedule_colors'] as Map<String, dynamic>?,
    ),
    scheduleDisplay: ScheduleDisplaySettings.fromJson(
      themeMap['schedule_display'] as Map<String, dynamic>?,
    ),
  );
}

Map<String, dynamic> businessBrandingForSave(BusinessBrandingSettings branding) {
  return {
    'logo_url': branding.logoUrl,
    'owner_profile_image_url': branding.ownerProfileImageUrl,
    'display_image_url': branding.logoUrl ?? branding.displayImageUrl,
    'theme': {
      'primary_color': branding.theme.primaryColor,
      'secondary_color': branding.theme.secondaryColor,
      'sidebar_color': branding.theme.sidebarColor,
      'accent_color': branding.theme.accentColor,
      'button_color': branding.theme.buttonColor,
      'card_style': branding.theme.cardStyle,
      'font_size': branding.theme.fontSize,
      'color_mode': branding.theme.colorMode,
      'layout_density': branding.theme.layoutDensity,
      'schedule_colors': branding.theme.scheduleColors.toJson(),
      'schedule_display': branding.theme.scheduleDisplay.toJson(),
    },
  };
}
