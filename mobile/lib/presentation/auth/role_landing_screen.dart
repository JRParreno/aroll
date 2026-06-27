import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RoleLandingScreen extends StatelessWidget {
  const RoleLandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E466E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Image.asset('assets/branding/logo.png', height: 150),
              const SizedBox(height: 28),
              const Text(
                'One workspace for every workday.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Choose how you want to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFC8D8E7), fontSize: 14),
              ),
              const Spacer(),
              _RoleButton(
                icon: Icons.badge_outlined,
                label: 'Login as Employee',
                onTap: () => context.go('/login/employee'),
              ),
              const SizedBox(height: 12),
              _RoleButton(
                icon: Icons.business_center_outlined,
                label: 'Login as Business Owner',
                filled: false,
                onTap: () => context.go('/login/owner-options'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OwnerOptionsScreen extends StatelessWidget {
  const OwnerOptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(title: const Text('Business Owner')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.storefront_rounded,
                size: 72, color: Color(0xFF1E466E)),
            const SizedBox(height: 20),
            Text(
              'Manage your business from anywhere',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 30),
            _OptionCard(
              icon: Icons.login_rounded,
              title: 'Sign In',
              subtitle: 'Use your business code and owner account.',
              onTap: () => context.go('/login/owner'),
            ),
            _OptionCard(
              icon: Icons.add_business_rounded,
              title: 'Register Business',
              subtitle: 'Submit your business details and requirements.',
              onTap: () => context.go('/register-business'),
            ),
            _OptionCard(
              icon: Icons.manage_search_rounded,
              title: 'Track Registration Status',
              subtitle: 'Check an existing application using your email.',
              onTap: () => context.go('/track-registration'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  const _RoleButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: filled
          ? FilledButton.icon(
              onPressed: onTap, icon: Icon(icon), label: Text(label))
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              onPressed: onTap,
              icon: Icon(icon),
              label: Text(label),
            ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ListTile(
        contentPadding: const EdgeInsets.all(18),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE7EEF5),
          child: Icon(icon, color: const Color(0xFF1E466E)),
        ),
        title:
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
