import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../leave/domain/time_off_models.dart';
import '../../leave/presentation/time_off_widgets.dart';
import '../domain/service_models.dart';

/// A request in a list: amount or title, a few lines, the status, and an edit
/// button only while the request can still be edited.
class RequestCard extends StatelessWidget {
  const RequestCard({
    super.key,
    required this.title,
    required this.status,
    this.subtitle,
    this.lines = const [],
    this.onEdit,
    this.onTap,
    this.icon = Icons.request_page_rounded,
    this.leading,
    this.chip,
    this.accent,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final List<String> lines;
  final TimeOffStatus status;
  final IconData icon;

  /// Replaces the icon box on the left (e.g. a date badge).
  final Widget? leading;

  /// Replaces the status chip (for statuses other than pending / approved /
  /// disapproved).
  final Widget? chip;

  /// Replaces the colour taken from [status].
  final Color? accent;

  /// Shown at the bottom of the card, under the lines.
  final Widget? footer;
  final VoidCallback? onEdit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? statusColor(status);
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading ??
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: color == AppColors.muted ? AppColors.body : color,
                ),
              ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
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
                    chip ?? StatusChip(status),
                  ],
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                for (final line in lines) ...[
                  const SizedBox(height: 4),
                  Text(
                    line,
                    style: const TextStyle(color: AppColors.body, fontSize: 13),
                  ),
                ],
                if (footer != null) ...[const SizedBox(height: 8), footer!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The months a salary deduction may start from: this month and the next.
/// [extra] (the month of a request being edited) is kept in the list.
List<(String value, String label)> monthOptions([String? extra]) {
  final now = DateTime.now();
  final values = [
    for (var i = 0; i < 2; i++)
      DateFormat('yyyy-MM').format(DateTime(now.year, now.month + i)),
    if (extra != null && extra.isNotEmpty) extra,
  ];
  return [for (final v in values.toSet().toList()..sort()) (v, monthLabel(v))];
}

/// A dropdown of [monthOptions].
class MonthField extends StatelessWidget {
  const MonthField({
    super.key,
    required this.value,
    required this.hint,
    required this.onChanged,
    this.existing,
  });

  final String? value;
  final String hint;
  final String? existing;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      hint: Text(
        hint,
        style: const TextStyle(color: AppColors.muted, fontSize: 14),
      ),
      decoration: const InputDecoration(),
      items: [
        for (final (v, label) in monthOptions(existing))
          DropdownMenuItem(value: v, child: Text(label)),
      ],
      onChanged: onChanged,
    );
  }
}

/// A text field that takes numbers only.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.hint,
    this.helper,
  });

  final TextEditingController controller;
  final String hint;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      decoration: InputDecoration(hintText: hint, helperText: helper),
    );
  }
}

/// A screen that holds one self service list (advance, loan, payslips).
class ServiceScaffold extends StatelessWidget {
  const ServiceScaffold({super.key, required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: body,
  );
}

/// Three figures side by side (loan given, returned, remaining).
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.items});

  final List<(String label, num value, Color color)> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
              decoration: BoxDecoration(
                color: items[i].$3.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  FittedBox(
                    child: Text(
                      rs(items[i].$2),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: items[i].$3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i].$1,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.body,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
