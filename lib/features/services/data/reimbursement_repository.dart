import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../leave/domain/time_off_models.dart';
import '../domain/reimbursement_models.dart';

abstract class ReimbursementRepository {
  Future<ExpenseData> claims();

  Future<void> add({
    required DateTime date,
    required String reason,
    required int type,
    required num amount,
    Attachment? attachment,
  });

  /// Changes a pending claim (everything is sent again). A new file replaces
  /// the old one; without one the old one stays.
  Future<void> update({
    required String id,
    required DateTime date,
    required String reason,
    required int type,
    required num amount,
    Attachment? attachment,
  });

  Future<List<AmountLogEntry>> amountLog(String id);

  /// The file of a claim. Throws "File Not Found." when there is none.
  Future<({Uint8List bytes, String filename})> attachment(
    String id, {
    String? name,
  });
}

class ApiReimbursementRepository implements ReimbursementRepository {
  ApiReimbursementRepository(this._api);

  final ApiClient _api;

  static final _day = DateFormat('yyyy-MM-dd');

  static List<Map> _rows(dynamic list) =>
      list is List ? list.whereType<Map>().toList() : const [];

  /// `[{"total": "1500"}]`, or `[{"total": null}]` when there is nothing.
  static num _total(dynamic list) {
    final rows = _rows(list);
    if (rows.isEmpty) return 0;
    final t = rows.first['total'];
    return t is num ? t : num.tryParse('$t') ?? 0;
  }

  @override
  Future<ExpenseData> claims() async {
    final data = (await _api.get('my-expense'))['data'];
    if (data is! Map) return const ExpenseData(claims: []);

    final typeList = data['expense_type_list'];
    final types = <int, String>{};
    if (typeList is Map) {
      for (final e in typeList.entries) {
        final id = int.tryParse('${e.key}');
        if (id != null) types[id] = '${e.value}';
      }
    }
    final names = types.isEmpty ? defaultExpenseTypes : types;
    final responded = responseIds(data['responsed_request']);

    return ExpenseData(
      claims: _rows(data['fetch_expense'])
          .map((r) => ExpenseClaim.fromApi(r, responded, names))
          .toList(),
      total: _total(data['fetch_expense_total']),
      approvedTotal: _total(data['fetch_expense_total_approved']),
      paidTotal: _total(data['fetch_expense_total_paid']),
      types: names,
    );
  }

  Map<String, dynamic> _fields(
    DateTime date,
    String reason,
    int type,
    num amount,
  ) => {
    'expense_date': _day.format(date),
    'expense_reason': reason,
    'expense_type': '$type',
    'expense_amount': '$amount',
  };

  static Map<String, MultipartFile> _file(Attachment? a) => a == null
      ? const {}
      : {
          'expense_attachment': MultipartFile.fromBytes(
            a.bytes,
            filename: a.name,
          ),
        };

  @override
  Future<void> add({
    required DateTime date,
    required String reason,
    required int type,
    required num amount,
    Attachment? attachment,
  }) async {
    await _api.post(
      'add-my-expense',
      _fields(date, reason, type, amount),
      _file(attachment),
    );
  }

  @override
  Future<void> update({
    required String id,
    required DateTime date,
    required String reason,
    required int type,
    required num amount,
    Attachment? attachment,
  }) async {
    await _api.post('update-my-expense', {
      'expense_id': id,
      ..._fields(date, reason, type, amount),
    }, _file(attachment));
  }

  @override
  Future<List<AmountLogEntry>> amountLog(String id) async {
    final json = await _api.post('expense-amount-log', {'expense_id': id});
    return _rows(json['data']).map(AmountLogEntry.fromApi).toList();
  }

  @override
  Future<({Uint8List bytes, String filename})> attachment(
    String id, {
    String? name,
  }) => _api.download(
    'download-employee-expense-file?expense_id=$id',
    fallbackName: name ?? 'expense-$id',
  );
}
