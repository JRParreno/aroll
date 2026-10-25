import 'dart:convert';

import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/brand_theme_choices.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

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
  Map<String, String>? _savedTheme;

  @override
  void initState() {
    super.initState();
    _theme = defaultBrandThemeFields();
    _load();
  }

  Map<String, String> _defaultTheme() => defaultBrandThemeFields();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repo.businessSettings();
      final branding = data['branding'];
      final theme = branding is Map ? branding['theme'] : null;
      final nextTheme = {
        ..._defaultTheme(),
        if (theme is Map)
          for (final entry in theme.entries)
            if (entry.value != null) '${entry.key}': '${entry.value}',
      };
      setState(() {
        _settings = data;
        _logoUrl = branding is Map ? branding['logo_url'] as String? : null;
        _theme = nextTheme;
        _savedTheme = Map<String, String>.from(nextTheme);
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
      setState(() => _savedTheme = Map<String, String>.from(_theme));
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
        primaryColor:
            '${theme['primary_color'] ?? systemBrandTheme.primary}',
        secondaryColor:
            '${theme['secondary_color'] ?? systemBrandTheme.secondary}',
        sidebarColor:
            '${theme['sidebar_color'] ?? systemBrandTheme.sidebar}',
        accentColor: '${theme['accent_color'] ?? systemBrandTheme.accent}',
        buttonColor: '${theme['button_color'] ?? systemBrandTheme.button}',
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

  void _applyChoice(BrandThemeChoice choice) {
    setState(() {
      _theme = {..._theme, ...choice.colorMap};
    });
  }

  void _setColor(String key, String value) {
    setState(() => _theme = {..._theme, key: value});
  }

  Future<void> _editColor(BrandColorOption option) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => _BrandColorDialog(
        label: option.label,
        initialHex: _theme[option.key] ?? '',
      ),
    );
    if (!mounted || picked == null) return;
    _setColor(option.key, picked);
  }

  void _restoreSavedColors() {
    final saved = _savedTheme;
    if (saved == null) return;
    setState(() {
      _theme = {
        ..._theme,
        for (final key in brandColorKeys)
          if (saved[key] != null) key: saved[key]!,
      };
    });
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
          subtitle:
              'System Theme, a coordinated theme, or your own colors. The same choice is saved for web and mobile.',
          children: [
            for (final theme in featuredBrandThemes) ...[
              _FeaturedThemeCard(
                theme: theme,
                selected: brandThemeMatches(_theme, theme),
                onTap: _busy ? null : () => _applyChoice(theme),
              ),
              const SizedBox(height: 8),
            ],
            for (final group in brandThemeGroups) ...[
              const SizedBox(height: 6),
              Text(
                group,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final theme in brandThemesInGroup(group))
                    _ThemeChoice(
                      name: theme.name,
                      color: theme.primary,
                      selected: brandThemeMatches(_theme, theme),
                      onTap: _busy ? () {} : () => _applyChoice(theme),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _ThemeChoice(
              name: 'Custom Colors',
              color: _theme['primary_color'] ?? systemBrandTheme.primary,
              selected: findBrandThemeChoice(_theme) == null,
              wide: true,
              onTap: _busy
                  ? () {}
                  : () {
                      final saved = _savedTheme;
                      if (saved == null || findBrandThemeChoice(_theme) == null) {
                        return;
                      }
                      if (findBrandThemeChoice(saved) != null) return;
                      _restoreSavedColors();
                    },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Custom colors',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_savedTheme != null &&
                    brandColorsDiffer(_theme, _savedTheme!))
                  TextButton(
                    onPressed: _busy ? null : _restoreSavedColors,
                    child: const Text('Restore saved colors'),
                  ),
              ],
            ),
            Text(
              findBrandThemeChoice(_theme) == null
                  ? 'These are your custom colors. Save to use them on web and mobile.'
                  : 'These colors come from ${findBrandThemeChoice(_theme)!.name}. Change a color to make your own theme. Saved colors stay until you save.',
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            for (final option in brandColorOptions) ...[
              _BrandColorRow(
                option: option,
                value: _theme[option.key] ?? '',
                source: findBrandThemeChoice(_theme) == null
                    ? 'Your custom color'
                    : 'Set by ${findBrandThemeChoice(_theme)!.name}',
                enabled: !_busy,
                onChanged: (value) => _setColor(option.key, value),
                onPick: () => _editColor(option),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 2),
            Builder(
              builder: (context) {
                final hex = normalizeBrandHex(_theme['primary_color'] ?? '');
                final rgb = isValidBrandHex(hex)
                    ? int.parse(hex.substring(1), radix: 16)
                    : 0x1E3A5F;
                final preview = Color(0xFF000000 | rgb);
                final red = (rgb >> 16) & 0xFF;
                final green = (rgb >> 8) & 0xFF;
                final blue = rgb & 0xFF;
                final luminance = (0.299 * red + 0.587 * green + 0.114 * blue) / 255;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: preview,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    name,
                    style: TextStyle(
                      color: luminance > 0.72
                          ? const Color(0xFF111827)
                          : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
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
    this.wide = false,
  });

  final String name;
  final String color;
  final bool selected;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final parsed = parseBrandHex(color) ?? const Color(0xFF1E3A5F);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: wide ? double.infinity : 104,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF1E3A5F) : AppColors.border,
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

class _FeaturedThemeCard extends StatelessWidget {
  const _FeaturedThemeCard({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final BrandThemeChoice theme;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final swatches = [
      theme.previewSurface,
      theme.accent,
      theme.secondary,
      theme.sidebar,
    ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF1E3A5F) : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                theme.name,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final swatch in swatches)
                    Expanded(
                      child: Container(
                        height: 22,
                        color: parseBrandHex(swatch) ?? AppColors.border,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                theme.description,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                selected ? 'Selected' : 'Choose',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? const Color(0xFF1E3A5F)
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandColorRow extends StatefulWidget {
  const _BrandColorRow({
    required this.option,
    required this.value,
    required this.source,
    required this.enabled,
    required this.onChanged,
    required this.onPick,
  });

  final BrandColorOption option;
  final String value;
  final String source;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onPick;

  @override
  State<_BrandColorRow> createState() => _BrandColorRowState();
}

class _BrandColorRowState extends State<_BrandColorRow> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _BrandColorRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsed = parseBrandHex(widget.value);
    final valid = isValidBrandHex(widget.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.option.label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          widget.option.effect,
          style: const TextStyle(
            fontSize: 12,
            height: 1.35,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          widget.source,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E3A5F),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Material(
              color: parsed ?? const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: widget.enabled ? widget.onPick : null,
                borderRadius: BorderRadius.circular(8),
                child: const SizedBox(width: 42, height: 42),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                enabled: widget.enabled,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: SetupUi.input('Hex value'),
                onChanged: widget.onChanged,
                onEditingComplete: () {
                  if (isValidBrandHex(_controller.text)) {
                    widget.onChanged(normalizeBrandHex(_controller.text));
                  }
                },
              ),
            ),
          ],
        ),
        if (!valid)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'This value is not a usable hex color. Choose a color to replace it.',
              style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
            ),
          ),
      ],
    );
  }
}

