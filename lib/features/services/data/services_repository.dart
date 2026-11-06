import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../leave/domain/time_off_models.dart';
import '../domain/service_models.dart';

/// The values the server accepts for `loan_reason`, spelt exactly like this.
const loanReasons = [
  'Bike Loan',
  'Car Loan',
  'Property Loan',
  'Advance Salary',
  'Other',
];

/// What the employee fills in to ask for a loan.
class LoanForm {
  const LoanForm({
    required this.amount,
    required this.reason,
    required this.message,
    required this.percent,
    required this.deduction,
    required this.start,
  });

  final num amount;
  final String reason;
  final String message;

  /// Percent of the salary each month instead of a fixed amount.
  final bool percent;

  /// The monthly amount, or the percent.
  final num deduction;

  /// `YYYY-MM`
  final String start;
}

abstract class ServicesRepository {
  Future<AdvanceData> advances();
  Future<void> submitAdvance({
    required num amount,
    required String payback,
    required String message,
  });
  Future<void> updateAdvance({
    required String id,
    required num amount,
    required String payback,
    required String message,
  });

  Future<LoanData> loans();

  /// Throws the server's message ("Loan request is Pending.") when there is
  /// no detail yet.
  Future<LoanDetail> loanDetail(String id);
  Future<void> submitLoan(LoanForm form);
  Future<void> updateLoan(String id, LoanForm form);

  Future<List<Payslip>> payslips();
  Future<({Uint8List bytes, String filename})> payslipPdf(String id);

  Future<List<Resignation>> resignations();
  Future<void> placeResignation({
    required String reason,
    required DateTime from,
    required DateTime to,
  });
  Future<void> updateResignation({
    required String id,
    required String reason,
    required DateTime from,
    required DateTime to,
  });
}

class ApiServicesRepository implements ServicesRepository {
  ApiServicesRepository(this._api);

  final ApiClient _api;

  static List<Map> _rows(dynamic list) =>
      list is List ? list.whereType<Map>().toList() : const [];

  static num _num(dynamic raw) => raw is num ? raw : num.tryParse('$raw') ?? 0;

  /// `[{"total": 50000}]`, or `[{"total": null}]` when there is nothing.
  static num _total(dynamic list) {
    final rows = _rows(list);
    return rows.isEmpty ? 0 : _num(rows.first['total']);
  }

  @override
  Future<AdvanceData> advances() async {
    final data = (await _api.get('my-salary-request'))['data'];
    if (data is! Map) return const AdvanceData(requests: []);
    final responded = responseIds(data['responsed_request']);
    final salary = _rows(data['employee_salary']);
    return AdvanceData(
      requests: _rows(data['my_requests'])
          .map((r) => AdvanceRequest.fromApi(r, responded))
          .toList(),
      salary: salary.isEmpty ? null : _num(salary.first['salary_amount']),
    );
  }

  Map<String, dynamic> _advanceFields(num amount, String payback, String msg) =>
      {'advance_salary': '$amount', 'payback_date': payback, 'message': msg};

  @override
  Future<void> submitAdvance({
    required num amount,
    required String payback,
    required String message,
  }) async {
    await _api.post(
      'submit_salary_request',
      _advanceFields(amount, payback, message),
    );
  }

  @override
  Future<void> updateAdvance({
    required String id,
    required num amount,
    required String payback,
    required String message,
  }) async {
    await _api.post('update-adv-request', {
      'request_id': id,
      ..._advanceFields(amount, payback, message),
    });
  }

  @override
  Future<LoanData> loans() async {
    final data = (await _api.get('my-loan'))['data'];
    if (data is! Map) return const LoanData(loans: []);
    final responded = responseIds(data['responsed_request']);
    return LoanData(
      loans: _rows(data['all_loans'])
          .map((r) => Loan.fromApi(r, responded))
          .toList(),
      given: _total(data['loan_given_amount']),
      returned: _total(data['loan_return_amount']),
      remaining: _num(data['loan_remaining_amount']),
    );
  }

  @override
  Future<LoanDetail> loanDetail(String id) async {
    final json = await _api.get('my-loan-request-detail/$id');
    final rows = _rows(json['data']);
    final first = rows.isEmpty ? const {} : rows.first;
    return LoanDetail(
      given: _num(first['loan_given_amount']),
      remaining: _num(first['loan_remaining_amount']),
      returned: _num(first['loan_submitted_amount']),
      installments: _rows(json['installments'])
          .map(
            (i) => LoanInstallment(
              amount: _num(i['loan_installment_amount']),
              date: '${i['loan_installment_date']}',
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> _loanFields(LoanForm f) => {
    'loan_amount': '${f.amount}',
    'loan_reason': f.reason,
    'loan_message': f.message,
    'deduction_type': f.percent ? '2' : '1',
    if (f.percent)
      'deduction_percentage': '${f.deduction}'
    else
      'deduction_amount': '${f.deduction}',
    'deduction_start': f.start,
  };

  @override
  Future<void> submitLoan(LoanForm form) async {
    await _api.post('loan-request', _loanFields(form));
  }

  @override
  Future<void> updateLoan(String id, LoanForm form) async {
    await _api.post('update-loan-request', {
      'request_id': id,
      ..._loanFields(form),
    });
  }

  @override
  Future<List<Payslip>> payslips() async {
    final data = (await _api.get('my-payroll'))['data'];
    return _rows(data is Map ? data['fetch_employee_payroll'] : null)
        .map(Payslip.fromApi)
        .toList();
  }

  @override
  Future<({Uint8List bytes, String filename})> payslipPdf(String id) =>
      _api.downloadPayslip(id);

  static final _day = DateFormat('yyyy-MM-dd');

  @override
  Future<List<Resignation>> resignations() async {
    final data = (await _api.get('employee-resignation'))['data'];
    if (data is! Map) return const [];
    final responded = responseIds(data['responsed_request']);
    return _rows(data['resignations'])
        .map((r) => Resignation.fromApi(r, responded))
        .toList();
  }

  @override
  Future<void> placeResignation({
    required String reason,
    required DateTime from,
    required DateTime to,
  }) async {
    await _api.post('add-employee-resignation', {
      'reason': reason,
      'from_date': _day.format(from),
      'to_date': _day.format(to),
    });
  }

  @override
  Future<void> updateResignation({
    required String id,
    required String reason,
    required DateTime from,
    required DateTime to,
  }) async {
    await _api.post('update-employee-resignation', {
      'resignation_id': id,
      'reason': reason,
      'from_date': _day.format(from),
      'to_date': _day.format(to),
    });
  }
}
