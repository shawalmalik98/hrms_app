import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../leave/presentation/time_off_widgets.dart';
import '../application/services_providers.dart';
import '../data/services_repository.dart';
import '../domain/service_models.dart';
import 'service_widgets.dart';

class LoanScreen extends ConsumerWidget {
  const LoanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(loansProvider);
    final summary = data.value;

    return ServiceScaffold(
      title: 'Loan',
      body: TimeOffTab<Loan>(
        value: data.whenData((d) => d.loans),
        onRefresh: () async {
          ref.invalidate(loansProvider);
          await ref.read(loansProvider.future);
        },
        statusOf: (r) => r.status,
        emptyText: 'No loan requests yet.',
        applyLabel: 'REQUEST A LOAN',
        onApply: () => showFormSheet<void>(context, const LoanFormSheet()),
        header: summary == null
            ? null
            : StatStrip(
                items: [
                  ('Received', summary.given, AppColors.info),
                  ('Returned', summary.returned, AppColors.primary),
                  ('Remaining', summary.remaining, AppColors.warning),
                ],
              ),
        cardBuilder: (loan) => RequestCard(
          icon: Icons.account_balance_rounded,
          title: rs(loan.amount),
          status: loan.status,
          subtitle: loan.reason,
          lines: [
            'Deducted ${loan.deductionLabel} from ${monthLabel(loan.start)}',
            if (loan.message.isNotEmpty) loan.message,
            if (loan.approverMessage != null) loan.approverMessage!,
            if (loan.decision != null) loan.decision!,
          ],
          onTap: () => showFormSheet<void>(context, _LoanDetailSheet(loan)),
          onEdit: loan.canEdit
              ? () =>
                    showFormSheet<void>(context, LoanFormSheet(existing: loan))
              : null,
        ),
      ),
    );
  }
}

/// What has been paid back so far. Only an approved loan has this; for the
/// others the server says why not ("Loan request is Pending.").
class _LoanDetailSheet extends ConsumerWidget {
  const _LoanDetailSheet(this.loan);

  final Loan loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(loanDetailProvider(loan.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: detail.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            e is ApiException ? e.message : 'Could not load the loan.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.body, fontSize: 15),
          ),
        ),
        data: (d) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              loan.reason,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 14),
            StatStrip(
              items: [
                ('Received', d.given, AppColors.info),
                ('Returned', d.returned, AppColors.primary),
                ('Remaining', d.remaining, AppColors.warning),
              ],
            ),
            if (d.installments.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Installments paid',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final i in d.installments)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.primary,
                        ),
                        title: Text(rs(i.amount)),
                        trailing: Text(
                          _date(i.date),
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _date(String raw) {
    final d = DateTime.tryParse(raw);
    return d == null ? raw : DateFormat('dd MMM yyyy').format(d);
  }
}

class LoanFormSheet extends ConsumerStatefulWidget {
  const LoanFormSheet({super.key, this.existing});

  /// Set when a pending request is being edited.
  final Loan? existing;

  @override
  ConsumerState<LoanFormSheet> createState() => _LoanFormSheetState();
}

class _LoanFormSheetState extends ConsumerState<LoanFormSheet> {
  final _amount = TextEditingController();
  final _deduction = TextEditingController();
  final _message = TextEditingController();
  String? _reason;
  String? _start;
  bool _percent = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final l = widget.existing;
    if (l == null) return;
    _amount.text = '${l.amount}';
    _deduction.text = '${l.deduction}';
    _message.text = l.message;
    _reason = loanReasons.contains(l.reason) ? l.reason : null;
    _start = l.start;
    _percent = l.percentDeduction;
  }

  @override
  void dispose() {
    _amount.dispose();
    _deduction.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final amount = num.tryParse(_amount.text.trim());
    final deduction = num.tryParse(_deduction.text.trim());
    final String? problem;
    if (amount == null || amount <= 0) {
      problem = 'Please enter the loan amount.';
    } else if (_reason == null) {
      problem = 'Please select the loan type.';
    } else if (deduction == null || deduction <= 0) {
      problem = _percent
          ? 'Please enter the percent to deduct.'
          : 'Please enter the monthly installment.';
    } else if (_percent && deduction > 100) {
      problem = 'The percent must be between 1 and 100.';
    } else if (!_percent && deduction > amount) {
      problem = 'The installment cannot be more than the loan.';
    } else if (_start == null) {
      problem = 'Please select the month the deduction starts.';
    } else if (_message.text.trim().isEmpty) {
      problem = 'Please enter the details.';
    } else {
      problem = null;
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final form = LoanForm(
        amount: amount!,
        reason: _reason!,
        message: _message.text.trim(),
        percent: _percent,
        deduction: deduction!,
        start: _start!,
      );
      final repo = ref.read(servicesRepositoryProvider);
      final existing = widget.existing;
      if (existing == null) {
        await repo.submitLoan(form);
      } else {
        await repo.updateLoan(existing.id, form);
      }
      ref.invalidate(loansProvider);
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
    return Padding(
      padding: formPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AmountField(controller: _amount, hint: 'Loan amount'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              isExpanded: true,
              hint: const Text(
                'Loan type',
                style: TextStyle(color: AppColors.muted, fontSize: 14),
              ),
              decoration: const InputDecoration(),
              items: [
                for (final r in loanReasons)
                  DropdownMenuItem(value: r, child: Text(r)),
              ],
              onChanged: (v) => setState(() => _reason = v),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Fixed amount')),
                ButtonSegment(value: true, label: Text('% of salary')),
              ],
              selected: {_percent},
              onSelectionChanged: (s) => setState(() => _percent = s.first),
            ),
            const SizedBox(height: 12),
            AmountField(
              controller: _deduction,
              hint: _percent
                  ? 'Percent each month (1-100)'
                  : 'Amount each month',
            ),
            const SizedBox(height: 12),
            MonthField(
              value: _start,
              hint: 'Start deducting from',
              existing: widget.existing?.start,
              onChanged: (v) => setState(() => _start = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Details'),
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
          ],
        ),
      ),
    );
  }
}