class _BrandColorDialog extends StatefulWidget {
  const _BrandColorDialog({
    required this.label,
    required this.initialHex,
  });

  final String label;
  final String initialHex;

  @override
  State<_BrandColorDialog> createState() => _BrandColorDialogState();
}

class _BrandColorDialogState extends State<_BrandColorDialog> {
  late int _red;
  late int _green;
  late int _blue;
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    final hex = isValidBrandHex(widget.initialHex)
        ? normalizeBrandHex(widget.initialHex)
        : '#1E3A5F';
    final rgb = int.parse(hex.substring(1), radix: 16);
    _red = (rgb >> 16) & 0xFF;
    _green = (rgb >> 8) & 0xFF;
    _blue = rgb & 0xFF;
    _hex = TextEditingController(text: _currentHex);
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  String get _currentHex {
    String pair(int channel) =>
        channel.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#${pair(_red)}${pair(_green)}${pair(_blue)}';
  }

  void _setChannels(int red, int green, int blue) {
    setState(() {
      _red = red;
      _green = green;
      _blue = blue;
      _hex.text = _currentHex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = Color.fromARGB(255, _red, _green, _blue);
    return AlertDialog(
      title: Text(widget.label),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 48,
              width: double.infinity,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hex,
              decoration: SetupUi.input('Hex value'),
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              onChanged: (value) {
                if (!isValidBrandHex(value)) return;
                final rgb = int.parse(
                  normalizeBrandHex(value).substring(1),
                  radix: 16,
                );
                setState(() {
                  _red = (rgb >> 16) & 0xFF;
                  _green = (rgb >> 8) & 0xFF;
                  _blue = rgb & 0xFF;
                });
              },
            ),
            _channelSlider('Red', _red, (value) {
              _setChannels(value.round(), _green, _blue);
            }),
            _channelSlider('Green', _green, (value) {
              _setChannels(_red, value.round(), _blue);
            }),
            _channelSlider('Blue', _blue, (value) {
              _setChannels(_red, _green, value.round());
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: isValidBrandHex(_hex.text)
              ? () => Navigator.pop(context, normalizeBrandHex(_hex.text))
              : null,
          child: const Text('Use color'),
        ),
      ],
    );
  }

  Widget _channelSlider(String label, int value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            max: 255,
            label: '$value',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
