import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/domain/entities/employee_portal.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:flutter/material.dart';

/// Minimalist employee-facing business details.
/// Never displays business code.
class EmployeeBusinessDetailsScreen extends StatefulWidget {
  const EmployeeBusinessDetailsScreen({super.key, this.profile});

  final EmployeeProfile? profile;

  @override
  State<EmployeeBusinessDetailsScreen> createState() =>
      _EmployeeBusinessDetailsScreenState();
}

class _EmployeeBusinessDetailsScreenState
    extends State<EmployeeBusinessDetailsScreen> {
  EmployeeProfile? _profile;
  EmployeeWorksite? _worksite;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = sl<EmployeeRepository>();
      final profile = widget.profile ?? await repo.getProfile();
      EmployeeWorksite? worksite;
      try {
        worksite = await repo.getWorksite();
      } catch (_) {
        worksite = null;
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _worksite = worksite;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load business details.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = brandPrimary(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Business details',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _buildContent(primary),
      ),
    );
  }

  Widget _buildContent(Color primary) {
    final profile = _profile!;
    final logoUrl = profile.branding?.logoUrl;
    final locationParts = <String>[
      if ((_worksite?.label ?? '').trim().isNotEmpty) _worksite!.label.trim(),
      if ((_worksite?.address ?? '').trim().isNotEmpty)
        _worksite!.address.trim(),
    ];
    final location = locationParts.join('\n');

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 40),
      children: [
        Center(
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            clipBehavior: Clip.antiAlias,
            child: logoUrl != null && logoUrl.trim().isNotEmpty
                ? BusinessLogo(logoUrl: logoUrl, height: 112, width: 112)
                : Icon(Icons.apartment_rounded, size: 44, color: primary),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          profile.businessName.trim().isEmpty
              ? 'Business'
              : profile.businessName.trim(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: EmployeeColors.textPrimary,
          ),
        ),
        if ((profile.businessType ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            profile.businessType!.trim(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: EmployeeColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 36),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        const SizedBox(height: 28),
        _InfoBlock(
          label: 'Business owner',
          value: (profile.ownerName ?? '').trim().isEmpty
              ? 'Not available'
              : profile.ownerName!.trim(),
        ),
        const SizedBox(height: 22),
        _InfoBlock(
          label: 'Email',
          value: (profile.ownerEmail ?? '').trim().isEmpty
              ? 'Not available'
              : profile.ownerEmail!.trim(),
        ),
        const SizedBox(height: 22),
        _InfoBlock(
          label: 'Location',
          value: location.isEmpty ? 'Not available' : location,
        ),
      ],
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: EmployeeColors.textMuted,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w600,
            color: EmployeeColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
