import 'dart:convert';

import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

const _brandThemes = <({
  String id,
  String name,
  String primary,
  String secondary,
  String sidebar,
  String accent,
  String button,
})>[
  (
    id: 'soft-blue',
    name: 'Soft Blue',
    primary: '#3D6280',
    secondary: '#4A7090',
    sidebar: '#35556F',
    accent: '#5E86A3',
    button: '#3A5C78',
  ),
  (
    id: 'sage',
    name: 'Sage',
    primary: '#466053',
    secondary: '#547062',
    sidebar: '#3E5348',
    accent: '#5E7A68',
    button: '#42604F',
  ),
  (
    id: 'lavender',
    name: 'Lavender',
    primary: '#554F78',
    secondary: '#655F88',
    sidebar: '#4A4568',
    accent: '#746C96',
    button: '#514B72',
  ),
  (
    id: 'sky',
    name: 'Sky',
    primary: '#426074',
    secondary: '#4E7084',
    sidebar: '#3A5568',
    accent: '#5C8498',
    button: '#3E5C70',
  ),
  (
    id: 'mint',
    name: 'Mint',
    primary: '#426056',
    secondary: '#4E7066',
    sidebar: '#3A554C',
    accent: '#5C8478',
    button: '#3E5C52',
  ),
  (
    id: 'peach',
    name: 'Peach',
    primary: '#745445',
    secondary: '#806052',
    sidebar: '#6A4A3C',
    accent: '#8C6A58',
    button: '#6E4E40',
  ),
  (
    id: 'blush',
    name: 'Blush',
    primary: '#754C5A',
    secondary: '#865C6A',
    sidebar: '#6A4552',
    accent: '#946274',
    button: '#6F4856',
  ),
  (
    id: 'sand',
    name: 'Sand',
    primary: '#665A4E',
    secondary: '#74685C',
    sidebar: '#5C5146',
    accent: '#7E7264',
    button: '#615548',
  ),
  (
    id: 'aqua',
    name: 'Aqua',
    primary: '#3D6A70',
    secondary: '#456F76',
    sidebar: '#355E64',
    accent: '#5A8890',
    button: '#39646A',
  ),
  (
    id: 'soft-teal',
    name: 'Soft Teal',
    primary: '#386266',
    secondary: '#467276',
    sidebar: '#2F5558',
    accent: '#548488',
    button: '#345E62',
  ),
];

bool brandingScreenShowsSkip(bool asSettings) => !asSettings;

String brandingScreenHelpText({required bool asSettings}) {
  if (asSettings) {
    return 'Update your business logo and brand colors. Saved values stay in sync with the web owner portal.';
  }
  return 'Optional logo and brand colors. Skip for now if you want '
      'to set this later in Business Settings.';
}

String brandingScreenSaveLabel({
  required bool asSettings,
  required bool busy,
}) {
  if (busy) return 'Saving…';
  return asSettings ? 'Save Branding' : 'Save and continue';
}

class OwnerBrandingOnboardingScreen extends StatefulWidget {
  const OwnerBrandingOnboardingScreen({
    super.key,
    this.asSettings = false,
  });

  final bool asSettings;

  @override
  State<OwnerBrandingOnboardingScreen> createState() =>
      _OwnerBrandingOnboardingScreenState();
}

