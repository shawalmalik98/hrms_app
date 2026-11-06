import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../leave/domain/time_off_models.dart';
import '../../leave/presentation/time_off_widgets.dart';
import '../../services/presentation/service_widgets.dart';
import '../application/attendance_providers.dart';
import '../domain/attendance_models.dart';

Future<void> _openForm(BuildContext context, [AttendanceRequest? existing]) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _RequestForm(existing: existing),
    );

class AttendanceRequestScreen extends ConsumerWidget {
  const AttendanceRequestScreen({super.key});

  static TimeOffStatus _status(RequestStatus s) => switch (s) {
    RequestStatus.pending => TimeOffStatus.pending,
    RequestStatus.approved => TimeOffStatus.approved,
    RequestStatus.rejected => TimeOffStatus.disapproved,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Same layout as Leave, Work From Home, Advance and Loan.
    return ServiceScaffold(
      title: 'Attendance Requests',
      body: TimeOffTab<AttendanceRequest>(
        value: ref.watch(attendanceRequestsProvider),
        onRefresh: () async {
          ref.invalidate(attendanceRequestsProvider);
          await ref.read(attendanceRequestsProvider.future);
        },
        statusOf: (r) => _status(r.status),
        emptyText: 'No attendance requests yet.',
        applyLabel: 'REQUEST ATTENDANCE',
        onApply: () => _openForm(context),
        cardBuilder: (r) {
          final times = [
            if (r.checkIn != null) 'In ${r.checkIn}',
            if (r.checkOut != null) 'Out ${r.checkOut}',
          ].join('    ');
          return RequestCard(
            leading: DateBadge(r.appliedFor, _status(r.status)),
            title: r.typeLabel,
            subtitle: r.appliedFor == null
                ? null
                : DateFormat('EEEE, dd MMM yyyy').format(r.appliedFor!),
            lines: [
              if (times.isNotEmpty) times,
              if (r.message.isNotEmpty) r.message,
            ],
            status: _status(r.status),
            onEdit: r.canEdit ? () => _openForm(context, r) : null,
          );
        },
      ),
    );
  }
}

class _RequestForm extends ConsumerStatefulWidget {
  const _RequestForm({this.existing});

  /// Set when a pending request is being edited.
  final AttendanceRequest? existing;

  @override
  ConsumerState<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends ConsumerState<_RequestForm> {
  RequestType _type = RequestType.onTimeCheckIn;
  DateTime _date = DateTime.now();
  TimeOfDay? _time;
  final _message = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _needsTime => _type.needsCheckIn || _type.needsCheckOut;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    if (r == null) return;
    _type = r.type ?? _type;
    _date = r.appliedFor ?? _date;
    _message.text = r.message;
    final raw = _type.needsCheckIn ? r.checkIn : r.checkOut;
    final parts = raw?.split(':');
    final h = parts == null ? null : int.tryParse(parts[0]);
    final m = parts == null || parts.length < 2 ? null : int.tryParse(parts[1]);
    if (h != null && m != null) _time = TimeOfDay(hour: h, minute: m);
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      // An older request being edited may be before the picker's range.
      initialDate:
          _date.isBefore(DateTime.now().subtract(const Duration(days: 62)))
          ? DateTime.now().subtract(const Duration(days: 62))
          : _date,
      firstDate: DateTime.now().subtract(const Duration(days: 62)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  static String _hms(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _submit() async {
    if (_busy) return;
    if (_needsTime && _time == null) {
      setState(() => _error = 'Please select the time.');
      return;
    }
    if (_message.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a reason.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = NewAttendanceRequest(
        date: _date,
        type: _type,
        message: _message.text.trim(),
        checkIn: _type.needsCheckIn ? _hms(_time!) : null,
        checkOut: _type.needsCheckOut ? _hms(_time!) : null,
      );
      final repo = ref.read(attendanceRepositoryProvider);
      final existing = widget.existing;
      if (existing == null) {
        await repo.submitRequest(request);
      } else {
        await repo.updateRequest(existing.id, request);
      }
      ref.invalidate(attendanceRequestsProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not submit the request.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    OutlinedButton picker(IconData icon, String text, VoidCallback onTap) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(text),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<RequestType>(
              initialValue: _type,
              decoration: const InputDecoration(hintText: 'Request type'),
              items: [
                for (final t in RequestType.values)
                  DropdownMenuItem(value: t, child: Text(t.apiValue)),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            picker(
              Icons.calendar_today_rounded,
              DateFormat('dd MMM yyyy').format(_date),
              _pickDate,
            ),
            if (_needsTime) ...[
              const SizedBox(height: 12),
              picker(
                Icons.schedule_rounded,
                _time == null
                    ? (_type.needsCheckIn
                          ? 'Select check in time'
                          : 'Select check out time')
                    : _time!.format(context),
                _pickTime,
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Reason'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            GradientButton(
              label: widget.existing == null
                  ? 'SUBMIT REQUEST'
                  : 'SAVE CHANGES',
              loading: _busy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
