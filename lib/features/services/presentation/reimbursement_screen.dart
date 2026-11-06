import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/file_download.dart';
import '../../leave/domain/time_off_models.dart';
import '../../leave/presentation/time_off_widgets.dart';
import '../application/services_providers.dart';
import '../domain/reimbursement_models.dart';
import '../domain/service_models.dart';
import 'service_widgets.dart';

final _day = DateFormat('dd MMM yyyy');

class ReimbursementScreen extends ConsumerWidget {
  const ReimbursementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(expensesProvider);
    final d = data.value;

    return ServiceScaffold(
      title: 'Reimbursement',
      body: TimeOffTab<ExpenseClaim>(
        value: data.whenData((d) => d.claims),
        onRefresh: () async {
          ref.invalidate(expensesProvider);
          await ref.read(expensesProvider.future);
        },
        statusOf: (c) => c.status,
        emptyText: 'No expense claims yet.',
        applyLabel: 'NEW CLAIM',
        onApply: () => showFormSheet<void>(
          context,
          ExpenseForm(types: d?.types ?? defaultExpenseTypes),
        ),
        header: d == null
            ? null
            : StatStrip(
                items: [
                  ('Claimed', d.total, AppColors.info),
                  ('Approved', d.approvedTotal, AppColors.primary),
                  ('Paid', d.paidTotal, AppColors.warning),
                ],
              ),
        cardBuilder: (c) => RequestCard(
          icon: Icons.receipt_rounded,
          title: rs(c.amount),
          status: c.status,
          // A paid claim says so, instead of just "Approved".
          chip: c.paid ? const _PaidChip() : null,
          subtitle: [
            c.typeName,
            if (c.date != null) _day.format(c.date!),
          ].join('  •  '),
          lines: [
            if (c.description.isNotEmpty) c.description,
            if (c.approver != null)
              'Answered by ${c.approver}'
                  '${c.approvedAt == null ? '' : ', ${c.approvedAt}'}',
            ?c.reason,
            if (c.payslipLabel != null)
              'Paid with the ${c.payslipLabel} payslip',
          ],
          footer: c.attachment == null && !c.amountChanged
              ? null
              : Row(
                  children: [
                    if (c.amountChanged)
                      TextButton.icon(
                        onPressed: () => showFormSheet<void>(
                          context,
                          _AmountHistory(claim: c),
                        ),
                        icon: const Icon(Icons.history_rounded, size: 16),
                        label: const Text('Amount history'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (c.attachment != null)
                      FileDownload(
                        fetch: () => ref
                            .read(reimbursementRepositoryProvider)
                            .attachment(c.id, name: c.attachment),
                      ),
                  ],
                ),
          onEdit: c.canEdit
              ? () => showFormSheet<void>(
                  context,
                  ExpenseForm(
                    types: d?.types ?? defaultExpenseTypes,
                    existing: c,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _PaidChip extends StatelessWidget {
  const _PaidChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      'Paid',
      style: TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

/// The amounts a claim has had, and who set each one.
class _AmountHistory extends ConsumerWidget {
  const _AmountHistory({required this.claim});

  final ExpenseClaim claim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(amountLogProvider(claim.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: log.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            e is ApiException ? e.message : 'Could not load the history.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.body, fontSize: 15),
          ),
        ),
        data: (entries) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Amount history',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 12),
            for (final e in entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.payments_rounded,
                  color: AppColors.primary,
                ),
                title: Text(
                  rs(e.amount),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  [if (e.by.isNotEmpty) e.by, ?e.at].join('  •  '),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A new claim, or (with [existing]) the change of a pending one.
class ExpenseForm extends ConsumerStatefulWidget {
  const ExpenseForm({super.key, required this.types, this.existing});

  final Map<int, String> types;
  final ExpenseClaim? existing;

  @override
  ConsumerState<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<ExpenseForm> {
  /// The server accepts up to this.
  static const _maxAmount = 9999999.99;

  final _amount = TextEditingController();
  final _reason = TextEditingController();
  late DateTime _date;
  int? _type;
  Attachment? _file;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _date = c?.date ?? DateUtils.dateOnly(DateTime.now());
    if (c != null) {
      _type = widget.types.containsKey(c.typeId) ? c.typeId : null;
      _amount.text = '${c.amount}';
      _reason.text = c.description;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final first = today.subtract(const Duration(days: 365));
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(first) ? first : _date,
      firstDate: first,
      // Today or earlier.
      lastDate: today,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_busy) return;
    final amount = num.tryParse(_amount.text.trim());
    final String? problem;
    if (_type == null) {
      problem = 'Please choose the kind of expense.';
    } else if (amount == null || amount < 1) {
      problem = 'Please enter the amount.';
    } else if (amount > _maxAmount) {
      problem = 'The amount is too big.';
    } else if (_reason.text.trim().isEmpty) {
      problem = 'Please write what the expense was for.';
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
      final repo = ref.read(reimbursementRepositoryProvider);
      final existing = widget.existing;
      if (existing == null) {
        await repo.add(
          date: _date,
          reason: _reason.text.trim(),
          type: _type!,
          amount: amount!,
          attachment: _file,
        );
      } else {
        await repo.update(
          id: existing.id,
          date: _date,
          reason: _reason.text.trim(),
          type: _type!,
          amount: amount!,
          attachment: _file,
        );
      }
      ref.invalidate(expensesProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send the claim.');
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
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
              label: Text(DateFormat('EEE, dd MMM yyyy').format(_date)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navy,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _type,
              isExpanded: true,
              hint: const Text(
                'Kind of expense',
                style: TextStyle(color: AppColors.muted, fontSize: 14),
              ),
              decoration: const InputDecoration(),
              items: [
                for (final e in widget.types.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 12),
            AmountField(controller: _amount, hint: 'Amount'),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'What was it for? (e.g. Taxi to the client)',
              ),
            ),
            const SizedBox(height: 12),
            AttachmentField(
              value: _file,
              extensions: Attachment.expenseExtensions,
              current: widget.existing?.attachment,
              onChanged: (f) => setState(() => _file = f),
            ),
            if (_error != null) FormError(_error!),
            const SizedBox(height: 16),
            GradientButton(
              label: widget.existing == null ? 'SUBMIT CLAIM' : 'SAVE CHANGES',
              loading: _busy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
