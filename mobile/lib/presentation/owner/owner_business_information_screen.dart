import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_info_display.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:flutter/material.dart';

class OwnerBusinessInformationScreen extends StatelessWidget {
  const OwnerBusinessInformationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return OwnerSecondaryScreen(
      selectedIndex: 2,
      title: 'Business Information',
      backgroundColor: SetupUi.scaffold,
      future: Future.wait([
        sl<OwnerRepository>().accountSettings(),
        sl<OwnerRepository>().businessSettings(),
        sl<OwnerRepository>().payrollConfig(),
      ]),
      builder: (data) {
        final values = data as List<Map<String, dynamic>>;
        final account = values[0];
        final business = values[1];
        final payroll = values[2];

        return [
          const SetupSurfaceCard(
            child: SetupSectionHeader(
              icon: Icons.business_rounded,
              title: 'Business Information',
              subtitle: 'Your registered business profile and pay preferences.',
            ),
          ),
          const SizedBox(height: 14),
          OwnerInfoSection(
            title: 'Business Details',
            icon: Icons.storefront_outlined,
            skipEmpty: false,
            rows: [
              ('Business Name', business['business_name']),
              ('Business Type', business['business_type']),
              ('Business Code', business['business_code']),
              ('Address', business['address'] ?? account['address']),
              (
                'Payroll Frequency',
                ownerPayFrequencyLabel(payroll['pay_period_type']),
              ),
              (
                'Business Status',
                ownerStatusLabel(business['application_status']),
              ),
            ],
          ),
        ];
      },
    );
  }
}
