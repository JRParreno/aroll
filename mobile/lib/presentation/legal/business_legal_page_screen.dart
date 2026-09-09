import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/network/api_client.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class BusinessLegalPageScreen extends StatefulWidget {
  const BusinessLegalPageScreen({super.key, required this.businessCode});

  final String businessCode;

  @override
  State<BusinessLegalPageScreen> createState() => _BusinessLegalPageScreenState();
}

class _BusinessLegalPageScreenState extends State<BusinessLegalPageScreen> {
  String? _title;
  String? _content;
  String? _pageUrl;
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
      final code = widget.businessCode.trim().toUpperCase();
      final res = await sl<ApiClient>().dio.get<Map<String, dynamic>>(
        '/public/legal/$code',
      );
      final data = res.data ?? const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _title = data['business_name'] as String? ?? code;
        _content = data['content'] as String? ?? '';
        _pageUrl =
            '${sl<ApiClient>().dio.options.baseUrl}/public/legal/$code/page';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load this workplace consent page.';
      });
    }
  }

  Future<void> _openWebpage() async {
    final raw = _pageUrl;
    if (raw == null) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text(
          'Workplace consent',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: appMutedStyle(), textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    Text(_title ?? 'Workplace consent', style: appPageTitleStyle()),
                    const SizedBox(height: 8),
                    Text(
                      'This page is configured by the business. Opening it does not record agreement.',
                      style: appMutedStyle(),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: appCardDecoration(),
                      child: Text(
                        _content ?? '',
                        style: appBodyStyle().copyWith(height: 1.55),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _openWebpage,
                      child: const Text('Open consent webpage'),
                    ),
                  ],
                ),
    );
  }
}
