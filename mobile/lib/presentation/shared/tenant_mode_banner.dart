import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/tenant_mode.dart';
import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:flutter/material.dart';

class TenantModeBanner extends StatelessWidget {
  const TenantModeBanner({super.key, this.session});

  final UserSession? session;

  @override
  Widget build(BuildContext context) {
    final current = session ?? sl<AppState>().session;
    if (current == null) return const SizedBox.shrink();
    if (current.isDemo) {
      return _Banner(
        color: const Color(0xFFFFFBEB),
        border: const Color(0xFFFDE68A),
        title: TenantModeCopy.demoTitle,
        subtitle: current.businessName.isEmpty
            ? TenantModeCopy.demoBusinessFallback
            : current.businessName,
        body: TenantModeCopy.demoBody,
        titleColor: const Color(0xFF78350F),
      );
    }
    if (current.isInternalTest) {
      return _Banner(
        color: const Color(0xFFF0F9FF),
        border: const Color(0xFFBAE6FD),
        title: TenantModeCopy.devTestTitle,
        subtitle: current.businessName.isEmpty
            ? TenantModeCopy.devTestBusinessFallback
            : current.businessName,
        body: TenantModeCopy.devTestBody,
        titleColor: const Color(0xFF0C4A6E),
      );
    }
    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.border,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.titleColor,
  });

  final Color color;
  final Color border;
  final String title;
  final String subtitle;
  final String body;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            body,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: titleColor.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class SimulatedChip extends StatelessWidget {
  const SimulatedChip({super.key, this.label = TenantModeCopy.simulated});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: Color(0xFF78350F),
        ),
      ),
    );
  }
}

class PrototypeNoticeCard extends StatelessWidget {
  const PrototypeNoticeCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            TenantModeCopy.prototypeTitle,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF78350F),
            ),
          ),
          SizedBox(height: 6),
          Text(
            TenantModeCopy.prototypeBody,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Color(0xFF92400E),
            ),
          ),
        ],
      ),
    );
  }
}

class PayslipSampleBanner extends StatelessWidget {
  const PayslipSampleBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: const Column(
        children: [
          Text(
            TenantModeCopy.payslipSample1,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.4,
              color: Color(0xFF9A3412),
            ),
          ),
          SizedBox(height: 2),
          Text(
            TenantModeCopy.payslipSample2,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: Color(0xFFC2410C),
            ),
          ),
        ],
      ),
    );
  }
}
