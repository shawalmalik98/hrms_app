import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/time/trusted_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};
  var elapsed = 1000;
  var boot = 5;

  setUp(() {
    store.clear();
    elapsed = 1000;
    boot = 5;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('hrms/clock'), (
          call,
        ) async {
          return {'elapsed': elapsed, 'boot': boot};
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            switch (call.method) {
              case 'write':
                store[args['key'] as String] = args['value'] as String;
                return null;
              case 'read':
                return store[args['key'] as String];
              case 'delete':
                store.remove(args['key']);
                return null;
            }
            return null;
          },
        );
  });

  final server = DateTime.utc(2026, 11, 2, 9, 0, 0);

  test('time = server time + uptime since the last server contact', () async {
    final clock = TrustedClock();
    await clock.anchor(server);

    elapsed += const Duration(minutes: 90).inMilliseconds;
    final now = await clock.now();

    expect(now, isNotNull);
    expect(now!.toUtc(), server.add(const Duration(minutes: 90)));
  });

  test('refused after a restart of the phone', () async {
    final clock = TrustedClock();
    await clock.anchor(server);

    boot = 6;
    expect(await clock.now(), isNull);
  });

  test('refused when the last server contact is too old', () async {
    final clock = TrustedClock();
    await clock.anchor(server);

    elapsed += const Duration(hours: 25).inMilliseconds;
    expect(await clock.now(), isNull);
  });

  test('refused when the server was never reached', () async {
    expect(await TrustedClock().now(), isNull);
  });
}
