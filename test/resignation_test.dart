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
import 'package:hrms_app/features/services/data/services_repository.dart';
import 'package:hrms_app/features/services/domain/service_models.dart';
import 'package:hrms_app/features/services/presentation/resignation_screen.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.bodies);

  final Map<String, String> bodies;
  final sent = <String, Map<String, String>>{};

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
    }
    return ResponseBody.fromBytes(
      utf8.encode(bodies[path] ?? '{"status":false,"message":"unknown"}'),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
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

String _list(List<String> rows, {String responded = '[]'}) =>
    '{"status":true,"message":"My Resignation","data":{"title":"resignation",'
    '"resignations":[${rows.join(',')}],"responsed_request":$responded}}';

String _row(
  int id,
  int status, {
  String message = 'null',
  String date = 'null',
}) =>
    '{"resignation_id":$id,"employee_name":"Ali",'
    '"resignation_description":"Personal reasons",'
    '"resignation_from_date":"2026-11-10","resignation_to_date":"2026-12-10",'
    '"resignation_status":$status,"request_aprroved_message":$message,'
    '"request_approved_date_hr":$date}';

class _Fake implements ServicesRepository {
  _Fake(this.body);

  final String body;

  @override
  Future<List<Resignation>> resignations() =>
      ApiServicesRepository(_client(_Adapter({'employee-resignation': body})))
          .resignations();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(String body) => ProviderScope(
  overrides: [servicesRepositoryProvider.overrideWithValue(_Fake(body))],
  child: const MaterialApp(home: ResignationScreen()),
);

void main() {
  group('resignation data', () {
    test('rows, dates and the edit rule are read', () async {
      final repo = ApiServicesRepository(
        _client(
          _Adapter({
            'employee-resignation': _list([
              _row(12, 1),
              _row(11, 1),
              _row(
                10,
                2,
                message: '"Accepted"',
                date: '"Approved By : HR, at : 2026-11-05"',
              ),
              _row(9, 3),
            ], responded: '[11]'),
          }),
        ),
      );
      final list = await repo.resignations();

      expect(list, hasLength(4));
      expect(list[0].from, DateTime(2026, 11, 10));
      expect(list[0].to, DateTime(2026, 12, 10));
      expect(list[0].reason, 'Personal reasons');
      expect(list.map((r) => r.canEdit), [true, false, false, false]);
      expect(list.map((r) => r.blocksNew), [true, true, true, false]);
      expect(list[2].approverMessage, 'Accepted');
      expect(list[2].decision, 'Approved By : HR, at : 2026-11-05');
      expect(list[2].status, TimeOffStatus.approved);
    });

    test('place and edit send what the API expects', () async {
      final adapter = _Adapter({
        'add-employee-resignation': '{"status":true,"message":"ok"}',
        'update-employee-resignation': '{"status":true,"message":"ok"}',
      });
      final repo = ApiServicesRepository(_client(adapter));

      await repo.placeResignation(
        reason: 'Personal reasons',
        from: DateTime(2026, 11, 10),
        to: DateTime(2026, 12, 10),
      );
      expect(adapter.sent['add-employee-resignation'], {
        'reason': 'Personal reasons',
        'from_date': '2026-11-10',
        'to_date': '2026-12-10',
      });

      await repo.updateResignation(
        id: '12',
        reason: 'Moving abroad',
        from: DateTime(2026, 11, 15),
        to: DateTime(2026, 12, 15),
      );
      expect(adapter.sent['update-employee-resignation'], {
        'resignation_id': '12',
        'reason': 'Moving abroad',
        'from_date': '2026-11-15',
        'to_date': '2026-12-15',
      });
    });

    test('the server message is shown when placing is refused', () async {
      final repo = ApiServicesRepository(
        _client(
          _Adapter({
            'add-employee-resignation': '{"status":false,"message":"Resignation Already Placed.","data":""}',
          }),
        ),
      );
      expect(
        repo.placeResignation(
          reason: 'x',
          from: DateTime(2026, 11, 10),
          to: DateTime(2026, 12, 10),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Resignation Already Placed.',
          ),
        ),
      );
    });

    test('no resignation yet is an empty list', () async {
      final repo = ApiServicesRepository(
        _client(_Adapter({'employee-resignation': _list([])})),
      );
      expect(await repo.resignations(), isEmpty);
    });
  });

  group('resignation screen', () {
    testWidgets('nothing placed: the apply button shows', (tester) async {
      await tester.pumpWidget(_host(_list([])));
      await tester.pumpAndSettle();
      expect(find.text('PLACE RESIGNATION'), findsOneWidget);
      expect(find.text('You have not placed a resignation.'), findsOneWidget);
    });

    testWidgets('a pending one: edit shows, apply is hidden', (tester) async {
      await tester.pumpWidget(_host(_list([_row(12, 1)])));
      await tester.pumpAndSettle();
      expect(find.text('PLACE RESIGNATION'), findsNothing);
      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.textContaining('You can edit it until'), findsOneWidget);
      expect(find.text('Personal reasons'), findsOneWidget);
    });

    testWidgets('an answered one: no edit and no new one', (tester) async {
      await tester.pumpWidget(_host(_list([_row(12, 1)], responded: '[12]')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Edit'), findsNothing);
      expect(find.text('PLACE RESIGNATION'), findsNothing);
    });

    testWidgets('approved: no edit and no new one', (tester) async {
      await tester.pumpWidget(_host(_list([_row(12, 2)])));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Edit'), findsNothing);
      expect(find.text('PLACE RESIGNATION'), findsNothing);
      expect(find.text('Your resignation has been approved.'), findsOneWidget);
    });

    testWidgets('only a disapproved one: a new one can be placed', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_list([_row(12, 3)])));
      await tester.pumpAndSettle();
      expect(find.text('PLACE RESIGNATION'), findsOneWidget);
      expect(find.byTooltip('Edit'), findsNothing);
    });

    testWidgets('the form asks for a reason and then to confirm', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_list([])));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PLACE RESIGNATION'));
      await tester.pumpAndSettle();

      // Submit with no reason.
      await tester.tap(find.text('PLACE RESIGNATION').last);
      await tester.pumpAndSettle();
      expect(find.text('Please enter the reason.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Personal reasons');
      await tester.tap(find.text('PLACE RESIGNATION').last);
      await tester.pumpAndSettle();
      expect(find.text('Place your resignation?'), findsOneWidget);
    });
  });
}
