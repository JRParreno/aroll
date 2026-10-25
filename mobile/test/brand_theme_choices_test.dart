import 'package:aroll_mobile/presentation/owner/setup/brand_theme_choices.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('theme choices start with system, then ready-made themes', () {
    expect(allBrandThemes.first.id, 'system');
    expect(allBrandThemes.first.name, 'System Theme (Default)');
    expect(allBrandThemes[1].name, 'Soft Blue');
    expect(featuredBrandThemes.single.id, 'system');
    final plum = otherBrandThemes.firstWhere((theme) => theme.id == 'aroll-signature');
    expect(plum.name, 'Plum');
    expect(plum.group, 'Warm');
    expect(
      brandThemesInGroup('Warm').last.name,
      'Plum',
    );
  });

  test('system theme matches the login page background and default navy', () {
    expect(systemBrandTheme.previewSurface, '#F4F6F8');
    expect(systemBrandTheme.primary, '#1E3A5F');
    expect(systemBrandTheme.sidebar, '#1E3A5F');
    expect(systemBrandTheme.button, '#1E3A5F');
    expect(systemBrandTheme.secondary, '#284B73');
    expect(systemBrandTheme.accent, '#3B82F6');
    expect(findBrandThemeChoice(defaultBrandThemeFields())?.id, 'system');
  });

  test('plum keeps the purple, gold, and red palette', () {
    final plum = otherBrandThemes.firstWhere((theme) => theme.id == 'aroll-signature');
    expect(plum.sidebar, '#3C275C');
    expect(plum.primary, '#4C366E');
    expect(plum.button, '#4A3168');
    expect(plum.accent, '#8C6E16');
    expect(plum.secondary, '#7A3142');
    expect(findBrandThemeChoice(plum.colorMap)?.id, 'aroll-signature');
    expect(
      allBrandThemes.where((theme) => theme.name == 'Plum').length,
      1,
    );
  });

  test('custom colors stay unmatched so a preview does not rename them', () {
    final custom = {
      ...defaultBrandThemeFields(),
      'primary_color': '#112233',
    };
    expect(findBrandThemeChoice(custom), isNull);
    expect(brandColorsDiffer(custom, defaultBrandThemeFields()), isTrue);
    expect(brandColorsDiffer(custom, custom), isFalse);
  });

  test('color options explain the existing theme fields', () {
    expect(
      brandColorOptions.map((option) => option.key).toList(),
      [
        'primary_color',
        'secondary_color',
        'accent_color',
        'sidebar_color',
        'button_color',
      ],
    );
    expect(brandColorKeys.toSet(), brandColorOptions.map((option) => option.key).toSet());
    expect(brandColorOptions.first.effect, contains('Headings'));
    expect(brandColorOptions[2].effect, contains('page background'));
    expect(brandColorOptions[3].effect.toLowerCase(), contains('sidebar'));
  });

  test('existing coordinated themes remain available', () {
    expect(otherBrandThemes.map((theme) => theme.id), contains('soft-blue'));
    expect(otherBrandThemes.map((theme) => theme.id), contains('cream'));
    expect(otherBrandThemes.map((theme) => theme.id), contains('soft-lilac'));
    final softBlue =
        otherBrandThemes.firstWhere((theme) => theme.id == 'soft-blue');
    expect(softBlue.primary, '#3D6280');
    expect(softBlue.sidebar, '#35556F');
  });
}
