import 'package:aroll_mobile/domain/entities/user_session.dart';
import 'package:aroll_mobile/presentation/attendance/attendance_screen.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.session});

  final UserSession session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(session.businessName),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(session.fullName),
              subtitle: Text('Role: ${session.role}'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Quick actions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Attendance history'),
            subtitle: const Text('Paginated list — sample BLoC'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AttendanceScreen(),
                ),
              );
            },
          ),
          const ListTile(
            leading: Icon(Icons.face),
            title: Text('Clock in (face)'),
            subtitle: Text('Not implemented in sample'),
            enabled: false,
          ),
        ],
      ),
    );
  }
}
