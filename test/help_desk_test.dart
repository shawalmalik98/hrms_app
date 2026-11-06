import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/network/api_client.dart';
import 'package:hrms_app/core/storage/session_store.dart';
import 'package:hrms_app/features/leave/domain/time_off_models.dart';
import 'package:hrms_app/features/services/application/services_providers.dart';
import 'package:hrms_app/features/services/data/help_desk_repository.dart';
import 'package:hrms_app/features/services/domain/help_desk_models.dart';
import 'package:hrms_app/features/services/presentation/help_desk_screen.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.bodies, {this.types = const {}, this.disposition = const {}});

  final Map<String, String> bodies;
  final Map<String, String> types;
  final Map<String, String> disposition;
  final sent = <String, Map<String, String>>{};
  final files = <String, Map<String, String>>{};

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

const _tickets = '''
{"status":true,"message":"View My Help Desk","data":{"title":"my-help-desk",
 "get_my_help_desks":[
  {"help_desk_id":41,"help_message":"Printer is not working","help_attachment":null,
   "created_time":"2026-11-04 15:20:11","ticket_status":1,
   "ticket_status_created_time":"2026-11-04 15:20:11"},
  {"help_desk_id":40,"help_message":"VPN down","help_attachment":"vpn.png",
   "created_time":"2026-11-03 09:00:00","ticket_status":4,
   "ticket_status_created_time":"2026-11-03 11:00:00"}],
 "departments":[{"department_id":4,"department_name":"IT"},
                {"department_id":5,"department_name":"HR"}]}}
''';

const _detail = '''
{"status":true,"message":"","data":{
 "help_desk":[{"employee_name":"Ali","created_time":"2026-11-04 15:20:11",
   "help_message":"Printer is not working","help_attachment":"photo.png"}],
 "help_desk_status":[
  {"employee_name":"Ali","ticket_status":1,"ticket_status_created_time":"2026-11-04 15:20:11"},
  {"employee_name":"Sara","ticket_status":2,"ticket_status_created_time":"2026-11-04 16:00:00"}],
 "help_desk_departments":[4],
 "help_desk_employees_selected":[]}}
''';

class _Fake implements HelpDeskRepository {
  _Fake(this.adapter);

  final _Adapter adapter;
  late final _real = ApiHelpDeskRepository(_client(adapter));

  @override
  Future<TicketsData> tickets() => _real.tickets();

  @override
  Future<List<TicketPerson>> peopleOf(List<String> ids) => _real.peopleOf(ids);

  @override
  Future<void> addTicket({
    required String message,
    required List<String> departmentIds,
    List<String> employeeIds = const [],
    Attachment? attachment,
  }) => _real.addTicket(
    message: message,
    departmentIds: departmentIds,
    employeeIds: employeeIds,
    attachment: attachment,
  );

  @override
  Future<TicketDetail> detail(String id) => _real.detail(id);

  @override
  Future<void> updateTicket({
    required String id,
    required String message,
    required List<String> departmentIds,
    List<String> employeeIds = const [],
    Attachment? attachment,
  }) => _real.updateTicket(
    id: id,
    message: message,
    departmentIds: departmentIds,
    employeeIds: employeeIds,
    attachment: attachment,
  );

  @override
  Future<({Uint8List bytes, String filename})> attachment(
    String id, {
    String? name,
  }) => _real.attachment(id, name: name);
}

_Adapter _server() => _Adapter(
  {
    'my-tickets': _tickets,
    'my-help-desk-detail/41': _detail,
    'get-employee-department-hd':
        '{"status":true,"message":"Employee Department","data":['
        '{"employee_id":7,"employee_code":"1000007","employee_name":"Sara"}]}',
    'add-help-desk':
        '{"status":true,"message":"Ticket Generated Successfully."}',
    'update-help-desk':
        '{"status":true,"message":"Ticket Updated Successfully."}',
    'my-help-desk-detail/40':
        '{"status":true,"message":"","data":{"help_desk":[{"employee_name":"Ali",'
        '"created_time":"2026-11-03 09:00:00","help_message":"VPN down",'
        '"help_attachment":"vpn.png"}],"help_desk_status":['
        '{"employee_name":"Ali","ticket_status":1,"ticket_status_created_time":"2026-11-03 09:00:00"},'
        '{"employee_name":"Omar","ticket_status":4,"ticket_status_created_time":"2026-11-03 11:00:00"}],'
        '"help_desk_departments":[5],"help_desk_employees_selected":[]}}',
    'my-help-desk-attachment/40': '%PDF-1.4 file',
    'my-help-desk-attachment/41':
        '{"status":false,"message":"Attachment not found."}',
  },
  types: {'my-help-desk-attachment/40': 'application/pdf'},
  disposition: {
    'my-help-desk-attachment/40': 'attachment; filename="vpn-report.pdf"',
  },
);

