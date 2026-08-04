import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';

/// Read-only labeled rows in the shared settings / setup card style.
/// Skips empty values when [skipEmpty] is true (default).
class OwnerInfoSection extends StatelessWidget {
  const OwnerInfoSection({
    super.key,
    required this.title,
    required this.rows,
    this.icon,
    this.subtitle,
    this.skipEmpty = true,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final String title;
  final List<(String label, Object? value)> rows;
  final IconData? icon;
  final String? subtitle;
  final bool skipEmpty;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final visible = rows.where((row) {
      if (!skipEmpty) return true;
      final text = _displayValue(row.$2);
      return text != null;
    }).toList();

    if (visible.isEmpty) return const SizedBox.shrink();

    return SetupSurfaceCard(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.iconWell,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: SetupUi.navy),
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
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
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
          const SizedBox(height: 12),
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0xFFE8EEF4)),
              const SizedBox(height: 8),
            ],
            _InfoRow(
              label: visible[i].$1,
              value: _displayValue(visible[i].$2) ?? 'Not set',
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final multiline = value.contains('\n');
    if (multiline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: appMutedStyle().copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: appMutedStyle().copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

String? _displayValue(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') return null;
  return text;
}

String ownerRoleLabel(String? role) {
  switch ((role ?? '').toLowerCase()) {
    case 'owner':
      return 'Business Owner';
    case 'manager':
      return 'Manager';
    default:
      return role == null || role.isEmpty
          ? 'Business Owner'
          : ownerFormatKey(role);
  }
}

String ownerPayFrequencyLabel(Object? payPeriodType) {
  switch ('$payPeriodType') {
    case 'weekly':
      return 'Weekly';
    case 'semi_monthly':
      return 'Twice a month';
    case 'monthly':
      return 'Monthly';
    default:
      final text = _displayValue(payPeriodType);
      return text == null ? 'Not set' : ownerFormatKey(text);
  }
}

String ownerStatusLabel(Object? status) {
  final text = _displayValue(status);
  if (text == null) return 'Not set';
  return ownerFormatKey(text);
}