class _OwnerBrandingOnboardingScreenState
    extends State<OwnerBrandingOnboardingScreen> {
  final _repo = sl<OwnerRepository>();
  final _picker = ImagePicker();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic> _settings = const {};
  String? _logoUrl;
  late Map<String, String> _theme;

  @override
  void initState() {
    super.initState();
    _theme = _defaultTheme();
    _load();
  }

  Map<String, String> _defaultTheme() => {
        'primary_color': '#1E3A5F',
        'secondary_color': '#284B73',
        'sidebar_color': '#1E3A5F',
        'accent_color': '#3B82F6',
        'button_color': '#1E3A5F',
        'card_style': 'soft',
        'font_size': 'comfortable',
        'color_mode': 'light',
        'layout_density': 'rounded',
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repo.businessSettings();
      final branding = data['branding'];
      final theme = branding is Map ? branding['theme'] : null;
      setState(() {
        _settings = data;
        _logoUrl = branding is Map ? branding['logo_url'] as String? : null;
        _theme = {
          ..._defaultTheme(),
          if (theme is Map)
            for (final entry in theme.entries)
              if (entry.value != null) '${entry.key}': '${entry.value}',
        };
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load branding.';
      });
    }
  }

  Future<void> _pickLogo() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 1800000) {
        _showSnack('Image is too large. Choose a smaller logo.');
        return;
      }
      final mime = file.mimeType ?? 'image/jpeg';
      if (!mime.startsWith('image/')) {
        _showSnack('Please choose an image file.');
        return;
      }
      setState(() {
        _logoUrl = 'data:$mime;base64,${base64Encode(bytes)}';
      });
    } catch (_) {
      _showSnack('Could not open the image picker.');
    }
  }

  Map<String, dynamic> _brandingPayload() {
    final existing = _settings['branding'];
    return {
      'logo_url': _logoUrl,
      'owner_profile_image_url':
          existing is Map ? existing['owner_profile_image_url'] : null,
      'display_image_url': _logoUrl,
      'theme': _theme,
    };
  }

  Future<void> _saveAndContinue() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _repo.completeBrandingOnboarding(branding: _brandingPayload());
      sl<AppState>().updateNeedsBrandingOnboarding(false);
      sl<AppState>().updateBusinessBranding(
        _brandingFromPayload(_brandingPayload()),
      );
      if (!mounted) return;
      if (widget.asSettings) {
        _showSnack('Business branding saved');
        return;
      }
      context.go('/owner/setup-wizard');
    } on DioException catch (error) {
      final detail = error.response?.data is Map
          ? (error.response?.data as Map)['detail']
          : null;
      _showSnack(detail is String ? detail : 'Could not save branding.');
    } catch (_) {
      _showSnack('Could not save branding.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _repo.completeBrandingOnboarding();
      sl<AppState>().updateNeedsBrandingOnboarding(false);
      if (!mounted) return;
      context.go('/owner/setup-wizard');
    } on DioException catch (error) {
      final detail = error.response?.data is Map
          ? (error.response?.data as Map)['detail']
          : null;
      _showSnack(detail is String ? detail : 'Could not skip branding.');
    } catch (_) {
      _showSnack('Could not skip branding.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ImageProvider? _logoProvider() {
    final url = _logoUrl;
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('data:image/')) {
      final comma = url.indexOf(',');
      if (comma < 0) return null;
      return MemoryImage(base64Decode(url.substring(comma + 1)));
    }
    return NetworkImage(url);
  }

  BusinessBrandingSettings _brandingFromPayload(Map<String, dynamic> payload) {
    final theme = payload['theme'] as Map<String, dynamic>? ?? const {};
    return BusinessBrandingSettings(
      logoUrl: payload['logo_url'] as String?,
      ownerProfileImageUrl: payload['owner_profile_image_url'] as String?,
      displayImageUrl: payload['display_image_url'] as String?,
      theme: BusinessThemeSettings(
        primaryColor: '${theme['primary_color'] ?? '#1E3A5F'}',
        secondaryColor: '${theme['secondary_color'] ?? '#284B73'}',
        sidebarColor: '${theme['sidebar_color'] ?? '#1E3A5F'}',
        accentColor: '${theme['accent_color'] ?? '#3B82F6'}',
        buttonColor: '${theme['button_color'] ?? '#1E3A5F'}',
        cardStyle: '${theme['card_style'] ?? 'soft'}',
        fontSize: '${theme['font_size'] ?? 'comfortable'}',
        colorMode: '${theme['color_mode'] ?? 'light'}',
        layoutDensity: '${theme['layout_density'] ?? 'rounded'}',
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _body() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: SetupUi.navyOf(context)));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SetupInfoBanner(_error!, tone: SetupBannerTone.danger),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _load,
                style: SetupUi.primaryButtonOf(context),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final name = '${_settings['business_name'] ?? 'Your business'}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        SetupInfoBanner(brandingScreenHelpText(asSettings: widget.asSettings)),
        const SizedBox(height: 14),
        SetupPanel(
          title: 'Business logo',
          icon: Icons.image_outlined,
          subtitle: 'Shown in the owner portal and employee app.',
          children: [
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor: SetupUi.wellOf(context),
                backgroundImage: _logoProvider(),
                child: _logoUrl == null
                    ? Text(
                        name.isEmpty ? 'B' : name[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy ? null : _pickLogo,
                  style: SetupUi.primaryButtonOf(context),
                  child: Text(
                    _logoUrl == null ? 'Upload logo' : 'Replace logo',
                  ),
                ),
                if (_logoUrl != null)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _logoUrl = null),
                    child: const Text('Remove'),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        SetupPanel(
          title: 'Brand colors',
          icon: Icons.palette_outlined,
          subtitle: 'Choose a coordinated theme used on web and mobile.',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final theme in _brandThemes)
                  _ThemeChoice(
                    name: theme.name,
                    color: theme.primary,
                    selected: _theme['primary_color'] == theme.primary,
                    onTap: () => setState(() {
                      _theme = {
                        ..._theme,
                        'primary_color': theme.primary,
                        'secondary_color': theme.secondary,
                        'sidebar_color': theme.sidebar,
                        'accent_color': theme.accent,
                        'button_color': theme.button,
                      };
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Color(
                  int.parse(
                    'FF${_theme['primary_color']!.replaceFirst('#', '')}',
                    radix: 16,
                  ),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _busy ? null : _saveAndContinue,
            style: SetupUi.primaryButtonOf(context),
            child: Text(
              brandingScreenSaveLabel(
                asSettings: widget.asSettings,
                busy: _busy,
              ),
            ),
          ),
        ),
        if (brandingScreenShowsSkip(widget.asSettings)) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton(
              onPressed: _busy ? null : _skip,
              child: const Text('Skip for now'),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.asSettings) {
      return OwnerShell(
        selectedIndex: 2,
        showBackButton: true,
        title: 'Business Branding',
        backgroundColor: SetupUi.scaffold,
        child: _body(),
      );
    }
    return Scaffold(
      backgroundColor: SetupUi.scaffold,
      appBar: AppBar(
        title: const Text('Business Branding'),
      ),
      body: _body(),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parsed = Color(int.parse('FF${color.replaceFirst('#', '')}', radix: 16));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 104,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? parsed : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 22,
                decoration: BoxDecoration(
                  color: parsed,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
