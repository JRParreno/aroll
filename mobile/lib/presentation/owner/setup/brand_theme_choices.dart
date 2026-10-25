/// Owner branding theme choices shared by the mobile branding screen.
/// Color values match the web owner theme catalog.
class BrandThemeChoice {
  const BrandThemeChoice({
    required this.id,
    required this.name,
    required this.description,
    required this.group,
    required this.previewSurface,
    required this.primary,
    required this.secondary,
    required this.sidebar,
    required this.accent,
    required this.button,
  });

  final String id;
  final String name;
  final String description;
  final String group;
  final String previewSurface;
  final String primary;
  final String secondary;
  final String sidebar;
  final String accent;
  final String button;

  Map<String, String> get colorMap => {
        'primary_color': primary,
        'secondary_color': secondary,
        'sidebar_color': sidebar,
        'accent_color': accent,
        'button_color': button,
      };
}

class BrandColorOption {
  const BrandColorOption({
    required this.key,
    required this.label,
    required this.effect,
  });

  final String key;
  final String label;
  final String effect;
}

/// Web owner login page background, also the mobile app scaffold.
const systemThemeSurface = '#F4F6F8';

/// Saved default palette. Navy matches the login brand panel (#1E3A5F).
const systemBrandTheme = BrandThemeChoice(
  id: 'system',
  name: 'System Theme (Default)',
  description: 'Original Aroll+ navy, matching the login page.',
  group: 'Featured',
  previewSurface: systemThemeSurface,
  primary: '#1E3A5F',
  secondary: '#284B73',
  sidebar: '#1E3A5F',
  accent: '#3B82F6',
  button: '#1E3A5F',
);

/// Display name is Plum. The id stays so a saved color match still selects it.
const plumBrandTheme = BrandThemeChoice(
  id: 'aroll-signature',
  name: 'Plum',
  description: 'Warm plum, gold, and deep red',
  group: 'Warm',
  previewSurface: '#F7F4EE',
  primary: '#4C366E',
  secondary: '#7A3142',
  sidebar: '#3C275C',
  accent: '#8C6E16',
  button: '#4A3168',
);

const featuredBrandThemes = <BrandThemeChoice>[
  systemBrandTheme,
];

const brandThemeGroups = <String>['Calm', 'Warm', 'Fresh'];

const otherBrandThemes = <BrandThemeChoice>[
  BrandThemeChoice(
    id: 'soft-blue',
    name: 'Soft Blue',
    description: 'Calm, clean, professional',
    group: 'Calm',
    previewSurface: '#E7F0F6',
    primary: '#3D6280',
    secondary: '#4A7090',
    sidebar: '#35556F',
    accent: '#5E86A3',
    button: '#3A5C78',
  ),
  BrandThemeChoice(
    id: 'sage',
    name: 'Sage',
    description: 'Soft botanical green',
    group: 'Calm',
    previewSurface: '#E7F0EA',
    primary: '#466053',
    secondary: '#547062',
    sidebar: '#3E5348',
    accent: '#5E7A68',
    button: '#42604F',
  ),
  BrandThemeChoice(
    id: 'lavender',
    name: 'Lavender',
    description: 'Quiet and restrained',
    group: 'Calm',
    previewSurface: '#EEEAF4',
    primary: '#554F78',
    secondary: '#655F88',
    sidebar: '#4A4568',
    accent: '#746C96',
    button: '#514B72',
  ),
  BrandThemeChoice(
    id: 'sky',
    name: 'Sky',
    description: 'Cool and airy',
    group: 'Calm',
    previewSurface: '#E8F3F6',
    primary: '#426074',
    secondary: '#4E7084',
    sidebar: '#3A5568',
    accent: '#5C8498',
    button: '#3E5C70',
  ),
  BrandThemeChoice(
    id: 'mint',
    name: 'Mint',
    description: 'Fresh and balanced',
    group: 'Calm',
    previewSurface: '#E8F6F1',
    primary: '#426056',
    secondary: '#4E7066',
    sidebar: '#3A554C',
    accent: '#5C8478',
    button: '#3E5C52',
  ),
  BrandThemeChoice(
    id: 'peach',
    name: 'Peach',
    description: 'Warm and gentle',
    group: 'Warm',
    previewSurface: '#F8EFEA',
    primary: '#745445',
    secondary: '#806052',
    sidebar: '#6A4A3C',
    accent: '#8C6A58',
    button: '#6E4E40',
  ),
  BrandThemeChoice(
    id: 'blush',
    name: 'Blush',
    description: 'Soft rose with neutral depth',
    group: 'Warm',
    previewSurface: '#F8EEF1',
    primary: '#754C5A',
    secondary: '#865C6A',
    sidebar: '#6A4552',
    accent: '#946274',
    button: '#6F4856',
  ),
  BrandThemeChoice(
    id: 'sand',
    name: 'Sand',
    description: 'Warm beige, muted accent',
    group: 'Warm',
    previewSurface: '#F6F1EA',
    primary: '#665A4E',
    secondary: '#74685C',
    sidebar: '#5C5146',
    accent: '#7E7264',
    button: '#615548',
  ),
  BrandThemeChoice(
    id: 'cream',
    name: 'Cream',
    description: 'Soft warm neutral',
    group: 'Warm',
    previewSurface: '#F7F3EC',
    primary: '#645C50',
    secondary: '#726A5E',
    sidebar: '#5A5348',
    accent: '#7C7466',
    button: '#5F584C',
  ),
  BrandThemeChoice(
    id: 'soft-coral',
    name: 'Soft Coral',
    description: 'Muted warm coral',
    group: 'Warm',
    previewSurface: '#F8EEEE',
    primary: '#754E50',
    secondary: '#855E60',
    sidebar: '#6A4548',
    accent: '#94686A',
    button: '#6F494C',
  ),
  plumBrandTheme,
  BrandThemeChoice(
    id: 'aqua',
    name: 'Aqua',
    description: 'Clear and light',
    group: 'Fresh',
    previewSurface: '#E7F4F5',
    primary: '#3D6A70',
    secondary: '#456F76',
    sidebar: '#355E64',
    accent: '#5A8890',
    button: '#39646A',
  ),
  BrandThemeChoice(
    id: 'soft-teal',
    name: 'Soft Teal',
    description: 'Cool and steady',
    group: 'Fresh',
    previewSurface: '#E6F3F2',
    primary: '#386266',
    secondary: '#467276',
    sidebar: '#2F5558',
    accent: '#548488',
    button: '#345E62',
  ),
  BrandThemeChoice(
    id: 'pistachio',
    name: 'Pistachio',
    description: 'Light green, grounded',
    group: 'Fresh',
    previewSurface: '#F0F4EA',
    primary: '#54624A',
    secondary: '#627058',
    sidebar: '#4A5540',
    accent: '#6E7C62',
    button: '#4F5C46',
  ),
  BrandThemeChoice(
    id: 'soft-lilac',
    name: 'Soft Lilac',
    description: 'Gentle cool violet',
    group: 'Fresh',
    previewSurface: '#F3EEF6',
    primary: '#62546E',
    secondary: '#72647E',
    sidebar: '#554860',
    accent: '#80728C',
    button: '#5C4E68',
  ),
];

