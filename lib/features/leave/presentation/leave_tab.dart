import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_download.dart';
import '../application/time_off_providers.dart';
import '../domain/time_off_models.dart';
import 'time_off_widgets.dart';

class LeaveTab extends ConsumerWidget {
  const LeaveTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TimeOffTab<LeaveRequest>(
      value: ref.watch(myLeavesProvider),
      onRefresh: () => ref.refresh(myLeavesProvider.future),
      statusOf: (r) => r.status,
      cardBuilder: (r) => _LeaveCard(
        r,
        onEdit: r.canEdit
            ? () => showFormSheet<void>(context, _LeaveForm(existing: r))
            : null,
      ),
      applyLabel: 'APPLY FOR LEAVE',
      emptyText: 'No leave requests yet.',
      onApply: () => showFormSheet<void>(context, const _LeaveForm()),
    );
  }
}

class _LeaveCard extends ConsumerWidget {
  const _LeaveCard(this.leave, {this.onEdit});

  final LeaveRequest leave;

  /// Null when the leave can no longer be edited.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DateBadge(leave.date, leave.status),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        leave.typeName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    if (onEdit != null)
                      IconButton(
                        tooltip: 'Edit',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.only(right: 8),
                        icon: const Icon(Icons.edit_rounded, size: 20),
                        color: AppColors.primary,
                        onPressed: onEdit,
                      ),
                    StatusChip(leave.status),
                  ],
                ),
                if (leave.date != null)
                  Text(
                    DateFormat('EEEE, dd MMM yyyy').format(leave.date!),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                if (leave.reason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    leave.reason,
                    style: const TextStyle(color: AppColors.body, fontSize: 13),
                  ),
                ],
                if (leave.attachment != null) ...[
                  const SizedBox(height: 6),
                  // Tap the name to download the file.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FileDownload(
                      style: FileDownloadStyle.link,
                      label: leave.attachment,
                      fetch: () => ref
                          .read(timeOffRepositoryProvider)
                          .attachment(leave.id, name: leave.attachment),
                    ),
                  ),
                ],
                if (leave.decision != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    leave.decision!,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
                if (leave.sentOn != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Sent ${DateFormat('dd MMM, hh:mm a').format(leave.sentOn!)}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaveForm extends ConsumerStatefulWidget {
  const _LeaveForm({this.existing});

  /// Set when one day of a pending leave is being edited.
  final LeaveRequest? existing;

  @override
  ConsumerState<_LeaveForm> createState() => _LeaveFormState();
}

class _LeaveFormState extends ConsumerState<_LeaveForm> {
  final _reason = TextEditingController();
  String? _typeId;
  Attachment? _file;
  DateTime? _from;
  DateTime? _to;
  bool _several = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    if (r == null) return;
    _typeId = r.typeId;
    _from = r.date;
    _reason.text = r.reason;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_typeId == null) {
      setState(() => _error = 'Please select the leave type.');
      return;
    }
    if (_several && _to == null) {
      setState(() => _error = 'Please select the end date.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a reason.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(timeOffRepositoryProvider);
      final existing = widget.existing;
      if (existing == null) {
        await repo.applyLeave(
          typeId: _typeId!,
          reason: _reason.text.trim(),
          from: _from ?? DateTime.now(),
          to: _several ? _to : null,
          attachment: _file,
        );
      } else {
        await repo.updateLeave(
          id: existing.id,
          typeId: _typeId!,
          reason: _reason.text.trim(),
          date: _from ?? DateTime.now(),
          attachment: _file,
        );
      }
      ref.invalidate(myLeavesProvider);
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
    final types = ref.watch(leaveTypesProvider);
    final today = DateUtils.dateOnly(DateTime.now());

    return Padding(
      padding: formPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            types.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(
                e is ApiException ? e.message : 'Could not load leave types.',
                style: const TextStyle(color: AppColors.danger),
              ),
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _typeId,
                isExpanded: true,
                hint: const Text(
                  'Leave type',
                  style: TextStyle(color: AppColors.muted, fontSize: 14),
                ),
                decoration: const InputDecoration(),
                items: [
                  for (final t in list)
                    DropdownMenuItem(value: t.id, child: Text(t.name)),
                ],
                onChanged: (v) => setState(() => _typeId = v),
              ),
            ),
            const SizedBox(height: 12),
            DaysPicker(
              initialFrom: widget.existing?.date,
              allowSeveral: widget.existing == null,
              firstDate: today.subtract(const Duration(days: 60)),
              lastDate: DateTime(today.year, today.month + 2, today.day),
              onChanged: (from, to, several) {
                _from = from;
                _to = to;
                _several = several;
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Reason'),
            ),
            const SizedBox(height: 12),
            AttachmentField(
              value: _file,
              current: widget.existing?.attachment,
              onChanged: (f) => setState(() => _file = f),
            ),
            if (_error != null) FormError(_error!),
            const SizedBox(height: 16),
            GradientButton(
              label: widget.existing == null ? 'SUBMIT LEAVE' : 'SAVE CHANGES',
              loading: _busy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
