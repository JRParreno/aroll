import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';

/// Shared visual language for Owner Business Setup (UI only).
abstract final class SetupUi {
  static const navy = AppColors.primaryDark;
  static const navySoft = AppColors.primary;
  static const scaffold = AppColors.scaffold;
  static const cardRadius = 18.0;
  static const panelRadius = 14.0;
  static const fieldRadius = 12.0;
  static const sectionGap = 12.0;
  static const fieldGap = 10.0;

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  static InputDecoration input(String label, {String? hint}) {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: AppColors.fieldFill,
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
      ),
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: const BorderSide(color: navySoft, width: 1.4),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
    );
  }

  static ButtonStyle get primaryButton => FilledButton.styleFrom(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        disabledBackgroundColor: navy.withValues(alpha: 0.45),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      );

  static ButtonStyle get secondaryButton => OutlinedButton.styleFrom(
        foregroundColor: navy,
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFD7E0EA)),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      );

  static ButtonStyle get ghostButton => TextButton.styleFrom(
        foregroundColor: navySoft,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );
}

class SetupSurfaceCard extends StatelessWidget {
  const SetupSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(SetupUi.cardRadius),
        border: Border.all(color: AppColors.border),
        boxShadow: SetupUi.cardShadow,
      ),
      child: child,
    );
  }
}

class SetupPanel extends StatelessWidget {
  const SetupPanel({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.subtitle,
  });

  final String title;
  final List<Widget> children;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(SetupUi.panelRadius),
        border: Border.all(color: const Color(0xFFE8EEF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.iconWell,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: SetupUi.navy),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: appMutedStyle().copyWith(fontSize: 11.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class SetupInfoBanner extends StatelessWidget {
  const SetupInfoBanner(
    this.text, {
    super.key,
    this.tone = SetupBannerTone.neutral,
  });

  final String text;
  final SetupBannerTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = switch (tone) {
      SetupBannerTone.neutral => (
          bg: const Color(0xFFF3F6FA),
          border: const Color(0xFFD7E0EA),
          fg: AppColors.textMuted,
          icon: Icons.info_outline_rounded,
        ),
      SetupBannerTone.warning => (
          bg: const Color(0xFFFFFBEB),
          border: const Color(0xFFFDE68A),
          fg: const Color(0xFF92400E),
          icon: Icons.warning_amber_rounded,
        ),
      SetupBannerTone.danger => (
          bg: const Color(0xFFFEF2F2),
          border: const Color(0xFFFECACA),
          fg: const Color(0xFFB91C1C),
          icon: Icons.error_outline_rounded,
        ),
      SetupBannerTone.success => (
          bg: const Color(0xFFECFDF5),
          border: const Color(0xFFA7F3D0),
          fg: const Color(0xFF065F46),
          icon: Icons.check_circle_outline_rounded,
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(colors.icon, size: 18, color: colors.fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: colors.fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum SetupBannerTone { neutral, warning, danger, success }

class SetupListTileCard extends StatelessWidget {
  const SetupListTileCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon = Icons.check_circle_outline_rounded,
    this.iconColor,
    this.iconBackground,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData leadingIcon;
  final Color? iconColor;
  final Color? iconBackground;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final resolvedIconColor = iconColor ?? SetupUi.navy;
    return SetupSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        onTap: onTap,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconBackground ?? AppColors.iconWell,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(leadingIcon, size: 18, color: resolvedIconColor),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: appMutedStyle().copyWith(fontSize: 11.5),
              ),
        trailing: trailing,
      ),
    );
  }
}

class SetupListLabel extends StatelessWidget {
  const SetupListLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class SetupMenuCard extends StatelessWidget {
  const SetupMenuCard({
    super.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.complete = false,
    this.showStatus = true,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool complete;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(SetupUi.cardRadius),
        onTap: onTap,
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(SetupUi.cardRadius),
            border: Border.all(
              color: complete
                  ? const Color(0xFFBBF7D0)
                  : AppColors.border,
            ),
            boxShadow: SetupUi.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: complete
                      ? const Color(0xFFECFDF5)
                      : AppColors.iconWell,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: complete ? const Color(0xFF059669) : SetupUi.navy,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: appMutedStyle().copyWith(
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    if (showStatus) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: complete
                              ? const Color(0xFFECFDF5)
                              : const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          complete ? 'Completed' : 'Needs setup',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: complete
                                ? const Color(0xFF047857)
                                : const Color(0xFFC2410C),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                complete
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                size: 22,
                color: complete
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SetupSectionHeader extends StatelessWidget {
  const SetupSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.iconWell,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: SetupUi.navy),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: appMutedStyle().copyWith(fontSize: 12.5, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class SetupCompactSwitch extends StatelessWidget {
  const SetupCompactSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: VisualDensity.compact,
      activeThumbColor: SetupUi.navy,
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: appMutedStyle().copyWith(fontSize: 11.5),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}
