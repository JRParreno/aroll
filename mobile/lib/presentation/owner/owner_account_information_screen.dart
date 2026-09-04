import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_info_display.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:flutter/material.dart';

class OwnerAccountInformationScreen extends StatelessWidget {
  const OwnerAccountInformationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return OwnerSecondaryScreen(
      selectedIndex: 2,
      title: 'Account Information',
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

        final ownerName = account['owner_name'] ?? business['owner_name'];
        final email = account['email'] ?? business['owner_email'];
        final phone = account['contact_phone'] ?? business['owner_phone'];

        return [
          const SizedBox(height: 14),
          OwnerInfoSection(
            title: 'Owner Information',
            icon: Icons.person_outline_rounded,
            skipEmpty: false,
            rows: [
              ('Name', ownerName),
              ('Email', email),
              ('Mobile Number', phone),
            ],
          ),
          OwnerInfoSection(
            title: 'Business Information',
            icon: Icons.storefront_outlined,
            skipEmpty: false,
            rows: [
              ('Business Name', business['business_name']),
              ('Business Type', business['business_type']),
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
