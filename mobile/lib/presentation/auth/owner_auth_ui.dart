import 'package:aroll_mobile/presentation/auth/password_visibility.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract final class OwnerAuthColors {
  static const background = Color(0xFFF4F6F8);
  static const primary = Color(0xFF1E3A5F);
  static const primaryDark = Color(0xFF284B73);
  static const accentSurface = Color(0xFFEAF2FB);
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF1F2937);
  static const textMuted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
  static const success = Color(0xFF15803D);
  static const warning = Color(0xFFC2410C);
  static const danger = Color(0xFFB91C1C);
}

void ownerAuthBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/login/owner-options');
  }
}

class OwnerAuthScaffold extends StatelessWidget {
  const OwnerAuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.badgeLabel,
  });

  final String title;
  final String? subtitle;
  final String? badgeLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OwnerAuthColors.background,
      appBar: AppBar(
        backgroundColor: OwnerAuthColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => ownerAuthBack(context),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: OwnerAuthColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            if (badgeLabel != null) ...[
              OwnerAuthBadge(label: badgeLabel!),
              const SizedBox(height: 14),
            ],
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: OwnerAuthColors.textPrimary,
                    height: 1.15,
                  ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: const TextStyle(
                  color: OwnerAuthColors.textMuted,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 22),
            child,
          ],
        ),
      ),
    );
  }
}

class OwnerAuthBadge extends StatelessWidget {
  const OwnerAuthBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: OwnerAuthColors.accentSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.verified_outlined,
            size: 16,
            color: OwnerAuthColors.primary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: OwnerAuthColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class OwnerAuthCard extends StatelessWidget {
  const OwnerAuthCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class OwnerAuthField extends StatefulWidget {
  const OwnerAuthField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.keyboardType,
    this.obscureText = false,
    this.maxLines = 1,
    this.textInputAction,
    this.onSubmitted,
    this.prefixIcon,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int maxLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;

  @override
  State<OwnerAuthField> createState() => _OwnerAuthFieldState();
}

class _OwnerAuthFieldState extends State<OwnerAuthField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final obscure = widget.obscureText && !_visible;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: const TextStyle(
              color: OwnerAuthColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: widget.controller,
            keyboardType: widget.keyboardType,
            obscureText: obscure,
            maxLines: widget.maxLines,
            textInputAction: widget.textInputAction,
            onSubmitted: widget.onSubmitted,
            autocorrect: false,
            enableSuggestions: !widget.obscureText,
            style: const TextStyle(
              color: OwnerAuthColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
              filled: true,
              fillColor: Colors.white,
              prefixIcon: widget.prefixIcon == null
                  ? null
                  : Icon(
                      widget.prefixIcon,
                      size: 18,
                      color: const Color(0xFF9CA3AF),
                    ),
              suffixIcon: widget.obscureText
                  ? PasswordVisibilityToggle(
                      visible: _visible,
                      onToggle: () => setState(() => _visible = !_visible),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: OwnerAuthColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: OwnerAuthColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: OwnerAuthColors.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OwnerAuthPrimaryButton extends StatelessWidget {
  const OwnerAuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: OwnerAuthColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: OwnerAuthColors.primary.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 8),
                    Icon(icon, size: 18),
                  ],
                ],
              ),
      ),
    );
  }
}

class OwnerAuthTextLink extends StatelessWidget {
  const OwnerAuthTextLink({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: OwnerAuthColors.primary,
        padding: const EdgeInsets.symmetric(vertical: 8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class OwnerAuthSectionTitle extends StatelessWidget {
  const OwnerAuthSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: OwnerAuthColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                color: OwnerAuthColors.textMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class OwnerAuthDocumentTile extends StatelessWidget {
  const OwnerAuthDocumentTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.uploaded,
    required this.onTap,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final bool uploaded;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: uploaded
                    ? const Color(0xFFBBF7D0)
                    : OwnerAuthColors.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: OwnerAuthColors.accentSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    uploaded
                        ? Icons.check_circle_rounded
                        : Icons.upload_file_rounded,
                    color: uploaded
                        ? OwnerAuthColors.success
                        : OwnerAuthColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: OwnerAuthColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: OwnerAuthColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: OwnerAuthColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OwnerAuthStatusCard extends StatelessWidget {
  const OwnerAuthStatusCard({
    super.key,
    required this.title,
    required this.rows,
  });

  final String title;
  final List<(String label, String value)> rows;

  @override
  Widget build(BuildContext context) {
    return OwnerAuthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: OwnerAuthColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 118,
                    child: Text(
                      row.$1,
                      style: const TextStyle(
                        color: OwnerAuthColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$2,
                      style: const TextStyle(
                        color: OwnerAuthColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
