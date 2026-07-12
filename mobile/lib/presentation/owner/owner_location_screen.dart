import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:flutter/material.dart';

class OwnerLocationScreen extends StatelessWidget {
  const OwnerLocationScreen({super.key});

  @override
  Widget build(BuildContext context) => OwnerSecondaryScreen(
        title: 'Business Location',
        future: sl<OwnerRepository>().location(),
        builder: (data) => [
          OwnerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_rounded,
                    size: 42, color: Color(0xFF1E466E)),
                const SizedBox(height: 12),
                Text('${data['label'] ?? 'Primary workplace'}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const SizedBox(height: 6),
                Text('${data['address'] ?? 'No location configured'}'),
                const SizedBox(height: 12),
                Text('Geofence radius: ${data['geofence_radius_m'] ?? 0} m'),
                Text(
                  'Coordinates: ${data['latitude'] ?? '--'}, '
                  '${data['longitude'] ?? '--'}',
                ),
              ],
            ),
          ),
        ],
      );
}
