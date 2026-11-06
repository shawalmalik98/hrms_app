import 'package:intl/intl.dart';

import '../../leave/domain/time_off_models.dart';

String? _text(dynamic raw) {
  final v = raw?.toString().trim();
  return v == null || v.isEmpty || v == 'null' ? null : v;
}

num _num(dynamic raw) => raw is num ? raw : num.tryParse('$raw') ?? 0;

/// The kinds of expense the server knows (also sent as `expense_type_list`).
const defaultExpenseTypes = {
  1: 'Travel and accommodation',
  2: 'Corporate entertainment',
  3: 'Stationery and consumable goods',
  4: 'Subscriptions',
  5: 'Telephony and home office use',
};

/// One expense claim (reimbursement) of the employee.
class ExpenseClaim {
  const ExpenseClaim({
    required this.id,
    required this.date,
    required this.description,
    required this.typeId,
    required this.typeName,
    required this.amount,
    required this.status,
    required this.paid,
    required this.responded,
    required this.amountChanged,
    this.attachment,
    this.createdAt,
    this.approver,
    this.approvedAt,
    this.reason,
    this.payslipMonth,
    this.payslipYear,
  });

  final String id;
  final DateTime? date;
  final String description;
  final int typeId;
  final String typeName;

  /// The latest amount: HR can change it when approving.
  final num amount;

  /// 1 pending, 2 approved, 3 disapproved.
  final TimeOffStatus status;

  /// Paid out with a payslip.
  final bool paid;

  /// A manager has already answered it.
  final bool responded;

  /// The amount was changed after the claim was made (see the amount history).
  final bool amountChanged;
  final String? attachment;
  final DateTime? createdAt;

  /// Who answered, when, and what they wrote.
  final String? approver;
  final String? approvedAt;
  final String? reason;

  /// The payslip it was paid with.
  final int? payslipMonth;
  final int? payslipYear;

  /// Only the employee's own, pending claim that nobody answered.
  bool get canEdit => status == TimeOffStatus.pending && !responded;

  /// "October 2026" when the claim was paid with that month's payslip.
  String? get payslipLabel =>
      paid && payslipMonth != null && payslipYear != null
      ? DateFormat('MMMM yyyy').format(DateTime(payslipYear!, payslipMonth!))
      : null;

  static ExpenseClaim fromApi(
    Map row,
    Set<String> responded,
    Map<int, String> types,
  ) {
    final id = '${row['emp_expense_id']}';
    final typeId = int.tryParse('${row['emp_expense_type']}') ?? 0;
    return ExpenseClaim(
      id: id,
      date: DateTime.tryParse('${row['emp_expense_date']}'),
      description: _text(row['emp_expense_description']) ?? '',
      typeId: typeId,
      typeName: types[typeId] ?? 'Expense',
      amount: _num(row['emp_expense_amount']),
      status: TimeOffStatus.fromApi(row['emp_expense_approved_by_hr']),
      paid: '${row['emp_expense_reimbursement']}' == '2',
      responded: responded.contains(id),
      amountChanged: _num(row['update_amount']) > 1,
      attachment: _text(row['emp_expense_attachment']),
      createdAt: DateTime.tryParse('${row['emp_expense_created_at']}'),
      approver: _text(row['employee_name']),
      approvedAt: _text(row['emp_expense_approved_by_hr_time']),
      reason: _text(row['emp_expense_approved_by_hr_reason']),
      payslipMonth: int.tryParse('${row['pc_month']}'),
      payslipYear: int.tryParse('${row['pc_year']}'),
    );
  }
}

class ExpenseData {
  const ExpenseData({
    required this.claims,
    this.total = 0,
    this.approvedTotal = 0,
    this.paidTotal = 0,
    this.types = defaultExpenseTypes,
  });

  final List<ExpenseClaim> claims;

  /// Everything claimed / approved / paid. `null` from the server is 0.
  final num total;
  final num approvedTotal;
  final num paidTotal;
  final Map<int, String> types;
}

/// One entry of the history of a claim's amount.
class AmountLogEntry {
  const AmountLogEntry({
    required this.amount,
    required this.by,
    this.at,
    this.code,
  });

  final num amount;
  final String by;
  final String? at;
  final String? code;

  static AmountLogEntry fromApi(Map row) => AmountLogEntry(
    amount: _num(row['emp_expense_amount']),
    by: _text(row['employee_name']) ?? '',
    at: _text(row['emp_expense_create_at']),
    code: _text(row['employee_code']),
  );
}
