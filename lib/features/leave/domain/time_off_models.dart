import 'dart:typed_data';

import 'package:intl/intl.dart';

/// Leave and Work From Home requests share one status: 1 pending, 2 approved,
/// 3 disapproved.
enum TimeOffStatus {
  pending,
  approved,
  disapproved;

  static TimeOffStatus fromApi(dynamic raw) => switch ('$raw') {
    '2' => approved,
    '3' => disapproved,
    _ => pending,
  };

  String get label => switch (this) {
    pending => 'Pending',
    approved => 'Approved',
    disapproved => 'Disapproved',
  };
}

class LeaveType {
  const LeaveType({required this.id, required this.name});

  final String id;
  final String name;

  static LeaveType? fromApi(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['leave_manage_id']?.toString();
    final name = raw['leave_name']?.toString();
    if (id == null || name == null) return null;
    return LeaveType(id: id, name: name);
  }
}

/// `dd-MM-yyyy HH:mm:ss`, how the server writes "request sent on".
DateTime? _sentOn(dynamic raw) {
  try {
    return DateFormat('dd-MM-yyyy HH:mm:ss').parse('$raw');
  } catch (_) {
    return null;
  }
}

String? _text(dynamic raw) {
  final v = raw?.toString().trim();
  return v == null || v.isEmpty || v == 'null' ? null : v;
}

/// One day of a leave. A leave over several days comes as one row per day.
class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.date,
    required this.typeName,
    required this.reason,
    required this.status,
    this.sentOn,
    this.decision,
    this.attachment,
    this.typeId,
    this.responded = false,
  });

  final String id;
  final DateTime? date;
  final String typeName;
  final String? typeId;

  /// A manager has already answered it.
  final bool responded;
  final String reason;
  final TimeOffStatus status;
  final DateTime? sentOn;

  /// Who answered and when, as written by the server.
  final String? decision;
  final String? attachment;

  /// Only the employee's own, pending request that nobody answered.
  bool get canEdit => status == TimeOffStatus.pending && !responded;

  static LeaveRequest fromApi(Map row, [Set<String> responded = const {}]) =>
      LeaveRequest(
        id: '${row['leave_applied_id']}',
        typeId: _text(row['leave_manage_id']),
        responded: responded.contains('${row['leave_applied_id']}'),
        date: DateTime.tryParse('${row['leave_applied_for_date']}'),
        typeName: _text(row['leave_name']) ?? 'Leave',
        reason: _text(row['leave_applied_reason']) ?? '',
        status: TimeOffStatus.fromApi(row['leave_approved_by_hr']),
        sentOn: _sentOn(row['leave_applied_date']),
        decision: _text(row['leave_approved_date_hr']),
        attachment: _text(row['leave_applied_attachment']),
      );
}

class WfhRequest {
  const WfhRequest({
    required this.id,
    required this.date,
    required this.reason,
    required this.status,
    this.sentOn,
    this.decision,
  });

  final String id;
  final DateTime? date;
  final String reason;
  final TimeOffStatus status;
  final DateTime? sentOn;
  final String? decision;

  static WfhRequest fromApi(Map row) => WfhRequest(
    id: '${row['wfh_request_id']}',
    date: DateTime.tryParse('${row['wfh_request_date']}'),
    reason: _text(row['wfh_request_message']) ?? '',
    status: TimeOffStatus.fromApi(row['wfh_request_approved_by_hr']),
    sentOn: _sentOn(row['wfh_request_submition_date']),
    decision: _text(row['wfh_request_approved_date_hr']),
  );
}

/// IDs of the requests a manager has already answered (`responsed_request`).
/// Such a request cannot be edited any more. An entry is an id, or an object
/// holding it.
Set<String> responseIds(dynamic list) {
  if (list is! List) return const {};
  return {
    for (final e in list)
      if (e is Map) ...e.values.map((v) => '$v') else '$e',
  };
}

/// A file picked for a leave (medical certificate, etc.).
class Attachment {
  const Attachment({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  /// What the server accepts.
  static const extensions = ['jpg', 'jpeg', 'png', 'pdf', 'docx', 'txt'];

  /// A reimbursement also takes spreadsheets.
  static const expenseExtensions = [...extensions, 'xlsx', 'csv'];

  /// The server's limit is about 10 MB.
  static const maxBytes = 10 * 1024 * 1024;
}
