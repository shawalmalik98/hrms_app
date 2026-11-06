import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../attendance/application/attendance_providers.dart';
import '../application/time_off_providers.dart';
import '../domain/time_off_models.dart';
import 'time_off_widgets.dart';

class WfhTab extends ConsumerWidget {
  const WfhTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(myWfhProvider);
    final today = DateUtils.dateOnly(DateTime.now());
    final todayApproved = (value.value ?? const []).any(
      (r) =>
          r.status == TimeOffStatus.approved &&
          r.date != null &&
          DateUtils.isSameDay(r.date, today),
    );

    return TimeOffTab<WfhRequest>(
      value: value,
      onRefresh: () async {
        // A fresh list also refreshes the days that skip the location check.
        ref.read(todayAttendanceProvider.notifier).refreshOfficeData();
        ref.invalidate(myWfhProvider);
        await ref.read(myWfhProvider.future);
      },
      statusOf: (r) => r.status,
      cardBuilder: (r) => _WfhCard(r),
      applyLabel: 'REQUEST WFH',
      emptyText: 'No work from home requests yet.',
      header: todayApproved
          ? const _Banner(
              icon: Icons.home_work_rounded,
              text:
                  'Today is your work from home day. You can mark attendance '
                  'from any location.',
            )
          : null,
      onApply: () => showFormSheet<void>(context, const _WfhForm()),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
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

class _WfhCard extends StatelessWidget {
  const _WfhCard(this.request);

  final WfhRequest request;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DateBadge(request.date, request.status),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        request.date == null
                            ? 'Work from home'
                            : DateFormat('EEEE, dd MMM').format(request.date!),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    StatusChip(request.status),
                  ],
                ),
                if (request.reason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    request.reason,
                    style: const TextStyle(color: AppColors.body, fontSize: 13),
                  ),
                ],
                if (request.decision != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    request.decision!,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
                if (request.sentOn != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Sent ${DateFormat('dd MMM, hh:mm a').format(request.sentOn!)}',
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

class _WfhForm extends ConsumerStatefulWidget {
  const _WfhForm();

  @override
  ConsumerState<_WfhForm> createState() => _WfhFormState();
}

class _WfhFormState extends ConsumerState<_WfhForm> {
  final _reason = TextEditingController();
  DateTime? _from;
  DateTime? _to;
  bool _several = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
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
      await ref
          .read(timeOffRepositoryProvider)
          .submitWfh(
            reason: _reason.text.trim(),
            from: _from ?? DateTime.now(),
            to: _several ? _to : null,
          );
      ref.invalidate(myWfhProvider);
      // An auto approved request can make today a work from home day.
      ref.read(todayAttendanceProvider.notifier).refreshOfficeData();
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
    final today = DateUtils.dateOnly(DateTime.now());

    return Padding(
      padding: formPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DaysPicker(
              firstDate: today,
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
            const SizedBox(height: 10),
            const Text(
              'On an approved day you can mark attendance from any location.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            if (_error != null) FormError(_error!),
            const SizedBox(height: 16),
            GradientButton(
              label: 'SUBMIT REQUEST',
              loading: _busy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
