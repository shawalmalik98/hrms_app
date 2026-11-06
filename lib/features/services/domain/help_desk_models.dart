import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

String? _text(dynamic raw) {
  final v = raw?.toString().trim();
  return v == null || v.isEmpty || v == 'null' ? null : v;
}

enum TicketStatus {
  pending('Ticket Pending', AppColors.muted),
  open('Ticket Open', AppColors.info),
  rejected('Ticket Rejected', AppColors.danger),
  resolvedByDepartment('Resolved From Department', AppColors.primary),
  resolvedByEmployee('Resolved From Employee', AppColors.primary);

  const TicketStatus(this.label, this.color);

  final String label;
  final Color color;

  static TicketStatus fromApi(dynamic raw) => switch ('$raw') {
    '2' => open,
    '3' => rejected,
    '4' => resolvedByDepartment,
    '5' => resolvedByEmployee,
    _ => pending,
  };
}

class Ticket {
  const Ticket({
    required this.id,
    required this.message,
    required this.status,
    this.attachment,
    this.createdAt,
  });

  final String id;
  final String message;
  final TicketStatus status;
  final String? attachment;
  final DateTime? createdAt;

  static Ticket fromApi(Map row) => Ticket(
    id: '${row['help_desk_id']}',
    message: _text(row['help_message']) ?? '',
    status: TicketStatus.fromApi(row['ticket_status']),
    attachment: _text(row['help_attachment']),
    createdAt: DateTime.tryParse('${row['created_time']}'),
  );
}

class HelpDeskDepartment {
  const HelpDeskDepartment({required this.id, required this.name});

  final String id;
  final String name;

  static HelpDeskDepartment? fromApi(dynamic raw) {
    if (raw is! Map) return null;
    final id = _text(raw['department_id']);
    final name = _text(raw['department_name']);
    return id == null || name == null
        ? null
        : HelpDeskDepartment(id: id, name: name);
  }
}

class TicketsData {
  const TicketsData({required this.tickets, required this.departments});

  final List<Ticket> tickets;

  /// For the department choice of a new ticket.
  final List<HelpDeskDepartment> departments;
}

/// A colleague a ticket can be sent to (instead of the department managers).
class TicketPerson {
  const TicketPerson({
    required this.id,
    required this.code,
    required this.name,
  });

  final String id;
  final String code;
  final String name;

  static TicketPerson? fromApi(dynamic raw) {
    if (raw is! Map) return null;
    final id = _text(raw['employee_id']);
    final name = _text(raw['employee_name']);
    return id == null || name == null
        ? null
        : TicketPerson(
            id: id,
            code: _text(raw['employee_code']) ?? '',
            name: name,
          );
  }
}

/// One change of a ticket's status: who, to what, when.
class TicketStep {
  const TicketStep({required this.by, required this.status, this.time});

  final String by;
  final TicketStatus status;
  final DateTime? time;
}

class TicketDetail {
  const TicketDetail({
    required this.message,
    required this.history,
    required this.departmentIds,
    required this.employeeIds,
    this.employeeName,
    this.createdAt,
    this.attachment,
  });

  final String message;
  final String? employeeName;
  final DateTime? createdAt;
  final String? attachment;

  /// Oldest first.
  final List<TicketStep> history;
  final Set<String> departmentIds;

  /// The people the ticket was sent to (empty: the department managers).
  final Set<String> employeeIds;

  int get peopleCount => employeeIds.length;
}
