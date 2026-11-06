import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'dart:async';

import '../../../core/files/file_viewer.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../leave/domain/time_off_models.dart';
import '../../leave/presentation/time_off_widgets.dart';
import '../application/services_providers.dart';
import '../domain/help_desk_models.dart';
import 'service_widgets.dart';

final _when = DateFormat('dd MMM yyyy, hh:mm a');

class TicketChip extends StatelessWidget {
  const TicketChip(this.status, {super.key});

  final TicketStatus status;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
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

class HelpDeskScreen extends ConsumerWidget {
  const HelpDeskScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(ticketsProvider);

    return ServiceScaffold(
      title: 'Help Desk',
      body: TimeOffTab<Ticket>(
        value: data.whenData((d) => d.tickets),
        onRefresh: () async {
          ref.invalidate(ticketsProvider);
          await ref.read(ticketsProvider.future);
        },
        statusOf: (_) => TimeOffStatus.pending,
        showFilters: false,
        emptyText: 'No tickets yet.',
        applyLabel: 'RAISE A TICKET',
        // Always there. The departments come with the tickets: if they did not
        // load yet, load them again and ask to try once more.
        onApply: () {
          if (!data.hasValue) {
            ref.invalidate(ticketsProvider);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Loading the departments. Please try again.'),
              ),
            );
            return;
          }
          showFormSheet<void>(
            context,
            TicketForm(departments: data.value!.departments),
          );
        },
        cardBuilder: (t) => RequestCard(
          icon: Icons.support_agent_rounded,
          accent: t.status.color,
          title: 'Ticket #${t.id}',
          status: TimeOffStatus.pending,
          // The status has a long name: it gets its own line.
          chip: const SizedBox.shrink(),
          subtitle: t.createdAt == null ? null : _when.format(t.createdAt!),
          lines: [
            if (t.message.isNotEmpty) t.message,
            if (t.attachment != null) '📎 ${t.attachment}',
          ],
          footer: Row(
            children: [
              TicketChip(t.status),
              const Spacer(),
              if (t.attachment != null)
                DownloadButton(ticket: t, compact: true),
            ],
          ),
          // Only a ticket that is still pending can be changed.
          onEdit: t.status == TicketStatus.pending
              ? () => showFormSheet<void>(
                  context,
                  TicketForm(
                    departments: data.value?.departments ?? const [],
                    existing: t,
                  ),
                )
              : null,
          onTap: () => showFormSheet<void>(
            context,
            TicketDetailSheet(
              ticket: t,
              departments: data.value?.departments ?? const [],
              onEdit: (ticket) => showFormSheet<void>(
                context,
                TicketForm(
                  departments: data.value?.departments ?? const [],
                  existing: ticket,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A ticket's message, who it went to and every change of its status.
class TicketDetailSheet extends ConsumerWidget {
  const TicketDetailSheet({
    super.key,
    required this.ticket,
    required this.departments,
    required this.onEdit,
  });

  final Ticket ticket;
  final List<HelpDeskDepartment> departments;

  /// Opens the edit form (from the screen behind this sheet).
  final void Function(Ticket ticket) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(ticketDetailProvider(ticket.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: SingleChildScrollView(
        child: detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              e is ApiException ? e.message : 'Could not load the ticket.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.body, fontSize: 15),
            ),
          ),
          data: (d) {
            final names = [
              for (final dep in departments)
                if (d.departmentIds.contains(dep.id)) dep.name,
            ];
            final sentTo = [
              if (d.peopleCount > 0)
                '${d.peopleCount} ${d.peopleCount == 1 ? 'person' : 'people'}'
              else if (names.isNotEmpty)
                'Managers of ${names.join(', ')}',
            ].join();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ticket #${ticket.id}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    TicketChip(
                      d.history.isEmpty ? ticket.status : d.history.last.status,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.message.isEmpty ? ticket.message : d.message,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (d.attachment != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.attach_file_rounded,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                d.attachment!,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (sentTo.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Sent to: $sentTo',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (d.history.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'Status history',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < d.history.length; i++)
                    _Step(step: d.history[i], last: i == d.history.length - 1),
                ],
                if ((d.attachment ?? ticket.attachment) != null) ...[
                  const SizedBox(height: 12),
                  DownloadButton(ticket: ticket, name: d.attachment),
                ],
                // Only a ticket that is still pending can be changed.
                if ((d.history.isEmpty
                        ? ticket.status
                        : d.history.last.status) ==
                    TicketStatus.pending) ...[
                  const SizedBox(height: 10),
                  GradientButton(
                    label: 'EDIT TICKET',
                    icon: Icons.edit_rounded,
                    onPressed: () {
                      Navigator.pop(context);
                      onEdit(ticket);
                    },
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.step, required this.last});

  final TicketStep step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = step.status.color;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!last)
                  Expanded(child: Container(width: 2, color: AppColors.border)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.status.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                  Text(
                    [
                      if (step.by.isNotEmpty) step.by,
                      if (step.time != null) _when.format(step.time!),
                    ].join('  •  '),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A new ticket: the message, the departments (the managers of those get it),
/// optionally the exact people, and an optional file.
class TicketForm extends ConsumerStatefulWidget {
  const TicketForm({super.key, required this.departments, this.existing});

  final List<HelpDeskDepartment> departments;

  /// Set when a pending ticket is being edited.
  final Ticket? existing;

  @override
  ConsumerState<TicketForm> createState() => _TicketFormState();
}

class _TicketFormState extends ConsumerState<TicketForm> {
  final _message = TextEditingController();
  final _departments = <String>{};
  final _people = <String>{};
  List<TicketPerson> _available = const [];
  bool _loadingPeople = false;
  bool _loadingTicket = false;
  Attachment? _file;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) _fill(widget.existing!);
  }

  /// Editing: the message, departments and people of the ticket as they are.
  Future<void> _fill(Ticket ticket) async {
    setState(() => _loadingTicket = true);
    try {
      final d = await ref.read(ticketDetailProvider(ticket.id).future);
      if (!mounted) return;
      setState(() {
        _message.text = d.message.isEmpty ? ticket.message : d.message;
        _departments.addAll(d.departmentIds);
        _people.addAll(d.employeeIds);
      });
      final found = await ref
          .read(helpDeskRepositoryProvider)
          .peopleOf(_departments.toList());
      if (mounted) setState(() => _available = found);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Could not load the ticket.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingTicket = false);
    }
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _toggleDepartment(String id, bool on) async {
    setState(() {
      on ? _departments.add(id) : _departments.remove(id);
      _loadingPeople = _departments.isNotEmpty;
    });
    if (_departments.isEmpty) {
      setState(() {
        _available = const [];
        _people.clear();
      });
      return;
    }
    final asked = {..._departments};
    try {
      final found = await ref
          .read(helpDeskRepositoryProvider)
          .peopleOf(asked.toList());
      if (!mounted || !asked.containsAll(_departments)) return;
      setState(() {
        _available = found;
        // Keep only the people who are still in the chosen departments.
        _people.removeWhere((p) => !found.any((f) => f.id == p));
      });
    } catch (_) {
      if (mounted) setState(() => _available = const []);
    } finally {
      if (mounted) setState(() => _loadingPeople = false);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_message.text.trim().isEmpty) {
      setState(() => _error = 'Please write your message.');
      return;
    }
    if (_departments.isEmpty) {
      setState(() => _error = 'Please choose a department.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(helpDeskRepositoryProvider);
      final existing = widget.existing;
      if (existing == null) {
        await repo.addTicket(
          message: _message.text.trim(),
          departmentIds: _departments.toList(),
          employeeIds: _people.toList(),
          attachment: _file,
        );
      } else {
        await repo.updateTicket(
          id: existing.id,
          message: _message.text.trim(),
          departmentIds: _departments.toList(),
          employeeIds: _people.toList(),
          attachment: _file,
        );
        ref.invalidate(ticketDetailProvider(existing.id));
      }
      ref.invalidate(ticketsProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send the ticket.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _chips<T>(
    List<T> items,
    String Function(T) label,
    String Function(T) id,
    Set<String> selected,
    void Function(String, bool) onChange,
  ) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final item in items)
        FilterChip(
          label: Text(label(item)),
          selected: selected.contains(id(item)),
          onSelected: (on) => onChange(id(item), on),
          showCheckmark: false,
          selectedColor: AppColors.primary,
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.border),
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected.contains(id(item)) ? Colors.white : AppColors.body,
          ),
        ),
    ],
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
            if (_loadingTicket)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            TextField(
              controller: _message,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Describe the problem',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Send to department',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.departments.isEmpty)
              const Text(
                'No departments available.',
                style: TextStyle(color: AppColors.muted),
              )
            else
              _chips<HelpDeskDepartment>(
                widget.departments,
                (d) => d.name,
                (d) => d.id,
                _departments,
                _toggleDepartment,
              ),
            if (_loadingPeople)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: LinearProgressIndicator(minHeight: 3),
              )
            else if (_available.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Send to specific people (optional)',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const Text(
                'If you choose nobody, the department managers get it.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              _chips<TicketPerson>(
                _available,
                (p) => p.name,
                (p) => p.id,
                _people,
                (id, on) =>
                    setState(() => on ? _people.add(id) : _people.remove(id)),
              ),
            ],
            const SizedBox(height: 16),
            AttachmentField(
              value: _file,
              current: widget.existing?.attachment,
              onChanged: (f) => setState(() => _file = f),
            ),
            if (_error != null) FormError(_error!),
            const SizedBox(height: 16),
            GradientButton(
              label: widget.existing == null ? 'SEND TICKET' : 'SAVE CHANGES',
              loading: _busy || _loadingTicket,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Downloads the file of a ticket and opens it with the phone's viewer.
class DownloadButton extends ConsumerStatefulWidget {
  const DownloadButton({
    super.key,
    required this.ticket,
    this.name,
    this.compact = false,
  });

  final Ticket ticket;

  /// The file's name, when the detail gave a newer one than the list.
  final String? name;

  /// Just an icon (on a list card).
  final bool compact;

  @override
  ConsumerState<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends ConsumerState<DownloadButton> {
  bool _busy = false;

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ref
          .read(helpDeskRepositoryProvider)
          .attachment(
            widget.ticket.id,
            name: widget.name ?? widget.ticket.attachment,
          );
      if (!mounted) return;
      await openFile(context, file.bytes, file.filename);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      // Not one of the server's messages: say what it was, to be fixed.
      final detail = '$e'.replaceAll(RegExp(r'\s+'), ' ');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the file. (${detail.length > 120 ? detail.substring(0, 120) : detail})',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spinner = const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    if (widget.compact) {
      return IconButton(
        tooltip: 'Download attachment',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(),
        padding: const EdgeInsets.all(6),
        onPressed: _busy ? null : _download,
        icon: _busy
            ? spinner
            : const Icon(Icons.download_rounded, color: AppColors.primary),
      );
    }
    return OutlinedButton.icon(
      onPressed: _busy ? null : _download,
      icon: _busy ? spinner : const Icon(Icons.download_rounded, size: 18),
      label: Text(_busy ? 'Downloading...' : 'Download attachment'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
