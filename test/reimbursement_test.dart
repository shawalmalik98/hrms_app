import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/network/api_client.dart';
import 'package:hrms_app/core/storage/session_store.dart';
import 'package:hrms_app/features/leave/data/time_off_repository.dart';
import 'package:hrms_app/features/leave/domain/time_off_models.dart';
import 'package:hrms_app/features/services/application/services_providers.dart';
import 'package:hrms_app/features/services/data/reimbursement_repository.dart';
import 'package:hrms_app/features/services/domain/reimbursement_models.dart';
import 'package:hrms_app/features/services/presentation/reimbursement_screen.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.bodies, {this.types = const {}, this.disposition = const {}});

  final Map<String, String> bodies;
  final Map<String, String> types;
  final Map<String, String> disposition;
  final sent = <String, Map<String, String>>{};
  final files = <String, Map<String, String>>{};
  final queries = <String, Map<String, String>>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst(RegExp(r'^/api/v1/'), '');
    final data = options.data;
    if (data is FormData) {
      sent[path] = {for (final f in data.fields) f.key: f.value};
      files[path] = {for (final f in data.files) f.key: f.value.filename ?? ''};
    }
    queries[path] = options.uri.queryParameters;
    return ResponseBody.fromBytes(
      utf8.encode(bodies[path] ?? '{"status":false,"message":"unknown"}'),
      200,
      headers: {
        Headers.contentTypeHeader: [types[path] ?? Headers.jsonContentType],
        if (disposition[path] != null)
          'content-disposition': [disposition[path]!],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(_Adapter a) => ApiClient(
  session: SessionStore(),
  onUnauthorized: () {},
  dio: Dio(BaseOptions(baseUrl: 'http://test/api/v1/'))..httpClientAdapter = a,
);

const _list = '''
{"status":true,"message":"My Expense","data":{
 "fetch_expense":[
  {"emp_expense_id":15,"emp_expense_date":"2026-11-04",
   "emp_expense_description":"Taxi to client office","emp_expense_type":1,
   "emp_expense_amount":"1500","emp_expense_approved_by_hr":1,
   "emp_expense_reimbursement":1,"emp_expense_created_at":"2026-11-05 14:10:00",
   "emp_expense_attachment":"20261105141000_aB3dE9_bill.pdf",
   "employee_name":null,"emp_expense_approved_by_hr_time":null,
   "emp_expense_approved_by_hr_reason":null,"update_amount":1,
   "pc_id":null,"pc_month":null,"pc_year":null,"disburse":null},
  {"emp_expense_id":16,"emp_expense_date":"2026-11-03",
   "emp_expense_description":"Printer paper","emp_expense_type":3,
   "emp_expense_amount":"800","emp_expense_approved_by_hr":1,
   "emp_expense_reimbursement":1,"emp_expense_attachment":null,
   "update_amount":1},
  {"emp_expense_id":17,"emp_expense_date":"2026-10-20",
   "emp_expense_description":"Hotel","emp_expense_type":1,
   "emp_expense_amount":"9000","emp_expense_approved_by_hr":2,
   "emp_expense_reimbursement":2,"employee_name":"Zeeshan",
   "emp_expense_approved_by_hr_time":"21-10-2026 10:00",
   "emp_expense_approved_by_hr_reason":"Approved with a lower amount",
   "update_amount":2,"pc_month":10,"pc_year":2026,"disburse":2}
 ],
 "fetch_expense_total":[{"total":"11300"}],
 "fetch_expense_total_approved":[{"total":"9000"}],
 "fetch_expense_total_paid":[{"total":null}],
 "expense_type_list":{"1":"Travel and accommodation","2":"Corporate entertainment","3":"Stationery and consumable goods","4":"Subscriptions","5":"Telephony and home office use"},
 "responsed_request":[16]}}
''';

_Adapter _server() => _Adapter(
  {
    'my-expense': _list,
    'add-my-expense':
        '{"status":true,"message":"Reimbursement Added Successfully."}',
    'update-my-expense':
        '{"status":true,"message":"Reimbursement Updated Successfully."}',
    'expense-amount-log':
        '{"status":true,"message":"Get amount log.","data":['
        '{"emp_expense_amount":"1500","employee_name":"Ali Raza",'
        '"emp_expense_create_at":"2026-11-05 14:10:00","employee_code":"1000001"},'
        '{"emp_expense_amount":"9000","employee_name":"Zeeshan",'
        '"emp_expense_create_at":"2026-10-21 10:00:00","employee_code":"1000004"}]}',
    'download-employee-expense-file': '%PDF-1.4 bill',
  },
  types: {'download-employee-expense-file': 'application/pdf'},
  disposition: {
    'download-employee-expense-file': 'attachment; filename="bill.pdf"',
  },
);

class _Fake implements ReimbursementRepository {
  _Fake(this.adapter);

  final _Adapter adapter;
  late final _real = ApiReimbursementRepository(_client(adapter));

  @override
  Future<ExpenseData> claims() => _real.claims();

  @override
  Future<void> add({
    required DateTime date,
    required String reason,
    required int type,
    required num amount,
    Attachment? attachment,
  }) => _real.add(
    date: date,
    reason: reason,
    type: type,
    amount: amount,
    attachment: attachment,
  );

  @override
  Future<void> update({
    required String id,
    required DateTime date,
    required String reason,
    required int type,
    required num amount,
    Attachment? attachment,
  }) => _real.update(
    id: id,
    date: date,
    reason: reason,
    type: type,
    amount: amount,
    attachment: attachment,
  );

  @override
  Future<List<AmountLogEntry>> amountLog(String id) => _real.amountLog(id);

  @override
  Future<({Uint8List bytes, String filename})> attachment(
    String id, {
    String? name,
  }) => _real.attachment(id, name: name);
}

Widget _host(_Adapter a) => ProviderScope(
  overrides: [reimbursementRepositoryProvider.overrideWithValue(_Fake(a))],
  child: const MaterialApp(home: ReimbursementScreen()),
);

void main() {
  group('reimbursement data', () {
    test('claims, totals, types and who can edit are read', () async {
      final data = await ApiReimbursementRepository(_client(_server()))
          .claims();

      expect(data.claims, hasLength(3));
      expect(data.total, 11300);
      expect(data.approvedTotal, 9000);
      expect(data.paidTotal, 0); // null from the server is 0
      expect(data.types[1], 'Travel and accommodation');

      final taxi = data.claims[0];
      expect(taxi.amount, 1500);
      expect(taxi.typeName, 'Travel and accommodation');
      expect(taxi.date, DateTime(2026, 11, 4));
      expect(taxi.status, TimeOffStatus.pending);
      expect(taxi.canEdit, isTrue);
      expect(taxi.paid, isFalse);
      expect(taxi.amountChanged, isFalse);
      expect(taxi.attachment, '20261105141000_aB3dE9_bill.pdf');

      // Pending, but a manager has answered: no edit.
      expect(data.claims[1].canEdit, isFalse);
      expect(data.claims[1].attachment, isNull);

      final hotel = data.claims[2];
      expect(hotel.status, TimeOffStatus.approved);
      expect(hotel.canEdit, isFalse);
      expect(hotel.paid, isTrue);
      expect(hotel.payslipLabel, 'October 2026');
      expect(hotel.amountChanged, isTrue);
      expect(hotel.approver, 'Zeeshan');
      expect(hotel.reason, 'Approved with a lower amount');
    });

    test('a new claim is sent with its file', () async {
      final adapter = _server();
      await ApiReimbursementRepository(_client(adapter)).add(
        date: DateTime(2026, 11, 4),
        reason: 'Taxi to client office',
        type: 1,
        amount: 1500,
        attachment: Attachment(
          name: 'bill.pdf',
          bytes: Uint8List.fromList([1, 2]),
        ),
      );
      expect(adapter.sent['add-my-expense'], {
        'expense_date': '2026-11-04',
        'expense_reason': 'Taxi to client office',
        'expense_type': '1',
        'expense_amount': '1500',
      });
      expect(adapter.files['add-my-expense'], {
        'expense_attachment': 'bill.pdf',
      });
    });

    test(
      'a change sends everything with the claim id, no file = old stays',
      () async {
        final adapter = _server();
        await ApiReimbursementRepository(_client(adapter)).update(
          id: '15',
          date: DateTime(2026, 11, 4),
          reason: 'Taxi and parking',
          type: 1,
          amount: 1800,
        );
        expect(adapter.sent['update-my-expense'], {
          'expense_id': '15',
          'expense_date': '2026-11-04',
          'expense_reason': 'Taxi and parking',
          'expense_type': '1',
          'expense_amount': '1800',
        });
        expect(adapter.files['update-my-expense'], isEmpty);
      },
    );

    test('the server refuses a claim that is no longer pending', () async {
      final repo = ApiReimbursementRepository(
        _client(
          _Adapter({
            'update-my-expense': '{"status":false,"message":"You can\'t update this request now because your reporting authority has changed its status.","data":""}',
          }),
        ),
      );
      expect(
        repo.update(
          id: '16',
          date: DateTime(2026, 11, 4),
          reason: 'x',
          type: 1,
          amount: 5,
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('reporting authority'),
          ),
        ),
      );
    });

    test('the amount history is read', () async {
      final log = await ApiReimbursementRepository(_client(_server()))
          .amountLog('17');
      expect(log.map((e) => e.amount), [1500, 9000]);
      expect(log.last.by, 'Zeeshan');
    });

    test(
      'the file is asked for by the claim id and comes back as a file',
      () async {
        final adapter = _server();
        final file = await ApiReimbursementRepository(_client(adapter))
            .attachment('15');
        expect(adapter.queries['download-employee-expense-file'], {
          'expense_id': '15',
        });
        expect(file.filename, 'bill.pdf');
        expect(String.fromCharCodes(file.bytes), startsWith('%PDF'));
      },
    );

    test('"File Not Found." is shown instead of a file', () async {
      final repo = ApiReimbursementRepository(
        _client(
          _Adapter({
            'download-employee-expense-file':
                '{"status":false,"message":"File Not Found."}',
          }),
        ),
      );
      expect(
        repo.attachment('15'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'File Not Found.',
          ),
        ),
      );
    });
  });

  group('leave attachment download', () {
    test('the leave id is sent and the file comes back', () async {
      final adapter = _Adapter(
        {'download-leave-file': '%PDF-1.4 certificate'},
        types: {'download-leave-file': 'application/pdf'},
        disposition: {
          'download-leave-file': 'attachment; filename="certificate.pdf"',
        },
      );
      final file = await ApiTimeOffRepository(_client(adapter))
          .attachment('90');
      expect(adapter.queries['download-leave-file'], {'leave_id': '90'});
      expect(file.filename, 'certificate.pdf');
    });

    test('a file the server cannot find gives its message', () async {
      final repo = ApiTimeOffRepository(
        _client(
          _Adapter({
            'download-leave-file':
                '{"status":false,"message":"File Not Found."}',
          }),
        ),
      );
      expect(
        repo.attachment('90'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'File Not Found.',
          ),
        ),
      );
    });
  });

  group('reimbursement screen', () {
    testWidgets('lists the claims with totals, Paid and who may edit', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(_server()));
      await tester.pumpAndSettle();

      expect(find.text('NEW CLAIM'), findsOneWidget);
      // The totals.
      expect(find.text('Rs 11,300'), findsOneWidget);
      expect(find.text('Claimed'), findsOneWidget);
      // The claims.
      expect(find.text('Rs 1,500'), findsOneWidget);
      expect(find.text('Rs 9,000'), findsWidgets);
      expect(find.text('Taxi to client office'), findsOneWidget);
      expect(find.text('Paid'), findsWidgets);
      expect(
        find.textContaining('Paid with the October 2026 payslip'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Approved with a lower amount'),
        findsOneWidget,
      );
      // Only the first claim can be edited.
      expect(find.byTooltip('Edit'), findsOneWidget);
      // The amount was changed on the third.
      expect(find.text('Amount history'), findsOneWidget);
      // Only the first one has a file.
      expect(find.byTooltip('Download attachment'), findsOneWidget);
    });

    testWidgets('the amount history opens', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(_server()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Amount history'));
      await tester.pumpAndSettle();
      expect(find.text('Rs 1,500'), findsWidgets);
      expect(find.textContaining('Ali Raza'), findsOneWidget);
    });

    testWidgets('the form checks, then sends the claim', (tester) async {
      final adapter = _server();
      await tester.pumpWidget(_host(adapter));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NEW CLAIM'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('SUBMIT CLAIM'));
      await tester.pumpAndSettle();
      expect(find.text('Please choose the kind of expense.'), findsOneWidget);

      await tester.tap(find.text('Kind of expense'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Subscriptions').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('SUBMIT CLAIM'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter the amount.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '2500');
      await tester.tap(find.text('SUBMIT CLAIM'));
      await tester.pumpAndSettle();
      expect(
        find.text('Please write what the expense was for.'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).last, 'Annual licence');
      await tester.tap(find.text('SUBMIT CLAIM'));
      await tester.pumpAndSettle();

      final sent = adapter.sent['add-my-expense']!;
      expect(sent['expense_type'], '4');
      expect(sent['expense_amount'], '2500');
      expect(sent['expense_reason'], 'Annual licence');
    });

    testWidgets('editing fills the form and saves with the claim id', (
      tester,
    ) async {
      final adapter = _server();
      await tester.pumpWidget(_host(adapter));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('SAVE CHANGES'), findsOneWidget);
      expect(find.text('1500'), findsOneWidget); // the amount is filled in

      await tester.enterText(find.widgetWithText(TextField, '1500'), '1800');
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();

      final sent = adapter.sent['update-my-expense']!;
      expect(sent['expense_id'], '15');
      expect(sent['expense_amount'], '1800');
      expect(sent['expense_type'], '1');
    });
  });
}