const allBrandThemes = <BrandThemeChoice>[
  ...featuredBrandThemes,
  ...otherBrandThemes,
];

const brandColorKeys = <String>[
  'primary_color',
  'secondary_color',
  'sidebar_color',
  'accent_color',
  'button_color',
];

const brandColorOptions = <BrandColorOption>[
  BrandColorOption(
    key: 'primary_color',
    label: 'Primary color',
    effect:
        'Headings, links, focus rings, and selected navigation icons. On the mobile owner app it also colors checkboxes, switches, progress indicators, and date-picker headers.',
  ),
  BrandColorOption(
    key: 'secondary_color',
    label: 'Secondary color',
    effect:
        'The selected item in the web owner sidebar, the hover color of primary buttons, and supporting gradients next to the primary color.',
  ),
  BrandColorOption(
    key: 'accent_color',
    label: 'Accent color',
    effect:
        'Highlights and selected outlines. On the web owner portal it also colors checkbox accents and emphasized borders. It does not change the page background.',
  ),
  BrandColorOption(
    key: 'sidebar_color',
    label: 'Sidebar color',
    effect:
        'Background of the web owner navigation sidebar. On mobile it tints some header gradients.',
  ),
  BrandColorOption(
    key: 'button_color',
    label: 'Button color',
    effect:
        'Primary action buttons and other main filled controls on web and mobile.',
  ),
];

List<BrandThemeChoice> brandThemesInGroup(String group) =>
    otherBrandThemes.where((theme) => theme.group == group).toList();

String normalizeBrandHex(String value) {
  final raw = value.trim().replaceFirst('#', '');
  if (RegExp(r'^[0-9a-fA-F]{3}$').hasMatch(raw)) {
    final expanded = raw.split('').map((char) => '$char$char').join();
    return '#${expanded.toUpperCase()}';
  }
  if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(raw)) {
    return '#${raw.toUpperCase()}';
  }
  return value.trim().toUpperCase();
}

bool isValidBrandHex(String value) =>
    RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalizeBrandHex(value));

bool brandThemeMatches(Map<String, String> theme, BrandThemeChoice choice) {
  final colors = choice.colorMap;
  for (final entry in colors.entries) {
    if (normalizeBrandHex(theme[entry.key] ?? '') !=
        normalizeBrandHex(entry.value)) {
      return false;
    }
  }
  return true;
}

BrandThemeChoice? findBrandThemeChoice(Map<String, String> theme) {
  for (final choice in allBrandThemes) {
    if (brandThemeMatches(theme, choice)) return choice;
  }
  return null;
}

bool brandColorsDiffer(Map<String, String> left, Map<String, String> right) {
  for (final key in brandColorKeys) {
    if (normalizeBrandHex(left[key] ?? '') != normalizeBrandHex(right[key] ?? '')) {
      return true;
    }
  }
  return false;
}

Map<String, String> defaultBrandThemeFields() => {
      ...systemBrandTheme.colorMap,
      'card_style': 'soft',
      'font_size': 'comfortable',
      'color_mode': 'light',
      'layout_density': 'rounded',
    };
