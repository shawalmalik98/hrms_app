import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/network/api_client.dart';
import 'package:hrms_app/core/storage/session_store.dart';
import 'package:hrms_app/features/attendance/data/attendance_repository.dart';
import 'package:hrms_app/features/attendance/domain/attendance_models.dart';
import 'package:hrms_app/features/leave/data/time_off_repository.dart';
import 'package:hrms_app/features/leave/domain/time_off_models.dart';
import 'package:hrms_app/features/leave/presentation/time_off_widgets.dart';
import 'package:hrms_app/features/services/application/services_providers.dart';
import 'package:hrms_app/features/services/data/services_repository.dart';
import 'package:hrms_app/features/services/domain/service_models.dart';
import 'package:hrms_app/features/services/presentation/advance_screen.dart';
import 'package:hrms_app/features/services/presentation/loan_screen.dart';
import 'package:hrms_app/features/services/presentation/payslip_screen.dart';
import 'package:hrms_app/features/services/presentation/services_tab.dart';

/// Answers each path with a canned body (and content type) and remembers what
/// was sent.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.bodies, {this.types = const {}});

  final Map<String, Object> bodies; // String or Uint8List
  final Map<String, String> types;
  final sent = <String, Map<String, String>>{};
  final queries = <String, Map<String, String>>{};
  final files = <String, Map<String, String>>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path.replaceFirst(RegExp(r'^/'), '');
    final data = options.data;
    if (data is FormData) {
      sent[path] = {for (final f in data.fields) f.key: f.value};
      files[path] = {for (final f in data.files) f.key: f.value.filename ?? ''};
    }
    queries[path] = options.uri.queryParameters;
    final body = bodies[path] ?? '{"status":false,"message":"unknown"}';
    final bytes = body is String ? utf8.encode(body) : body as Uint8List;
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        Headers.contentTypeHeader: [types[path] ?? Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(_Adapter adapter, {SessionStore? session}) => ApiClient(
  session: session ?? SessionStore(),
  onUnauthorized: () {},
  dio: Dio(BaseOptions(baseUrl: 'http://test/api/v1/'))
    ..httpClientAdapter = adapter,
);

const _advanceJson = '''
{"status":true,"message":"","data":{
 "my_requests":[
  {"advance_salary_request_id":87,"effective_payroll_period":"2026-12",
   "advance_salary_amount":12000,"request_message":"Medical bills",
   "request_approved_by_finance":1,"request_approved_date_finance":null,
   "request_aprrover_message":null,"request_created_at":"04-11-2026 15:02:58"},
  {"advance_salary_request_id":88,"effective_payroll_period":"2026-11",
   "advance_salary_amount":5000,"request_message":"x",
   "request_approved_by_finance":1,"request_approved_date_finance":null,
   "request_aprrover_message":null,"request_created_at":"03-11-2026 10:00:00"},
  {"advance_salary_request_id":89,"effective_payroll_period":"2026-10",
   "advance_salary_amount":7000,"request_message":"y",
   "request_approved_by_finance":2,"request_approved_date_finance":"Done",
   "request_aprrover_message":"Approved","request_created_at":"01-10-2026 10:00:00"}
 ],
 "employee_salary":[{"salary_amount":60000}],
 "responsed_request":[88]}}
''';

const _loansJson = '''
{"status":true,"message":"","data":{
 "all_loans":[{"loan_request_id":82,"loan_reason":"Bike Loan",
  "loan_reason_message":"New bike","loan_request_amount":50000,
  "loan_deduction_type":2,"loan_deduction_start":"2026-12",
  "loan_deduction_amount":10,"request_approved_by_finance":1,
  "request_approved_date_finance":null,"request_aprrover_message":null,
  "loan_applied_date":"2026-11-04 15:02:58"}],
 "loan_given_amount":[{"total":null}],
 "loan_return_amount":[{"total":null}],
 "loan_remaining_amount":0,
 "responsed_request":[]}}
''';

class _FakeServices implements ServicesRepository {
  @override
  Future<AdvanceData> advances() async => ApiServicesRepository(
    _client(_Adapter({'api/v1/my-salary-request': _advanceJson})),
  ).advances();

  @override
  Future<LoanData> loans() async =>
      ApiServicesRepository(_client(_Adapter({'api/v1/my-loan': _loansJson})))
          .loans();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget child) => ProviderScope(
  overrides: [servicesRepositoryProvider.overrideWithValue(_FakeServices())],
  child: MaterialApp(home: child),
);

void main() {
  group('advance salary', () {
    test('requests, salary and who can still edit are read', () async {
      final repo = ApiServicesRepository(
        _client(_Adapter({'api/v1/my-salary-request': _advanceJson})),
      );
      final data = await repo.advances();

      expect(data.salary, 60000);
      expect(data.requests, hasLength(3));
      expect(data.requests[0].canEdit, isTrue); // pending, not answered
      expect(data.requests[1].canEdit, isFalse); // pending but answered
      expect(data.requests[2].canEdit, isFalse); // approved
      expect(data.requests[0].period, '2026-12');
      expect(monthLabel(data.requests[0].period), 'December 2026');
    });

    test('submit and edit send what the API expects', () async {
      final adapter = _Adapter({
        'api/v1/submit_salary_request': '{"status":true,"message":"ok"}',
        'api/v1/update-adv-request': '{"status":true,"message":"ok"}',
      });
      final repo = ApiServicesRepository(_client(adapter));

      await repo.submitAdvance(amount: 12000, payback: '2026-12', message: 'm');
      expect(adapter.sent['api/v1/submit_salary_request'], {
        'advance_salary': '12000',
        'payback_date': '2026-12',
        'message': 'm',
      });

      await repo.updateAdvance(
        id: '87',
        amount: 9000,
        payback: '2026-12',
        message: 'm2',
      );
      expect(adapter.sent['api/v1/update-adv-request'], {
        'request_id': '87',
        'advance_salary': '9000',
        'payback_date': '2026-12',
        'message': 'm2',
      });
    });
  });

  group('loan', () {
    test('null totals are 0 and the deduction type is read', () async {
      final repo = ApiServicesRepository(
        _client(_Adapter({'api/v1/my-loan': _loansJson})),
      );
      final data = await repo.loans();

      expect(data.given, 0);
      expect(data.returned, 0);
      expect(data.remaining, 0);
      expect(data.loans.single.percentDeduction, isTrue);
      expect(data.loans.single.deductionLabel, '10% of salary');
      expect(data.loans.single.canEdit, isTrue);
    });

    test(
      'detail has installments; pending loan gives the server message',
      () async {
        final adapter = _Adapter({
          'api/v1/my-loan-request-detail/47':
              '{"status":true,"message":"","data":[{"loan_id":47,'
              '"loan_given_amount":"50000","loan_remaining_amount":"45000",'
              '"loan_submitted_amount":"5000"}],"installments":['
              '{"loan_installment_amount":5000,"loan_installment_date":"2026-11-04"}]}',
          'api/v1/my-loan-request-detail/82':
              '{"status":false,"message":"Loan request is Pending.","data":""}',
        });
        final repo = ApiServicesRepository(_client(adapter));

        final detail = await repo.loanDetail('47');
        expect(detail.remaining, 45000);
        expect(detail.returned, 5000);
        expect(detail.installments.single.amount, 5000);

        expect(
          repo.loanDetail('82'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              'Loan request is Pending.',
            ),
          ),
        );
      },
    );

    test('fixed and percent requests send the right fields', () async {
      final adapter = _Adapter({
        'api/v1/loan-request': '{"status":true,"message":"ok"}',
        'api/v1/update-loan-request': '{"status":true,"message":"ok"}',
      });
      final repo = ApiServicesRepository(_client(adapter));

      await repo.submitLoan(
        const LoanForm(
          amount: 50000,
          reason: 'Bike Loan',
          message: 'm',
          percent: false,
          deduction: 5000,
          start: '2026-12',
        ),
      );
      expect(adapter.sent['api/v1/loan-request'], {
        'loan_amount': '50000',
        'loan_reason': 'Bike Loan',
        'loan_message': 'm',
        'deduction_type': '1',
        'deduction_amount': '5000',
        'deduction_start': '2026-12',
      });

      await repo.updateLoan(
        '82',
        const LoanForm(
          amount: 50000,
          reason: 'Other',
          message: 'm',
          percent: true,
          deduction: 10,
          start: '2026-12',
        ),
      );
      expect(adapter.sent['api/v1/update-loan-request'], {
        'request_id': '82',
        'loan_amount': '50000',
        'loan_reason': 'Other',
        'loan_message': 'm',
        'deduction_type': '2',
        'deduction_percentage': '10',
        'deduction_start': '2026-12',
      });
    });
  });

  group('payslip', () {
    test('payslips are read', () async {
      final repo = ApiServicesRepository(
        _client(
          _Adapter({
            'api/v1/my-payroll':
                '{"status":true,"message":"","data":{"fetch_employee_payroll":['
                '{"pc_id":1602,"pc_month":10,"pc_year":2026,'
                '"pc_employee_gross_salary":60000,"pc_employee_extra_salary":2500,'
                '"pc_employee_deduction":6870,"pc_employee_net_salary":55630}]}}',
          }),
        ),
      );
      final p = (await repo.payslips()).single;
      expect(p.title, 'October 2026');
      expect(p.net, 55630);
      expect(p.id, '1602');
    });

    test('a PDF is returned as a file, the token goes in the URL', () async {
      final adapter = _Adapter(
        {'payslip-pdf': Uint8List.fromList(utf8.encode('%PDF-1.4 data'))},
        types: {'payslip-pdf': 'application/pdf'},
      );
      final repo = ApiServicesRepository(_client(adapter));

      final file = await repo.payslipPdf('1602');
      expect(utf8.decode(file.bytes), startsWith('%PDF'));
      expect(file.filename, 'Payslip-1602.pdf');
      expect(adapter.queries['payslip-pdf']!['pc_id'], '1602');
      expect(adapter.queries['payslip-pdf']!.containsKey('token'), isTrue);
      expect(
        adapter.queries['payslip-pdf']!.containsKey('device_token'),
        isTrue,
      );
    });

    test(
      'a PDF is recognised by its first bytes, whatever the type says',
      () async {
        final repo = ApiServicesRepository(
          _client(
            _Adapter(
              {'payslip-pdf': '%PDF-1.4 content'},
              types: {'payslip-pdf': 'application/octet-stream'},
            ),
          ),
        );
        final file = await repo.payslipPdf('7');
        expect(String.fromCharCodes(file.bytes), startsWith('%PDF'));
        expect(file.filename, 'Payslip-7.pdf');
      },
    );

    test('something that is not a PDF is not saved as one', () async {
      final repo = ApiServicesRepository(
        _client(
          _Adapter(
            {'payslip-pdf': '<html>login</html>'},
            types: {'payslip-pdf': 'text/html'},
          ),
        ),
      );
      expect(
        repo.payslipPdf('7'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('did not send a PDF'),
          ),
        ),
      );
    });

    test('when the server answers with JSON its msg is shown', () async {
      final repo = ApiServicesRepository(
        _client(
          _Adapter({
            'payslip-pdf': '{"status":"FALSE","msg":"Payslip no. is invalid"}',
          }),
        ),
      );
      expect(
        repo.payslipPdf('1'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Payslip no. is invalid',
          ),
        ),
      );
    });
  });

  group('edit requests', () {
    test('leave rows know if they can still be edited', () async {
      final repo = ApiTimeOffRepository(
        _client(
          _Adapter({
            'api/v1/my-leaves':
                '{"status":true,"message":"","data":{"my_leaves":['
                '{"leave_applied_id":90,"leave_applied_for_date":"2026-11-07",'
                '"leave_approved_by_hr":1,"leave_name":"Casual Leave","leave_manage_id":1},'
                '{"leave_applied_id":91,"leave_applied_for_date":"2026-11-08",'
                '"leave_approved_by_hr":1,"leave_name":"Casual Leave","leave_manage_id":1},'
                '{"leave_applied_id":92,"leave_applied_for_date":"2026-11-09",'
                '"leave_approved_by_hr":2,"leave_name":"Casual Leave","leave_manage_id":1}],'
                '"responsed_request":[91]}}',
          }),
        ),
      );
      final leaves = await repo.myLeaves();
      expect(leaves.map((l) => l.canEdit), [true, false, false]);
      expect(leaves.first.typeId, '1');
    });

    test('leave and attendance edits send what the API expects', () async {
      final adapter = _Adapter({
        'api/v1/update-leave-request': '{"status":true,"message":"ok"}',
        'api/v1/update-attendance-request': '{"status":true,"message":"ok"}',
      });
      final client = _client(adapter);

      await ApiTimeOffRepository(client).updateLeave(
        id: '90',
        typeId: '2',
        reason: 'Sick',
        date: DateTime(2026, 11, 8),
      );
      expect(adapter.sent['api/v1/update-leave-request'], {
        'leave_id': '90',
        'leave_date': '2026-11-08',
        'edit_leave_type': '2',
        'edit_leave_reason': 'Sick',
      });

      await ApiAttendanceRepository(client).updateRequest(
        '70',
        NewAttendanceRequest(
          date: DateTime(2026, 11, 3),
          type: RequestType.onTimeCheckOut,
          message: 'Forgot',
          checkOut: '18:00:00',
        ),
      );
      expect(adapter.sent['api/v1/update-attendance-request'], {
        'attendance_id': '70',
        'edit_attendance_date': '2026-11-03',
        'edit_attendance_type': 'On Time Check Out',
        'edit_attendance_message': 'Forgot',
        'check_out_time': '18:00:00',
      });
    });

    test('attendance requests are read from the new shape', () async {
      final repo = ApiAttendanceRepository(
        _client(
          _Adapter({
            'api/v1/my-attendance-request':
                '{"status":true,"message":"","data":{"my_requests":['
                '{"attendance_request_id":70,"request_attendance_date":"2026-11-03",'
                '"request_attendance_status":"On Time Check Out",'
                '"request_attendance_message":"Forgot check out",'
                '"request_approved_by_hr":1,"attendance_checkin_time":"09:10:00",'
                '"attendance_checkout_time":"18:00:00"},'
                '{"attendance_request_id":71,"request_attendance_date":"2026-11-02",'
                '"request_attendance_status":"Present","request_attendance_message":"x",'
                '"request_approved_by_hr":1},'
                '{"attendance_request_id":72,"request_attendance_date":"2026-11-01",'
                '"request_attendance_status":"Present","request_attendance_message":"x",'
                '"request_approved_by_hr":3}],'
                '"responsed_request":[],"get_manager_response":[71]}}',
          }),
        ),
      );
      final list = await repo.requests();

      expect(list, hasLength(3));
      expect(list[0].typeLabel, 'On Time Check Out');
      expect(list[0].type, RequestType.onTimeCheckOut);
      expect(list[0].message, 'Forgot check out');
      expect(list[0].appliedFor, DateTime(2026, 11, 3));
      expect(list.map((r) => r.canEdit), [true, false, false]);
    });
  });

  group('leave attachment', () {
    final file = Attachment(
      name: 'certificate.pdf',
      bytes: Uint8List.fromList(utf8.encode('%PDF')),
    );

    test('is sent as a file with apply and with edit', () async {
      final adapter = _Adapter({
        'api/v1/applyfor_leave': '{"status":true,"message":"ok"}',
        'api/v1/update-leave-request': '{"status":true,"message":"ok"}',
      });
      final repo = ApiTimeOffRepository(_client(adapter));

      await repo.applyLeave(
        typeId: '1',
        reason: 'Sick',
        from: DateTime(2026, 11, 7),
        attachment: file,
      );
      expect(adapter.files['api/v1/applyfor_leave'], {
        'leave_applied_attachment': 'certificate.pdf',
      });

      await repo.updateLeave(
        id: '90',
        typeId: '1',
        reason: 'Sick',
        date: DateTime(2026, 11, 7),
        attachment: file,
      );
      expect(adapter.files['api/v1/update-leave-request'], {
        'leave_applied_attachment': 'certificate.pdf',
      });
    });

    test('no file means no upload', () async {
      final adapter = _Adapter({
        'api/v1/applyfor_leave': '{"status":true,"message":"ok"}',
      });
      await ApiTimeOffRepository(_client(adapter))
          .applyLeave(typeId: '1', reason: 'x', from: DateTime(2026, 11, 7));
      expect(adapter.files['api/v1/applyfor_leave'], isEmpty);
    });

    testWidgets(
      'the field picks, shows the name, removes, and reports errors',
      (tester) async {
        Attachment? value;
        var fail = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => AttachmentField(
                  value: value,
                  onChanged: (f) => setState(() => value = f),
                  pick: () async {
                    if (fail) {
                      throw const FormatException('The file is too big.');
                    }
                    return file;
                  },
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Attach a file (optional)'));
        await tester.pumpAndSettle();
        expect(find.text('certificate.pdf'), findsOneWidget);

        await tester.tap(find.byTooltip('Remove file'));
        await tester.pumpAndSettle();
        expect(find.text('Attach a file (optional)'), findsOneWidget);

        fail = true;
        await tester.tap(find.text('Attach a file (optional)'));
        await tester.pumpAndSettle();
        expect(find.text('The file is too big.'), findsOneWidget);
        expect(value, isNull);
      },
    );
  });

  group('screens', () {
    testWidgets('a payslip has both View and Download', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            payslipsProvider.overrideWith(
              (ref) async => const [
                Payslip(
                  id: '1',
                  month: 10,
                  year: 2026,
                  gross: 60000,
                  extra: 0,
                  deduction: 6000,
                  net: 54000,
                ),
              ],
            ),
          ],
          child: const MaterialApp(home: PayslipScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('View'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Rs 54,000'), findsOneWidget);
    });

    testWidgets('More lists everything but the three tabs, in order', (
      tester,
    ) async {
      // A tall screen, so every tile is on it at once.
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(const Scaffold(body: ServicesTab())));
      await tester.pumpAndSettle();
      // My Profile first, Leave right after it, Payslips last.
      final order = [
        'My Profile',
        'Leave',
        'Work From Home',
        'Advance Salary',
        'Reimbursement',
        'Loan',
        'Resignation',
        'Help Desk',
        'Payslips',
      ];
      var lastY = -1.0;
      for (final title in order) {
        final y = tester.getTopLeft(find.text(title)).dy;
        expect(find.text(title), findsOneWidget, reason: title);
        expect(
          y,
          greaterThan(lastY),
          reason: '$title comes after the one before',
        );
        lastY = y;
      }
    });

    testWidgets('only an editable advance has an Edit button', (tester) async {
      await tester.pumpWidget(_host(const AdvanceScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Rs 12,000'), findsOneWidget);
      expect(find.text('Rs 5,000'), findsOneWidget);
      expect(find.text('Rs 7,000'), findsOneWidget);
      // 87 pending, 88 answered by the manager, 89 approved: one edit button.
      expect(find.byTooltip('Edit'), findsOneWidget);

      await tester.tap(find.text('REQUEST ADVANCE'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Up to Rs 60,000'), findsOneWidget);
    });

    testWidgets('loan screen shows 0 totals and the request', (tester) async {
      await tester.pumpWidget(_host(const LoanScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Rs 0'), findsWidgets);
      expect(find.text('Bike Loan'), findsOneWidget);
      expect(find.textContaining('10% of salary'), findsOneWidget);
      expect(find.byTooltip('Edit'), findsOneWidget);
    });
  });
}
