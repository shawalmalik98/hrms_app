import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/network/api_client.dart';
import 'package:hrms_app/core/storage/session_store.dart';
import 'package:hrms_app/features/attendance/data/attendance_repository.dart';
import 'package:hrms_app/features/leave/data/time_off_repository.dart';

/// Answers each path with a canned body and remembers what was sent.
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
    final data = options.data;
    if (data is FormData) {
      sent[options.path] = {for (final f in data.fields) f.key: f.value};
    }
    return ResponseBody.fromString(
      bodies[options.path] ?? '{"status":false,"message":"unknown"}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(_Adapter adapter) => ApiClient(
  session: SessionStore(),
  onUnauthorized: () {},
  dio: Dio(BaseOptions(baseUrl: 'http://test/'))..httpClientAdapter = adapter,
);

void main() {
  serverDownTests();
  group('lists with nothing in them are empty, not stuck or broken', () {
    Future<void> checkEmpty(String path, String body, Function load) async {
      final adapter = _Adapter({path: body});
      final repo = ApiAttendanceRepository(_client(adapter));
      final leave = ApiTimeOffRepository(_client(adapter));
      final result = await switch (path) {
        'my-attendance-request' => loadList(repo.requests),
        'my-leaves' => loadList(leave.myLeaves),
        _ => loadList(leave.myWfh),
      };
      expect(result, isEmpty, reason: '$path <- $body');
    }

    final shapes = {
      'my-attendance-request': [
        '{"status":true,"message":"","data":[]}',
        '{"status":true,"message":"","data":""}',
        '{"status":true,"message":"","data":null}',
        '{"status":false,"message":"No record found","data":""}',
        '{"status":false,"message":"No requests found","data":[]}',
      ],
      'my-leaves': [
        '{"status":true,"message":"My Leave Request ","data":{"my_leaves":[],"responsed_request":[]}}',
        '{"status":true,"message":"","data":[]}',
        '{"status":true,"message":"","data":""}',
        '{"status":false,"message":"No leave found","data":""}',
      ],
      'my-wfh-requests': [
        '{"status":true,"message":"","data":{"my_requests":[],"responsed_request":[]}}',
        '{"status":true,"message":"","data":[]}',
        '{"status":false,"message":"No Remote Work Request found","data":""}',
      ],
    };

    for (final entry in shapes.entries) {
      for (final body in entry.value) {
        test('${entry.key}: $body', () => checkEmpty(entry.key, body, () {}));
      }
    }
  });

  test('a real error is still an error', () async {
    final adapter = _Adapter({
      'my-leaves': '{"status":false,"message":"Invalid apk version","data":""}',
    });
    final repo = ApiTimeOffRepository(_client(adapter));
    expect(
      loadList(repo.myLeaves),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Invalid apk version',
        ),
      ),
    );
  });

  testWidgets('a list that never answers ends with a message', (tester) async {
    Object? error;
    unawaited(
      loadList<int>(() => Completer<List<int>>().future)
          .then<void>((_) {}, onError: (Object e) => error = e),
    );
    await tester.pump(const Duration(seconds: 26));
    expect(error, isA<ApiException>());
    expect((error as ApiException).message, contains('contact IT'));
  });

  test('leave requests are sent as the API expects', () async {
    final adapter = _Adapter({
      'applyfor_leave': '{"status":true,"message":"ok","data":""}',
      'submit_wfh_request': '{"status":true,"message":"ok","data":""}',
    });
    final repo = ApiTimeOffRepository(_client(adapter));

    await repo.applyLeave(
      typeId: '2',
      reason: 'Sick',
      from: DateTime(2026, 11, 7),
    );
    expect(adapter.sent['applyfor_leave'], {
      'days_assign': 'single',
      'leave_date': '2026-11-07',
      'leave_type': '2',
      'leave_reason': 'Sick',
    });

    await repo.applyLeave(
      typeId: '1',
      reason: 'Trip',
      from: DateTime(2026, 11, 9),
      to: DateTime(2026, 11, 11),
    );
    expect(adapter.sent['applyfor_leave'], {
      'days_assign': 'multiple',
      'from_date': '2026-11-09',
      'to_date': '2026-11-11',
      'leave_type': '1',
      'leave_reason': 'Trip',
    });

    // Same day twice is still one day.
    await repo.submitWfh(
      reason: 'Internet work',
      from: DateTime(2026, 11, 6),
      to: DateTime(2026, 11, 6),
    );
    expect(adapter.sent['submit_wfh_request'], {
      'days_assign': 'single',
      'request_date': '2026-11-06',
      'home_work_reason': 'Internet work',
    });

    await repo.submitWfh(
      reason: 'Away',
      from: DateTime(2026, 11, 6),
      to: DateTime(2026, 11, 8),
    );
    expect(adapter.sent['submit_wfh_request'], {
      'days_assign': 'multiple',
      'from_date': '2026-11-06',
      'to_date': '2026-11-08',
      'home_work_reason': 'Away',
    });
  });

  test(
    'approved work from home days are read, also when status is false',
    () async {
      final ok = ApiAttendanceRepository(
        _client(
          _Adapter({
            'wfh-today': '{"status":true,"message":"","data":{"approved_dates":["2026-11-04","2026-11-05"]}}',
          }),
        ),
      );
      expect(await ok.wfhApprovedDates(), ['2026-11-04', '2026-11-05']);

      final none = ApiAttendanceRepository(
        _client(
          _Adapter({
            'wfh-today':
                '{"status":false,"message":"","data":{"approved_dates":[]}}',
          }),
        ),
      );
      expect(await none.wfhApprovedDates(), isEmpty);
    },
  );
}

/// A server that is switched off: the connection is refused at once.
class _DownAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'Connection refused',
    );
  }

  @override
  void close({bool force = false}) {}
}

void serverDownTests() {
  group('server down', () {
    ApiClient down() => ApiClient(
      session: SessionStore(),
      onUnauthorized: () {},
      dio: Dio(BaseOptions(baseUrl: 'http://test/'))
        ..httpClientAdapter = _DownAdapter(),
    );

    test('the employee is told at once to contact IT', () async {
      await expectLater(
        down().get('my-leaves'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.network, 'network', isTrue)
              .having((e) => e.message, 'message', serverDownMessage),
        ),
      );
      expect(
        serverDownMessage,
        'Cannot connect to the server. Kindly contact IT.',
      );
    });

    test('posts (login, requests) say the same', () async {
      await expectLater(
        down().post('login-process', {'employee_code': '1'}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            serverDownMessage,
          ),
        ),
      );
    });

    test('a list gives the message, not an empty list or a spinner', () async {
      final repo = ApiAttendanceRepository(down());
      await expectLater(
        loadList(repo.requests),
        throwsA(
          isA<ApiException>()
              .having((e) => e.network, 'network', isTrue)
              .having((e) => e.message, 'message', serverDownMessage),
        ),
      );
    });

    test('a hanging server ends with the same message after 15 s', () {
      expect(listTimeout, const Duration(seconds: 15));
    });
  });
}