Widget _host(_Adapter a) => ProviderScope(
  overrides: [helpDeskRepositoryProvider.overrideWithValue(_Fake(a))],
  child: const MaterialApp(home: HelpDeskScreen()),
);

void main() {
  group('help desk data', () {
    test('tickets, statuses and departments are read', () async {
      final repo = ApiHelpDeskRepository(_client(_server()));
      final data = await repo.tickets();

      expect(data.tickets, hasLength(2));
      expect(data.tickets[0].id, '41');
      expect(data.tickets[0].status, TicketStatus.pending);
      expect(data.tickets[0].status.label, 'Ticket Pending');
      expect(data.tickets[1].status.label, 'Resolved From Department');
      expect(data.tickets[1].attachment, 'vpn.png');
      expect(data.tickets[0].createdAt, DateTime(2026, 11, 4, 15, 20, 11));
      expect(data.departments.map((d) => d.name), ['IT', 'HR']);
    });

    test('all five status numbers have their label', () {
      expect([1, 2, 3, 4, 5].map((n) => TicketStatus.fromApi(n).label), [
        'Ticket Pending',
        'Ticket Open',
        'Ticket Rejected',
        'Resolved From Department',
        'Resolved From Employee',
      ]);
    });

    test('detail has the history, oldest first, and the departments', () async {
      final d = await ApiHelpDeskRepository(_client(_server())).detail('41');
      expect(d.message, 'Printer is not working');
      expect(d.attachment, 'photo.png');
      expect(d.history.map((s) => s.status), [
        TicketStatus.pending,
        TicketStatus.open,
      ]);
      expect(d.history.last.by, 'Sara');
      expect(d.departmentIds, {'4'});
      expect(d.peopleCount, 0);
    });

    test('a wrong ticket id gives the server message', () async {
      final repo = ApiHelpDeskRepository(
        _client(
          _Adapter({
            'my-help-desk-detail/9': '{"status":false,"message":"Help desk ticket id is invalid.","data":""}',
          }),
        ),
      );
      expect(
        repo.detail('9'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Help desk ticket id is invalid.',
          ),
        ),
      );
    });

    test('a ticket is sent with its departments, people and file', () async {
      final adapter = _server();
      await ApiHelpDeskRepository(_client(adapter)).addTicket(
        message: 'Printer is not working',
        departmentIds: ['4', '5'],
        employeeIds: ['7'],
        attachment: Attachment(
          name: 'photo.png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      );
      expect(adapter.sent['add-help-desk'], {
        'message': 'Printer is not working',
        'department_id[0]': '4',
        'department_id[1]': '5',
        'employee_id[0]': '7',
      });
      expect(adapter.files['add-help-desk'], {'attachment': 'photo.png'});
    });

    test('people of the chosen departments are asked for', () async {
      final adapter = _server();
      final people = await ApiHelpDeskRepository(_client(adapter))
          .peopleOf(['4']);
      expect(adapter.sent['get-employee-department-hd'], {
        'department[0]': '4',
      });
      expect(people.single.name, 'Sara');
      expect(people.single.code, '1000007');
    });
  });

  group('help desk edit and download', () {
    test(
      'a ticket is changed with its id, departments, people and file',
      () async {
        final adapter = _server();
        await ApiHelpDeskRepository(_client(adapter)).updateTicket(
          id: '41',
          message: 'Printer still broken',
          departmentIds: ['4'],
          employeeIds: ['7', '8'],
          attachment: Attachment(
            name: 'new.png',
            bytes: Uint8List.fromList([1]),
          ),
        );
        expect(adapter.sent['update-help-desk'], {
          'hd_id': '41',
          'message': 'Printer still broken',
          'department_id[0]': '4',
          'employee_id[0]': '7',
          'employee_id[1]': '8',
        });
        expect(adapter.files['update-help-desk'], {'attachment': 'new.png'});
      },
    );

    test('no new file means the old one stays (nothing is uploaded)', () async {
      final adapter = _server();
      await ApiHelpDeskRepository(_client(adapter))
          .updateTicket(id: '41', message: 'x', departmentIds: ['4']);
      expect(adapter.files['update-help-desk'], isEmpty);
    });

    test('the server refuses a ticket that is no longer pending', () async {
      final repo = ApiHelpDeskRepository(
        _client(
          _Adapter({
            'update-help-desk': '{"status":false,"message":"You can not edit this ticket because it is no longer pending.","data":""}',
          }),
        ),
      );
      expect(
        repo.updateTicket(id: '40', message: 'x', departmentIds: ['4']),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'You can not edit this ticket because it is no longer pending.',
          ),
        ),
      );
    });

    test('the detail gives the ids to fill the edit form with', () async {
      final repo = ApiHelpDeskRepository(
        _client(
          _Adapter({
            'my-help-desk-detail/41':
                '{"status":true,"message":"","data":{"help_desk":[{"help_message":"m"}],'
                '"help_desk_status":[],"help_desk_departments":[{"department_id":4}],'
                '"help_desk_employees_selected":[{"employee_id":7},8]}}',
          }),
        ),
      );
      final d = await repo.detail('41');
      expect(d.departmentIds, {'4'});
      expect(d.employeeIds, {'7', '8'});
      expect(d.peopleCount, 2);
    });

    test(
      'a file comes back as a file, with the name the server gives',
      () async {
        final file = await ApiHelpDeskRepository(_client(_server()))
            .attachment('40');
        expect(file.filename, 'vpn-report.pdf');
        expect(String.fromCharCodes(file.bytes), startsWith('%PDF'));
      },
    );

    test(
      'without a name from the server the ticket file name is used',
      () async {
        final repo = ApiHelpDeskRepository(
          _client(
            _Adapter(
              {'my-help-desk-attachment/9': 'bytes'},
              types: {'my-help-desk-attachment/9': 'image/png'},
            ),
          ),
        );
        expect(
          (await repo.attachment('9', name: 'photo.png')).filename,
          'photo.png',
        );
      },
    );

    test('"Attachment not found." is shown instead of a file', () async {
      expect(
        ApiHelpDeskRepository(_client(_server())).attachment('41'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Attachment not found.',
          ),
        ),
      );
    });
  });

  group('help desk screen', () {
    testWidgets('lists tickets with their status', (tester) async {
      await tester.pumpWidget(_host(_server()));
      await tester.pumpAndSettle();

      expect(find.text('RAISE A TICKET'), findsOneWidget);
      expect(find.text('Ticket #41'), findsOneWidget);
      expect(find.text('Printer is not working'), findsOneWidget);
      expect(find.text('Ticket Pending'), findsOneWidget);
      expect(find.text('Resolved From Department'), findsOneWidget);
    });

    testWidgets('a ticket opens its detail with the status history', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_server()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ticket #41'));
      await tester.pumpAndSettle();

      expect(find.text('Status history'), findsOneWidget);
      expect(find.text('Ticket Open'), findsWidgets);
      expect(find.textContaining('Sara'), findsOneWidget);
      expect(find.text('Sent to: Managers of IT'), findsOneWidget);
    });

    testWidgets('the form needs a message and a department, then sends', (
      tester,
    ) async {
      final adapter = _server();
      await tester.pumpWidget(_host(adapter));
      await tester.pumpAndSettle();

      await tester.tap(find.text('RAISE A TICKET'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('SEND TICKET'));
      await tester.pumpAndSettle();
      expect(find.text('Please write your message.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Printer is not working');
      await tester.tap(find.text('SEND TICKET'));
      await tester.pumpAndSettle();
      expect(find.text('Please choose a department.'), findsOneWidget);

      await tester.tap(find.text('IT'));
      await tester.pumpAndSettle();
      // The people of the department can be chosen (optional).
      expect(find.text('Sara'), findsOneWidget);

      await tester.tap(find.text('SEND TICKET'));
      await tester.pumpAndSettle();
      expect(adapter.sent['add-help-desk'], {
        'message': 'Printer is not working',
        'department_id[0]': '4',
      });
    });

    testWidgets('only a pending ticket can be edited', (tester) async {
      await tester.pumpWidget(_host(_server()));
      await tester.pumpAndSettle();
      // #41 is pending, #40 is resolved: one edit button.
      expect(find.byTooltip('Edit'), findsOneWidget);
      // Only #40 has a file.
      expect(find.byTooltip('Download attachment'), findsOneWidget);
    });

    testWidgets('the detail of a pending ticket offers edit', (tester) async {
      final adapter = _server();
      adapter.bodies['my-help-desk-detail/41'] =
          '{"status":true,"message":"","data":{"help_desk":[{"employee_name":"Ali",'
          '"help_message":"Printer is not working","help_attachment":"photo.png"}],'
          '"help_desk_status":[{"employee_name":"Ali","ticket_status":1,'
          '"ticket_status_created_time":"2026-11-04 15:20:11"}],'
          '"help_desk_departments":[4],"help_desk_employees_selected":[]}}';
      await tester.pumpWidget(_host(adapter));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ticket #41'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT TICKET'), findsOneWidget);
      expect(find.text('Download attachment'), findsOneWidget); // photo.png
    });

    testWidgets('the detail of a resolved ticket has no edit', (tester) async {
      await tester.pumpWidget(_host(_server()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ticket #40'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT TICKET'), findsNothing);
      expect(find.text('Download attachment'), findsOneWidget);
    });

    testWidgets('editing fills the form in and saves with the ticket id', (
      tester,
    ) async {
      final adapter = _server();
      await tester.pumpWidget(_host(adapter));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();

      // The message of the ticket is already there.
      expect(find.text('Printer is not working'), findsWidgets);
      expect(find.text('SAVE CHANGES'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Printer still broken');
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();
      expect(adapter.sent['update-help-desk'], {
        'hd_id': '41',
        'message': 'Printer still broken',
        'department_id[0]': '4',
      });
    });
  });
}
