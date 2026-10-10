import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';

/// Shared confirmation dialog shell for Sign Out / Time Out style prompts.
/// Visual only — callers own showDialog + result handling.
class ConfirmActionDialog extends StatelessWidget {
  const ConfirmActionDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.messageSecondary,
    this.messageSecondaryStyle,
    this.messageTextAlign = TextAlign.left,
    this.cancelLabel = 'Cancel',
    this.iconColor,
    this.iconBackground,
    this.confirmColor,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? messageSecondary;
  /// When set, overrides the default secondary (warning) text style.
  final TextStyle? messageSecondaryStyle;
  final TextAlign messageTextAlign;
  final String cancelLabel;
  final String confirmLabel;
  final Color? iconColor;
  final Color? iconBackground;
  final Color? confirmColor;

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final wellBg = iconBackground ?? brand.toneWell;
    final wellFg = iconColor ?? brand.toneButton;
    final maxBodyHeight = MediaQuery.sizeOf(context).height * 0.45;

    return Dialog(
      backgroundColor: AppColors.white,
      elevation: 6,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sheet),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: wellBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 26, color: wellFg),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxBodyHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      message,
                      textAlign: messageTextAlign,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMuted,
                        height: 1.45,
                      ),
                    ),
                    if (messageSecondary != null) ...[
                      SizedBox(height: messageSecondaryStyle != null ? 8 : 10),
                      Text(
                        messageSecondary!,
                        textAlign: messageTextAlign,
                        style: messageSecondaryStyle ??
                            const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFB91C1C),
                              height: 1.4,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: AppSizes.buttonHeight,
                    child: OutlinedButton(
                      style: appSecondaryButtonStyle(),
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(cancelLabel),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: AppSizes.buttonHeight,
                    child: FilledButton(
                      style: appPrimaryButtonStyle(
                        background: confirmColor ?? brand.toneButton,
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        confirmLabel,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
