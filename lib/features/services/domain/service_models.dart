import 'package:intl/intl.dart';

import '../../leave/domain/time_off_models.dart';

String? _text(dynamic raw) {
  final v = raw?.toString().trim();
  return v == null || v.isEmpty || v == 'null' ? null : v;
}

num _num(dynamic raw) => raw is num ? raw : num.tryParse('$raw') ?? 0;

/// `1,234` style amount with the currency in front.
String rs(num amount) => 'Rs ${NumberFormat('#,##0').format(amount)}';

/// `2026-12` as "December 2026".
String monthLabel(String? yearMonth) {
  final d = DateTime.tryParse('${yearMonth ?? ''}-01');
  return d == null ? (yearMonth ?? '') : DateFormat('MMMM yyyy').format(d);
}

class AdvanceRequest {
  const AdvanceRequest({
    required this.id,
    required this.period,
    required this.amount,
    required this.message,
    required this.status,
    required this.responded,
    this.decision,
    this.approverMessage,
    this.createdAt,
  });

  final String id;

  /// `YYYY-MM`, the salary the advance is taken from.
  final String period;
  final num amount;
  final String message;
  final TimeOffStatus status;
  final bool responded;
  final String? decision;
  final String? approverMessage;
  final String? createdAt;

  /// Only the employee's own, pending request that nobody answered.
  bool get canEdit => status == TimeOffStatus.pending && !responded;

  static AdvanceRequest fromApi(Map row, Set<String> responded) {
    final id = '${row['advance_salary_request_id']}';
    return AdvanceRequest(
      id: id,
      period: _text(row['effective_payroll_period']) ?? '',
      amount: _num(row['advance_salary_amount']),
      message: _text(row['request_message']) ?? '',
      status: TimeOffStatus.fromApi(row['request_approved_by_finance']),
      responded: responded.contains(id),
      decision: _text(row['request_approved_date_finance']),
      approverMessage: _text(row['request_aprrover_message']),
      createdAt: _text(row['request_created_at']),
    );
  }
}

class AdvanceData {
  const AdvanceData({required this.requests, this.salary});

  final List<AdvanceRequest> requests;

  /// An advance cannot be more than this.
  final num? salary;
}

class Loan {
  const Loan({
    required this.id,
    required this.reason,
    required this.message,
    required this.amount,
    required this.percentDeduction,
    required this.deduction,
    required this.start,
    required this.status,
    required this.responded,
    this.decision,
    this.approverMessage,
    this.appliedOn,
  });

  final String id;
  final String reason;
  final String message;
  final num amount;

  /// `loan_deduction_type` 2: a percent of the salary each month, otherwise a
  /// fixed amount.
  final bool percentDeduction;
  final num deduction;

  /// `YYYY-MM`
  final String start;
  final TimeOffStatus status;
  final bool responded;
  final String? decision;
  final String? approverMessage;
  final String? appliedOn;

  bool get canEdit => status == TimeOffStatus.pending && !responded;

  String get deductionLabel =>
      percentDeduction ? '$deduction% of salary' : '${rs(deduction)} a month';

  static Loan fromApi(Map row, Set<String> responded) {
    final id = '${row['loan_request_id']}';
    return Loan(
      id: id,
      reason: _text(row['loan_reason']) ?? 'Loan',
      message: _text(row['loan_reason_message']) ?? '',
      amount: _num(row['loan_request_amount']),
      percentDeduction: '${row['loan_deduction_type']}' == '2',
      deduction: _num(row['loan_deduction_amount']),
      start: _text(row['loan_deduction_start']) ?? '',
      status: TimeOffStatus.fromApi(row['request_approved_by_finance']),
      responded: responded.contains(id),
      decision: _text(row['request_approved_date_finance']),
      approverMessage: _text(row['request_aprrover_message']),
      appliedOn: _text(row['loan_applied_date']),
    );
  }
}

class LoanData {
  const LoanData({
    required this.loans,
    this.given = 0,
    this.returned = 0,
    this.remaining = 0,
  });

  final List<Loan> loans;
  final num given;
  final num returned;
  final num remaining;
}

class LoanInstallment {
  const LoanInstallment({required this.amount, required this.date});

  final num amount;
  final String date;
}

/// Only an approved loan has a detail; otherwise the server says why not and
/// the repository throws that message.
class LoanDetail {
  const LoanDetail({
    required this.given,
    required this.remaining,
    required this.returned,
    required this.installments,
  });

  final num given;
  final num remaining;
  final num returned;
  final List<LoanInstallment> installments;
}

class Payslip {
  const Payslip({
    required this.id,
    required this.month,
    required this.year,
    required this.gross,
    required this.extra,
    required this.deduction,
    required this.net,
  });

  /// `pc_id`, what the PDF is asked by.
  final String id;
  final int month;
  final int year;
  final num gross;
  final num extra;
  final num deduction;
  final num net;

  String get title => DateFormat('MMMM yyyy').format(DateTime(year, month));

  static Payslip fromApi(Map row) => Payslip(
    id: '${row['pc_id']}',
    month: int.tryParse('${row['pc_month']}') ?? 1,
    year: int.tryParse('${row['pc_year']}') ?? 2000,
    gross: _num(row['pc_employee_gross_salary']),
    extra: _num(row['pc_employee_extra_salary']),
    deduction: _num(row['pc_employee_deduction']),
    net: _num(row['pc_employee_net_salary']),
  );
}

/// The employee's own resignation. Only one can be pending or approved at a
/// time.
class Resignation {
  const Resignation({
    required this.id,
    required this.reason,
    required this.from,
    required this.to,
    required this.status,
    required this.responded,
    this.approverMessage,
    this.decision,
  });

  final String id;
  final String reason;
  final DateTime? from;
  final DateTime? to;
  final TimeOffStatus status;

  /// A manager has already answered it.
  final bool responded;
  final String? approverMessage;

  /// "Approved By : ..., at : ..." once HR has answered.
  final String? decision;

  /// Only the employee's own, pending resignation that nobody answered.
  bool get canEdit => status == TimeOffStatus.pending && !responded;

  /// A pending or approved resignation stops a new one being placed.
  bool get blocksNew => status != TimeOffStatus.disapproved;

  static Resignation fromApi(Map row, Set<String> responded) {
    final id = '${row['resignation_id']}';
    return Resignation(
      id: id,
      reason: _text(row['resignation_description']) ?? '',
      from: DateTime.tryParse('${row['resignation_from_date']}'),
      to: DateTime.tryParse('${row['resignation_to_date']}'),
      status: TimeOffStatus.fromApi(row['resignation_status']),
      responded: responded.contains(id),
      approverMessage: _text(row['request_aprroved_message']),
      decision: _text(row['request_approved_date_hr']),
    );
  }
}
