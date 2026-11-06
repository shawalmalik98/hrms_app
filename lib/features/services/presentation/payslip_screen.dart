import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/file_viewer.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../leave/domain/time_off_models.dart';
import '../../leave/presentation/time_off_widgets.dart';
import '../application/services_providers.dart';
import '../domain/service_models.dart';
import 'service_widgets.dart';

/// The payslips list as a page of its own (with an app bar).
class PayslipScreen extends StatelessWidget {
  const PayslipScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const ServiceScaffold(title: 'Payslips', body: PayslipTab());
}

/// The payslips list, as a tab of the bottom bar.
class PayslipTab extends ConsumerWidget {
  const PayslipTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TimeOffTab<Payslip>(
      value: ref.watch(payslipsProvider),
      onRefresh: () async {
        ref.invalidate(payslipsProvider);
        await ref.read(payslipsProvider.future);
      },
      statusOf: (_) => TimeOffStatus.approved,
      showFilters: false,
      emptyText:
          'No payslips yet. A payslip appears here after Finance has paid '
          'the salary.',
      cardBuilder: (p) => _PayslipCard(p),
    );
  }
}

class _PayslipCard extends ConsumerStatefulWidget {
  const _PayslipCard(this.payslip);

  final Payslip payslip;

  @override
  ConsumerState<_PayslipCard> createState() => _PayslipCardState();
}

class _PayslipCardState extends ConsumerState<_PayslipCard> {
  /// 'view' or 'download' while one of them is running.
  String? _running;

  Future<void> _run(
    String what,
    Future<void> Function(
      ({Uint8List bytes, String filename}) file,
      ScaffoldMessengerState messenger,
    )
    action,
  ) async {
    if (_running != null) return;
    setState(() => _running = what);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ref
          .read(servicesRepositoryProvider)
          .payslipPdf(widget.payslip.id);
      await action(file, messenger);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not download the payslip.')),
      );
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  /// Opens the payslip in the phone's PDF viewer.
  Future<void> _view() => _run('view', (file, messenger) async {
    if (!mounted) return;
    await openFile(context, file.bytes, file.filename);
  });

  /// Saves the payslip on the phone: the phone asks where (e.g. Downloads).
  Future<void> _download() => _run('download', (file, messenger) async {
    final saved = await FilePicker.saveFile(
      fileName: file.filename,
      bytes: file.bytes,
      mimeType: 'application/pdf',
      dialogTitle: 'Save payslip',
    );
    if (saved == null) return; // the employee cancelled
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Payslip saved on your phone.'),
        action: SnackBarAction(
          label: 'OPEN',
          onPressed: () => openFile(context, file.bytes, file.filename),
        ),
      ),
    );
  });

  Widget _row(String label, num value, {Color? color}) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.body, fontSize: 13),
          ),
        ),
        Text(
          rs(value),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: color ?? AppColors.navy,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.payslip;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  p.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Net salary',
                    style: TextStyle(
                      color: AppColors.primaryActive,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  rs(p.net),
                  style: const TextStyle(
                    color: AppColors.primaryActive,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _row('Gross salary', p.gross),
          if (p.extra > 0) _row('Extra earnings', p.extra),
          _row('Deductions', p.deduction, color: AppColors.danger),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _running != null ? null : _view,
                  icon: _running == 'view'
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('View'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running != null ? null : _download,
                  icon: _running == 'download'
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
