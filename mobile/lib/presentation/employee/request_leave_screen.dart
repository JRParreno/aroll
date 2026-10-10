import 'dart:convert';
import 'dart:io';

import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:aroll_mobile/domain/entities/leave_request.dart';
import 'package:aroll_mobile/domain/repositories/employee_repository.dart';
import 'package:aroll_mobile/presentation/employee/employee_ui.dart';
import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class RequestLeaveScreen extends StatefulWidget {
  const RequestLeaveScreen({super.key, this.requestId});

  final String? requestId;

  bool get isEditMode => requestId != null && requestId!.isNotEmpty;

  @override
  State<RequestLeaveScreen> createState() => _RequestLeaveScreenState();
}

class _RequestLeaveScreenState extends State<RequestLeaveScreen> {
  final _repo = sl<EmployeeRepository>();
  final _reason = TextEditingController();
  final _otherSpec = TextEditingController();
  String _leaveType = 'sick';
  DateTime? _start;
  DateTime? _end;
  String? _documentDataUrl;
  String? _documentName;
  bool _submitting = false;
  bool _loading = false;
  bool _hasExistingDocument = false;
  LeaveRequestPreview? _preview;
  Set<String> _blockedTypes = {};
  List<LeaveBalanceItem> _balanceItems = const [];

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode) {
      _loadExisting();
    }
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    try {
      final years = <int>{};
      if (_start != null) years.add(_start!.year);
      if (_end != null) years.add(_end!.year);
      final balances = years.isEmpty
          ? [await _repo.getLeaveBalances()]
          : [
              for (final year in years.toList()..sort())
                await _repo.getLeaveBalances(year: year),
            ];
      if (!mounted) return;
      final blocked = <String>{};
      for (final balance in balances) {
        for (final item in balance.items) {
          if (item.disabled || !item.configured) blocked.add(item.leaveType);
        }
      }
      setState(() {
        _blockedTypes = blocked;
        _balanceItems = balances.first.items;
        if (!widget.isEditMode && blocked.contains(_leaveType)) {
          final next = leaveTypeOptions
              .where(
                (option) =>
                    option.$1 != 'unpaid' && !blocked.contains(option.$1),
              )
              .toList();
          if (next.isNotEmpty) _leaveType = next.first.$1;
        }
      });
    } catch (_) {
      // The request screen still lists types; the server rejects disabled ones.
    }
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    try {
      final item = await _repo.getLeaveRequest(widget.requestId!);
      if (!mounted) return;
      setState(() {
        _leaveType = item.leaveType;
        _start = DateTime(
          item.startDate.year,
          item.startDate.month,
          item.startDate.day,
        );
        _end = DateTime(
          item.endDate.year,
          item.endDate.month,
          item.endDate.day,
        );
        _reason.text = item.reason;
        _otherSpec.text = item.otherLeaveSpecification ?? '';
        _hasExistingDocument = item.hasSupportingDocument;
      });
      await _refreshPreview();
    } on DioException catch (error) {
      if (!mounted) return;
      _showError(error, fallback: 'Could not load leave request.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    _otherSpec.dispose();
    super.dispose();
  }

  int get _leaveDays {
    if (_start == null || _end == null) return 0;
    if (_end!.isBefore(_start!)) return 0;
    return _end!.difference(_start!).inDays + 1;
  }

  LeaveBalanceItem? get _selectedBalance {
    for (final item in _balanceItems) {
      if (item.leaveType == _leaveType) return item;
    }
    return null;
  }

  String? get _specificationPayload =>
      _leaveType == 'other' ? _otherSpec.text.trim() : null;

  List<(String, String)> get _typeOptions {
    final options = leaveTypeOptions
        .where((option) => option.$1 != 'unpaid')
        .toList();
    if (widget.isEditMode && _leaveType == 'unpaid') {
      options.add(('unpaid', 'Unpaid Leave'));
    }
    return options;
  }

  bool get _ready =>
      _start != null &&
      _end != null &&
      !_end!.isBefore(_start!) &&
      _reason.text.trim().length >= 3 &&
      (_leaveType != 'other' || _otherSpec.text.trim().isNotEmpty);

  Future<void> _pickDate({required bool start}) async {
    final initial = start
        ? (_start ?? DateTime.now())
        : (_end ?? _start ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = DateTime(picked.year, picked.month, picked.day);
        if (_end != null && _end!.isBefore(_start!)) _end = _start;
      } else {
        _end = DateTime(picked.year, picked.month, picked.day);
        if (_start != null && _end!.isBefore(_start!)) _start = _end;
      }
    });
    await _loadAvailability();
    await _refreshPreview();
  }

  Future<void> _refreshPreview() async {
    if (_start == null || _end == null || _end!.isBefore(_start!)) {
      if (mounted) setState(() => _preview = null);
      return;
    }
    try {
      final preview = await _repo.previewLeaveRequest(
        leaveType: _leaveType,
        startDate: _start!,
        endDate: _end!,
      );
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (_) {
      if (mounted) setState(() => _preview = null);
    }
  }

  Future<void> _pickDocument() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null) return;
    final bytes = await File(file.path).readAsBytes();
    final b64 = base64Encode(bytes);
    final mime = file.mimeType ?? 'image/jpeg';
    setState(() {
      _documentDataUrl = 'data:$mime;base64,$b64';
      _documentName = file.name;
      _hasExistingDocument = false;
    });
  }

  String _dioErrorMessage(DioException error, {required String fallback}) {
    final detail = error.response?.data is Map
        ? (error.response?.data as Map)['detail']
        : null;
    if (detail is String) return detail;
    if (detail is Map) {
      return '${detail['message'] ?? fallback}';
    }
    return fallback;
  }

  void _showError(DioException error, {required String fallback}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_dioErrorMessage(error, fallback: fallback))),
    );
  }

  Future<void> _submit() async {
    if (!_ready || _submitting) return;
    setState(() => _submitting = true);
    try {
      if (widget.isEditMode) {
        await _repo.updateLeaveRequest(
          requestId: widget.requestId!,
          leaveType: _leaveType,
          startDate: _start!,
          endDate: _end!,
          reason: _reason.text.trim(),
          otherLeaveSpecification: _specificationPayload,
          supportingDocument: _documentDataUrl,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Leave request updated and sent for approval.'),
          ),
        );
      } else {
        await _repo.createLeaveRequest(
          leaveType: _leaveType,
          startDate: _start!,
          endDate: _end!,
          reason: _reason.text.trim(),
          otherLeaveSpecification: _specificationPayload,
          supportingDocument: _documentDataUrl,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Leave request submitted for approval.')),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on DioException catch (error) {
      if (!mounted) return;
      _showError(
        error,
        fallback: widget.isEditMode
            ? 'Failed to update leave request.'
            : 'Failed to submit leave request.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _fieldDecoration(
    Color focusColor, {
    String? label,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFFAFBFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: EmployeeColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: EmployeeColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: focusColor, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.yMMMd();
    final brand = BrandColors.of(context);
    final soft = Color.lerp(brand.primary, Colors.white, 0.18) ?? brand.primary;
    final isEdit = widget.isEditMode;

    if (_loading) {
      return Scaffold(
        backgroundColor: EmployeeColors.scaffold,
        appBar: AppBar(
          title: Text(isEdit ? 'Edit Leave Request' : 'Request Leave'),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF111827),
          elevation: 0,
        ),
        body: Center(child: CircularProgressIndicator(color: brand.primary)),
      );
    }

    return Scaffold(
      backgroundColor: EmployeeColors.scaffold,
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Leave Request' : 'Request Leave'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            isEdit
                ? 'Update your leave details. Changes to approved leave will need owner approval again.'
                : 'Fill in your leave details. Your owner will review and approve or reject the request.',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: EmployeeColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _FieldLabel('Leave type'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _leaveType,
                  decoration: _fieldDecoration(brand.primary),
                  items: [
                    for (final option in _typeOptions)
                      if (!_blockedTypes.contains(option.$1) ||
                          option.$1 == _leaveType)
                        DropdownMenuItem(
                          value: option.$1,
                          child: Text(option.$2),
                        ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _leaveType = value ?? 'sick';
                      if (_leaveType != 'other') _otherSpec.clear();
                    });
                    _refreshPreview();
                  },
                ),
                if (_selectedBalance != null && _selectedBalance!.configured) ...[
                  const SizedBox(height: 8),
                  Text(
                    _selectedBalance!.remainingDays == 1
                        ? '1 day remaining'
                        : '${_selectedBalance!.remainingDays} days remaining',
                    style: TextStyle(
                      color: brand.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Payroll treatment follows your company Leave Policy.',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                const _FieldLabel('Leave dates'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'Start date',
                        value:
                            _start == null ? 'Select' : dateFmt.format(_start!),
                        onTap: () => _pickDate(start: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DateField(
                        label: 'End date',
                        value: _end == null ? 'Select' : dateFmt.format(_end!),
                        onTap: () => _pickDate(start: false),
                      ),
                    ),
                  ],
                ),
                if (_preview != null) ...[
                  const SizedBox(height: 10),
                  _PreviewNote(preview: _preview!),
                ],
                const SizedBox(height: 12),
                Text(
                  'Leave days: $_leaveDays',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: brand.primary,
                  ),
                ),
                if (_leaveType == 'other') ...[
                  const SizedBox(height: 16),
                  const _FieldLabel(
                    'Please specify the type of leave you want to file',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _otherSpec,
                    maxLength: 200,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _fieldDecoration(brand.primary).copyWith(
                      hintText: 'Bereavement Leave',
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                const SizedBox(height: 16),
                const _FieldLabel('Reason'),
                const SizedBox(height: 8),
                TextField(
                  controller: _reason,
                  minLines: 3,
                  maxLines: 5,
                  onChanged: (_) => setState(() {}),
                  decoration: _fieldDecoration(
                    brand.primary,
                    hint: 'Briefly explain why you need leave',
                  ),
                ),
                const SizedBox(height: 16),
                const _FieldLabel('Supporting document (optional)'),
                const SizedBox(height: 8),
                Material(
                  color: const Color(0xFFFAFBFC),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: _pickDocument,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: EmployeeColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: soft.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _documentName != null || _hasExistingDocument
                                  ? Icons.insert_drive_file_rounded
                                  : Icons.attach_file_rounded,
                              color: brand.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _documentName ??
                                      (_hasExistingDocument
                                          ? 'Document attached'
                                          : 'Attach an image'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: EmployeeColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _documentName != null || _hasExistingDocument
                                      ? 'Tap to replace attachment'
                                      : 'Medical certificate or related photo',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: EmployeeColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: EmployeeColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: appBrandedPrimaryButtonStyle(context),
            onPressed: !_ready || _submitting ? null : _submit,
            child: Text(
              _submitting
                  ? (isEdit ? 'Saving…' : 'Submitting…')
                  : (isEdit ? 'Save Changes' : 'Submit Leave Request'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Color(0xFF6B7280),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFFAFBFC),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: EmployeeColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: EmployeeColors.border),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            const Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: EmployeeColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewNote extends StatelessWidget {
  const _PreviewNote({required this.preview});

  final LeaveRequestPreview preview;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      for (final year in preview.years)
        if (year.disabled)
          '${year.leaveTypeLabel} is not available in ${year.year}.'
        else if (!year.configured)
          'No ${year.year ?? ''} allowance is set for this leave type.'
              .replaceAll('  ', ' ')
        else if (preview.years.length > 1)
          '${year.year}: ${year.remainingDays} days remaining · ${year.scheduledDays} leave day${year.scheduledDays == 1 ? '' : 's'}'
        else
          '${year.year}: ${year.remainingDays} days remaining',
      'Leave days: ${preview.calendarDays}',
      if (!preview.advanceNoticeMet && preview.earliestStartDate != null)
        'This starts too soon. Earliest start date is ${preview.earliestStartDate}.',
      if (!preview.balanceSufficient)
        'This request uses more leave days than the remaining allowance.',
    ];
    final warning = !preview.advanceNoticeMet || !preview.balanceSufficient;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFF7ED) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: warning ? const Color(0xFFFDBA74) : EmployeeColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                line,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: warning
                      ? const Color(0xFF9A3412)
                      : const Color(0xFF334155),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
