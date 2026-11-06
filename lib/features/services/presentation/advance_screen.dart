import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../leave/presentation/time_off_widgets.dart';
import '../application/services_providers.dart';
import '../domain/service_models.dart';
import 'service_widgets.dart';

class AdvanceScreen extends ConsumerWidget {
  const AdvanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(advanceProvider);
    final salary = data.value?.salary;

    return ServiceScaffold(
      title: 'Advance Salary',
      body: TimeOffTab<AdvanceRequest>(
        value: data.whenData((d) => d.requests),
        onRefresh: () async {
          ref.invalidate(advanceProvider);
          await ref.read(advanceProvider.future);
        },
        statusOf: (r) => r.status,
        emptyText: 'No advance salary requests yet.',
        applyLabel: 'REQUEST ADVANCE',
        onApply: () =>
            showFormSheet<void>(context, AdvanceForm(salary: salary)),
        cardBuilder: (r) => RequestCard(
          icon: Icons.payments_rounded,
          title: rs(r.amount),
          status: r.status,
          subtitle: 'From ${monthLabel(r.period)} salary',
          lines: [
            if (r.message.isNotEmpty) r.message,
            if (r.approverMessage != null) r.approverMessage!,
            if (r.decision != null) r.decision!,
          ],
          onEdit: r.canEdit
              ? () => showFormSheet<void>(
                  context,
                  AdvanceForm(salary: salary, existing: r),
                )
              : null,
        ),
      ),
    );
  }
}

class AdvanceForm extends ConsumerStatefulWidget {
  const AdvanceForm({super.key, this.salary, this.existing});

  final num? salary;

  /// Set when a pending request is being edited.
  final AdvanceRequest? existing;

  @override
  ConsumerState<AdvanceForm> createState() => _AdvanceFormState();
}

class _AdvanceFormState extends ConsumerState<AdvanceForm> {
  final _amount = TextEditingController();
  final _message = TextEditingController();
  String? _month;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    if (r == null) return;
    _amount.text = '${r.amount}';
    _message.text = r.message;
    _month = r.period;
  }

  @override
  void dispose() {
    _amount.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final amount = num.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Please enter the amount.');
      return;
    }
    final salary = widget.salary;
    if (salary != null && amount > salary) {
      setState(() => _error = 'The advance cannot be more than ${rs(salary)}.');
      return;
    }
    if (_month == null) {
      setState(() => _error = 'Please select the salary month.');
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
      final repo = ref.read(servicesRepositoryProvider);
      final existing = widget.existing;
      if (existing == null) {
        await repo.submitAdvance(
          amount: amount,
          payback: _month!,
          message: _message.text.trim(),
        );
      } else {
        await repo.updateAdvance(
          id: existing.id,
          amount: amount,
          payback: _month!,
          message: _message.text.trim(),
        );
      }
      ref.invalidate(advanceProvider);
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
    final salary = widget.salary;
    return Padding(
      padding: formPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AmountField(
              controller: _amount,
              hint: 'Amount',
              helper: salary == null
                  ? null
                  : 'Up to ${rs(salary)} (your salary)',
            ),
            const SizedBox(height: 12),
            MonthField(
              value: _month,
              hint: 'Deduct from the salary of',
              existing: widget.existing?.period,
              onChanged: (v) => setState(() => _month = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Reason'),
            ),
            if (_error != null) FormError(_error!),
            const SizedBox(height: 16),
            GradientButton(
              label: widget.existing == null
                  ? 'SUBMIT REQUEST'
                  : 'SAVE CHANGES',
              loading: _busy,
              onPressed: _submit,
            ),
            if (widget.existing == null)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'You can edit the request until it is answered.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
