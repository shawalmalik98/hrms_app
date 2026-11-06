import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/files/image_shrink.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../domain/time_off_models.dart';

Color statusColor(TimeOffStatus s) => switch (s) {
  TimeOffStatus.pending => AppColors.muted,
  TimeOffStatus.approved => AppColors.primary,
  TimeOffStatus.disapproved => AppColors.danger,
};

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final TimeOffStatus status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color == AppColors.muted ? AppColors.body : color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The date on the left of a request card: big day number, month under it.
class DateBadge extends StatelessWidget {
  const DateBadge(this.date, this.status, {super.key});

  final DateTime? date;
  final TimeOffStatus status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      width: 54,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: date == null
          ? Icon(Icons.event_rounded, color: color)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${date!.day}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color == AppColors.muted ? AppColors.navy : color,
                    height: 1.1,
                  ),
                ),
                Text(
                  DateFormat('MMM').format(date!).toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color == AppColors.muted ? AppColors.body : color,
                  ),
                ),
              ],
            ),
    );
  }
}

/// A list of requests with filter chips (with counts), pull to refresh, and
/// one clear "apply" button at the top. Used by Leave and Work From Home.
class TimeOffTab<T> extends StatefulWidget {
  const TimeOffTab({
    super.key,
    required this.value,
    required this.onRefresh,
    required this.statusOf,
    required this.cardBuilder,
    required this.emptyText,
    this.applyLabel,
    this.onApply,
    this.header,
    this.showFilters = true,
  });

  final AsyncValue<List<T>> value;
  final Future<void> Function() onRefresh;
  final TimeOffStatus Function(T) statusOf;
  final Widget Function(T) cardBuilder;
  final String emptyText;

  /// The button at the top. Left out when there is nothing to apply for.
  final String? applyLabel;
  final VoidCallback? onApply;
  final bool showFilters;

  /// Shown above the apply button (e.g. "today is your WFH day").
  final Widget? header;

  @override
  State<TimeOffTab<T>> createState() => _TimeOffTabState<T>();
}

class _TimeOffTabState<T> extends State<TimeOffTab<T>> {
  TimeOffStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final all = widget.value.value;
    final shown = all == null
        ? const []
        : [
            for (final r in all)
              if (_filter == null || widget.statusOf(r) == _filter) r,
          ];
    int count(TimeOffStatus? s) => all == null
        ? 0
        : all.where((r) => s == null || widget.statusOf(r) == s).length;

    final list = RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // Room under the last card for the button that floats over the list.
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          widget.onApply == null ? 110 : 190,
        ),
        children: [
          if (widget.header != null) ...[
            widget.header!,
            const SizedBox(height: 12),
          ],
          if (widget.showFilters && all != null && all.isNotEmpty)
            Row(
              children: [
                for (final s in <TimeOffStatus?>[null, ...TimeOffStatus.values])
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: s == TimeOffStatus.disapproved ? 0 : 8,
                      ),
                      child: _FilterTile(
                        label: s?.label ?? 'All',
                        count: count(s),
                        selected: _filter == s,
                        onTap: () => setState(() => _filter = s),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          if (all == null && !widget.value.hasError)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (widget.value.hasError)
            _Message(
              icon: Icons.cloud_off_rounded,
              text: widget.value.error is ApiException
                  ? '${(widget.value.error as ApiException).message}\n'
                        'Pull down to try again.'
                  : 'Could not load. Pull down to retry.',
            )
          else if (shown.isEmpty)
            _Message(
              icon: Icons.inbox_rounded,
              text: _filter == null
                  ? widget.emptyText
                  : 'No ${_filter!.label.toLowerCase()} requests.',
            )
          else
            for (var i = 0; i < shown.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FadeInUp(
                  index: i.clamp(0, 6),
                  child: widget.cardBuilder(shown[i]),
                ),
              ),
        ],
      ),
    );

    if (widget.onApply == null) return list;
    return Stack(
      children: [
        list,
        Positioned(
          right: 20,
          // Above the floating bottom bar (the body's bottom padding is its
          // height); on a page without the bar just above the screen edge.
          bottom: MediaQuery.paddingOf(context).bottom + 16,
          child: ApplyButton(
            label: widget.applyLabel ?? 'APPLY',
            onPressed: widget.onApply!,
          ),
        ),
      ],
    );
  }
}

