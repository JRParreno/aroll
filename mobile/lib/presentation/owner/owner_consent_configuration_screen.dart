import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/data/repositories/owner_repository.dart';
import 'package:aroll_mobile/presentation/owner/owner_shell.dart';
import 'package:aroll_mobile/presentation/owner/setup/setup_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:aroll_mobile/presentation/shared/confirm_action_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class OwnerConsentConfigurationScreen extends StatefulWidget {
  const OwnerConsentConfigurationScreen({super.key});

  @override
  State<OwnerConsentConfigurationScreen> createState() =>
      _OwnerConsentConfigurationScreenState();
}

class _OwnerConsentConfigurationScreenState
    extends State<OwnerConsentConfigurationScreen> {
  final _repo = sl<OwnerRepository>();
  late Future<_ConsentConfigData> _future;
  bool _useCustom = false;
  bool _savingToggle = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ConsentConfigData> _load() async {
    final legal = await _repo.businessLegalSettings();
    final catalog = await _repo.consentCatalog();
    final useCustom = legal['use_custom_consents'] == true;
    _useCustom = useCustom;
    const coreTypes = {'terms', 'privacy', 'biometric'};
    final docs = (catalog['documents'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => coreTypes.contains('${item['consent_type'] ?? ''}'))
        .toList()
      ..sort((a, b) {
        final ap = (a['position'] as num?)?.toInt() ?? 0;
        final bp = (b['position'] as num?)?.toInt() ?? 0;
        return ap.compareTo(bp);
      });
    return _ConsentConfigData(
      useCustomConsents: useCustom,
      canEdit: catalog['can_edit'] == true,
      documents: docs,
    );
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _saveToggle() async {
    if (_savingToggle) return;
    setState(() => _savingToggle = true);
    try {
      await _repo.updateBusinessLegalSettings({
        'use_custom_consents': _useCustom,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Consent settings saved')),
      );
      await _reload();
    } on DioException catch (error) {
      if (!mounted) return;
      _showError(error, fallback: 'Could not save consent settings.');
    } finally {
      if (mounted) setState(() => _savingToggle = false);
    }
  }

  void _showError(DioException error, {required String fallback}) {
    final detail = error.response?.data is Map
        ? (error.response?.data as Map)['detail']
        : null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(detail is String ? detail : fallback)),
    );
  }

  Future<void> _openEditor({Map<String, dynamic>? document}) async {
    final titleController = TextEditingController(
      text: '${document?['title'] ?? ''}',
    );
    final bodyController = TextEditingController(
      text: '${document?['body_text'] ?? ''}',
    );
    var consentType = '${document?['consent_type'] ?? 'terms'}';
    if (consentType != 'terms' &&
        consentType != 'privacy' &&
        consentType != 'biometric') {
      consentType = 'terms';
    }
    var isRequired = document?['is_required'] != false;
    var isActive = document?['is_active'] != false;
    final isNew = document == null;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isNew ? 'Add consent' : 'Edit consent'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: 10),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Type'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: consentType,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'terms',
                              child: Text('Terms and Conditions'),
                            ),
                            DropdownMenuItem(
                              value: 'privacy',
                              child: Text('Privacy Policy'),
                            ),
                            DropdownMenuItem(
                              value: 'biometric',
                              child: Text('Biometric Consent'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() => consentType = value);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: bodyController,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(labelText: 'Body text'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Required'),
                      value: isRequired,
                      onChanged: (value) =>
                          setDialogState(() => isRequired = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: isActive,
                      onChanged: (value) =>
                          setDialogState(() => isActive = value),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(isNew ? 'Create' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;
    final title = titleController.text.trim();
    if (title.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title is required.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final payload = {
        'title': title,
        'body_text': bodyController.text,
        'consent_type': consentType,
        'is_required': isRequired,
        'is_active': isActive,
      };
      if (isNew) {
        await _repo.createConsentDocument(payload);
      } else {
        await _repo.updateConsentDocument('${document['id']}', payload);
      }
      if (!mounted) return;
      await _reload();
    } on DioException catch (error) {
      if (!mounted) return;
      _showError(error, fallback: 'Could not save consent document.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteDocument(Map<String, dynamic> document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmActionDialog(
        icon: Icons.delete_outline_rounded,
        title: 'Delete consent',
        message: 'Delete “${document['title']}”?',
        confirmLabel: 'Delete',
        iconColor: AppColors.danger,
        iconBackground: const Color(0xFFFEE2E2),
        confirmColor: const Color(0xFFB91C1C),
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _repo.deleteConsentDocument('${document['id']}');
      if (!mounted) return;
      await _reload();
    } on DioException catch (error) {
      if (!mounted) return;
      _showError(error, fallback: 'Could not delete consent document.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move(
    List<Map<String, dynamic>> documents,
    int index,
    int direction,
  ) async {
    final next = index + direction;
    if (next < 0 || next >= documents.length) return;
    final ordered = [...documents];
    final item = ordered.removeAt(index);
    ordered.insert(next, item);
    setState(() => _busy = true);
    try {
      await _repo.reorderConsentDocuments(
        ordered.map((doc) => '${doc['id']}').toList(),
      );
      if (!mounted) return;
      await _reload();
    } on DioException catch (error) {
      if (!mounted) return;
      _showError(error, fallback: 'Could not reorder consents.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OwnerShell(
      selectedIndex: 2,
      showBackButton: true,
      title: 'Consent Configuration',
      backgroundColor: SetupUi.scaffold,
      child: FutureBuilder<_ConsentConfigData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(color: SetupUi.navyOf(context)),
            );
          }
          if (snapshot.hasError && !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Unable to load consent configuration.',
                      style: appMutedStyle(),
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: () => setState(() => _future = _load()),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final canEdit = data.canEdit && _useCustom;

          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Workplace consents',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: SetupUi.navyOf(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Employees always load consents from the API. This '
                          'workplace uses Aroll+ Admin defaults unless you '
                          'enable custom workplace consents.',
                          style: appMutedStyle().copyWith(fontSize: 12.5),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Use custom workplace consents',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          value: _useCustom,
                          onChanged: _savingToggle
                              ? null
                              : (value) => setState(() => _useCustom = value),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton(
                            onPressed: _savingToggle ? null : _saveToggle,
                            child: Text(
                              _savingToggle ? 'Saving…' : 'Save consent toggle',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!canEdit)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _useCustom
                            ? 'Custom mode is on, but editing is unavailable.'
                            : 'Admin defaults apply. Turn on custom workplace '
                                'consents to upload or edit documents for this '
                                'workplace only.',
                        style: appMutedStyle().copyWith(fontSize: 12.5),
                      ),
                    ),
                  if (canEdit)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _openEditor(),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add consent'),
                      ),
                    ),
                  if (canEdit) const SizedBox(height: 8),
                  if (data.documents.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Text(
                        'No consent documents yet.',
                        style: appMutedStyle(),
                      ),
                    )
                  else
                    ...List.generate(data.documents.length, (index) {
                      final doc = data.documents[index];
                      final required = doc['is_required'] == true;
                      final published = doc['published'] == true;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${doc['title'] ?? 'Consent'}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: SetupUi.navyOf(context),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${doc['consent_type'] ?? 'custom'} · '
                                      '${doc['version'] ?? '—'} · '
                                      '${required ? 'Required' : 'Optional'} · '
                                      '${published ? 'Published' : 'Unpublished'}',
                                      style: appMutedStyle()
                                          .copyWith(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              if (canEdit) ...[
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _busy || index == 0
                                      ? null
                                      : () => _move(data.documents, index, -1),
                                  icon: const Icon(Icons.arrow_upward_rounded),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _busy ||
                                          index >= data.documents.length - 1
                                      ? null
                                      : () => _move(data.documents, index, 1),
                                  icon:
                                      const Icon(Icons.arrow_downward_rounded),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed:
                                      _busy ? null : () => _openEditor(document: doc),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed:
                                      _busy ? null : () => _deleteDocument(doc),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
              if (_busy)
                Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x33FFFFFF),
                    child: Center(
                      child: CircularProgressIndicator(color: SetupUi.navyOf(context)),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ConsentConfigData {
  const _ConsentConfigData({
    required this.useCustomConsents,
    required this.canEdit,
    required this.documents,
  });

  final bool useCustomConsents;
  final bool canEdit;
  final List<Map<String, dynamic>> documents;
}
