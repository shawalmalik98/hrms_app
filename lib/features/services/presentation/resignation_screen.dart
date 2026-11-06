import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../leave/domain/time_off_models.dart';
import '../../leave/presentation/time_off_widgets.dart';
import '../application/services_providers.dart';
import '../domain/service_models.dart';
import 'service_widgets.dart';

class ResignationScreen extends ConsumerWidget {
  const ResignationScreen({super.key});

  static final _date = DateFormat('dd MMM yyyy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(resignationsProvider);
    final list = data.value ?? const <Resignation>[];
    final active = list.where((r) => r.blocksNew).toList();
    // Only one resignation at a time: no new one while one is pending or
    // approved (the server refuses it as well).
    // Not shown only while the list is first loading, or when one is active.
    final canPlace = data.hasValue ? active.isEmpty : data.hasError;

    return ServiceScaffold(
      title: 'Resignation',
      body: TimeOffTab<Resignation>(
        value: data,
        onRefresh: () async {
          ref.invalidate(resignationsProvider);
          await ref.read(resignationsProvider.future);
        },
        statusOf: (r) => r.status,
        showFilters: false,
        emptyText: 'You have not placed a resignation.',
        applyLabel: 'PLACE RESIGNATION',
        onApply: canPlace
            ? () => showFormSheet<void>(context, const ResignationForm())
            : null,
        header: active.isEmpty
            ? null
            : _Notice(
                approved: active.first.status == TimeOffStatus.approved,
                canEdit: active.first.canEdit,
              ),
        cardBuilder: (r) {
          final days = r.from != null && r.to != null
              ? r.to!.difference(r.from!).inDays
              : null;
          return RequestCard(
            icon: Icons.exit_to_app_rounded,
            title: 'Resignation',
            status: r.status,
            subtitle: r.from == null || r.to == null
                ? null
                : '${_date.format(r.from!)}  →  ${_date.format(r.to!)}'
                      '${days == null ? '' : '  ($days days)'}',
            lines: [
              if (r.reason.isNotEmpty) r.reason,
              if (r.approverMessage != null) r.approverMessage!,
              if (r.decision != null) r.decision!,
            ],
            onEdit: r.canEdit
                ? () =>
                      showFormSheet<void>(context, ResignationForm(existing: r))
                : null,
          );
        },
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.approved, required this.canEdit});

  final bool approved;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final text = approved
        ? 'Your resignation has been approved.'
        : canEdit
        ? 'Your resignation is waiting for a response. You can edit it until '
              'it is answered.'
        : 'Your resignation has been answered and can no longer be edited.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.primaryActive,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ResignationForm extends ConsumerStatefulWidget {
  const ResignationForm({super.key, this.existing});

  /// Set when a pending resignation is being edited.
  final Resignation? existing;

  @override
  ConsumerState<ResignationForm> createState() => _ResignationFormState();
}

class _ResignationFormState extends ConsumerState<ResignationForm> {
  static final _fmt = DateFormat('EEE, dd MMM yyyy');

  final _reason = TextEditingController();
  late DateTime _from;
  late DateTime _to;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    final r = widget.existing;
    _from = r?.from ?? today;
    // A month's notice is the usual default.
    _to = r?.to ?? today.add(const Duration(days: 30));
    _reason.text = r?.reason ?? '';
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isFrom) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final first = isFrom ? today : _from.add(const Duration(days: 1));
    final current = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: DateTime(today.year + 2, today.month, today.day),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (!_to.isAfter(_from)) _to = _from.add(const Duration(days: 30));
      } else {
        _to = picked;
      }
    });
  }

  Future<bool> _confirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Place your resignation?',
          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy),
        ),
        content: Text(
          'Last day: ${_fmt.format(_to)}.\n'
          'You can edit it until it is answered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Place it'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Please enter the reason.');
      return;
    }
    if (!_to.isAfter(_from)) {
      setState(() => _error = 'The last day must be after the first day.');
      return;
    }
    final existing = widget.existing;
    if (existing == null && !await _confirm()) return;
    if (!mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(servicesRepositoryProvider);
      if (existing == null) {
        await repo.placeResignation(
          reason: _reason.text.trim(),
          from: _from,
          to: _to,
        );
      } else {
        await repo.updateResignation(
          id: existing.id,
          reason: _reason.text.trim(),
          from: _from,
          to: _to,
        );
      }
      ref.invalidate(resignationsProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not submit. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _button(IconData icon, String label, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: formPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _button(
              Icons.calendar_today_rounded,
              'From  ${_fmt.format(_from)}',
              () => _pick(true),
            ),
            const SizedBox(height: 12),
            _button(
              Icons.event_available_rounded,
              'Last day  ${_fmt.format(_to)}',
              () => _pick(false),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'Reason'),
            ),
            if (_error != null) FormError(_error!),
            const SizedBox(height: 16),
            GradientButton(
              label: widget.existing == null
                  ? 'PLACE RESIGNATION'
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