/// The button that starts a new request: bottom right, over the list, the
/// same in every module.
class ApplyButton extends StatelessWidget {
  const ApplyButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.glow(AppColors.primary),
      ),
      child: FloatingActionButton.extended(
        // Several of these can be on one route (the tabs): no shared hero.
        heroTag: null,
        backgroundColor: Colors.transparent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Icon(icon, size: 56, color: AppColors.border),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// One day or several days. Reports `(from, to, several)`; `to` is null for
/// one day, or while the end date of a range is not chosen yet.
class DaysPicker extends StatefulWidget {
  const DaysPicker({
    super.key,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
    this.initialFrom,
    this.allowSeveral = true,
  });

  /// The date to start on (editing an existing request).
  final DateTime? initialFrom;

  /// False hides "Several days" (a leave is edited one day at a time).
  final bool allowSeveral;
  final DateTime firstDate;
  final DateTime lastDate;
  final void Function(DateTime from, DateTime? to, bool several) onChanged;

  @override
  State<DaysPicker> createState() => _DaysPickerState();
}

class _DaysPickerState extends State<DaysPicker> {
  static final _fmt = DateFormat('EEE, dd MMM yyyy');
  bool _several = false;
  DateTime _from = DateUtils.dateOnly(DateTime.now());
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    final start = widget.initialFrom;
    if (start != null) _from = DateUtils.dateOnly(start);
    if (_from.isBefore(widget.firstDate)) _from = widget.firstDate;
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  void _report() => widget.onChanged(_from, _several ? _to : null, _several);

  Future<void> _pick(bool isFrom) async {
    final initial = isFrom ? _from : (_to ?? _from);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(widget.firstDate)
          ? widget.firstDate
          : initial,
      firstDate: isFrom ? widget.firstDate : _from,
      lastDate: widget.lastDate,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to != null && _to!.isBefore(picked)) _to = null;
      } else {
        _to = picked;
      }
    });
    _report();
  }

  Widget _button(IconData icon, String text, VoidCallback onTap) =>
      OutlinedButton.icon(
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.allowSeveral) ...[
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('One day')),
              ButtonSegment(value: true, label: Text('Several days')),
            ],
            selected: {_several},
            onSelectionChanged: (s) {
              setState(() => _several = s.first);
              _report();
            },
          ),
          const SizedBox(height: 12),
        ],
        _button(
          Icons.calendar_today_rounded,
          _several ? 'From  ${_fmt.format(_from)}' : _fmt.format(_from),
          () => _pick(true),
        ),
        if (_several) ...[
          const SizedBox(height: 12),
          _button(
            Icons.event_available_rounded,
            _to == null ? 'Select end date' : 'To  ${_fmt.format(_to!)}',
            () => _pick(false),
          ),
        ],
      ],
    );
  }
}

/// Bottom sheet that holds a request form.
Future<T?> showFormSheet<T>(BuildContext context, Widget form) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => form,
    );

/// Padding that keeps a form above the keyboard.
EdgeInsets formPadding(BuildContext context) => EdgeInsets.fromLTRB(
  20,
  0,
  20,
  MediaQuery.viewInsetsOf(context).bottom + 20,
);

class FormError extends StatelessWidget {
  const FormError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.danger, fontSize: 13),
    ),
  );
}

/// "Attach a file (optional)": picks a file the server accepts (picture, PDF,
/// Word or text, up to 10 MB), shows its name and lets the user remove it.
class AttachmentField extends StatelessWidget {
  const AttachmentField({
    super.key,
    required this.value,
    required this.onChanged,
    this.current,
    this.pick,
    this.extensions = Attachment.extensions,
  });

  final Attachment? value;
  final ValueChanged<Attachment?> onChanged;

  /// Name of the file already saved with the request (when editing).
  final String? current;

  /// Opens the picker and returns the file, or throws a message to show.
  /// Left out: the phone's file picker, limited to [extensions].
  final Future<Attachment?> Function()? pick;

  /// The file types the server takes for this request.
  final List<String> extensions;

  Future<void> _choose(BuildContext context) async {
    try {
      final file = await (pick ?? () => _pickAttachment(extensions))();
      if (file != null) onChanged(file);
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final picked = value;
    if (picked != null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Icon(Icons.attach_file_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                picked.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primaryActive,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Remove file',
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => onChanged(null),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () => _choose(context),
          icon: const Icon(Icons.attach_file_rounded, size: 18),
          label: Text(
            current == null ? 'Attach a file (optional)' : 'Replace the file',
          ),
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
        if (current != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Current file: $current. A new file replaces it.',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

Future<Attachment?> _pickAttachment(List<String> extensions) async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: extensions,
  );
  if (file == null) return null;
  final size = await file.length();
  // A picture over the limit may still become small enough once shrunk.
  final isPicture = RegExp(
    r'\.(jpe?g|png)$',
    caseSensitive: false,
  ).hasMatch(file.name);
  if (size != null && size > Attachment.maxBytes && !isPicture) {
    throw const FormatException('The file is too big. The limit is 10 MB.');
  }
  // Pictures from a camera are big: send a smaller copy (it uploads faster).
  final ready = await shrinkIfImage(await file.readAsBytes(), file.name);
  if (ready.bytes.length > Attachment.maxBytes) {
    throw const FormatException('The file is too big. The limit is 10 MB.');
  }
  return Attachment(name: ready.name, bytes: ready.bytes);
}

/// One of the four filters above a list: the number on top, the name under it.
class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.primaryGradient : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? Colors.transparent : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppColors.navy,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white70 : AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
