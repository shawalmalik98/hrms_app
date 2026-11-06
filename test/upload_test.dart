import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/files/image_shrink.dart';
import 'package:hrms_app/core/network/api_client.dart';
import 'package:hrms_app/core/storage/session_store.dart';
import 'package:image/image.dart' as img;

/// Remembers the time limits each request was sent with.
class _Adapter implements HttpClientAdapter {
  _Adapter({this.fail});

  final DioExceptionType? fail;
  Duration? lastSendTimeout;
  Duration? lastReceiveTimeout;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastSendTimeout = options.sendTimeout;
    lastReceiveTimeout = options.receiveTimeout;
    if (fail != null) {
      throw DioException(requestOptions: options, type: fail!);
    }
    return ResponseBody.fromString(
      '{"status":true,"message":"ok","data":""}',
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
  dio: Dio(
    BaseOptions(
      baseUrl: 'http://test/api/v1/',
      // What the real app uses for an ordinary request.
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
    ),
  )..httpClientAdapter = a,
);

MultipartFile _file() =>
    MultipartFile.fromBytes(Uint8List.fromList([1, 2, 3]), filename: 'a.png');

/// A picture of random noise: it does not compress, so it stays big.
Uint8List _noisyPicture(int width, int height, {bool png = false}) {
  final r = Random(1);
  final image = img.Image(width: width, height: height);
  for (final p in image) {
    p
      ..r = r.nextInt(256)
      ..g = r.nextInt(256)
      ..b = r.nextInt(256);
  }
  return Uint8List.fromList(png ? img.encodePng(image) : img.encodeJpg(image));
}

void main() {
  group('uploads get time to finish', () {
    test('a request with a file is sent with the long time limit', () async {
      final a = _Adapter();
      await _client(a)
          .post('add-help-desk', {'message': 'x'}, {'attachment': _file()});
      expect(a.lastSendTimeout, uploadTimeout);
      expect(a.lastReceiveTimeout, uploadTimeout);
      expect(uploadTimeout, const Duration(seconds: 120));
    });

    test('an ordinary request keeps the short limit', () async {
      final a = _Adapter();
      await _client(a).post('login-process', {'employee_code': '1'});
      expect(a.lastSendTimeout, const Duration(seconds: 15));
      expect(a.lastReceiveTimeout, const Duration(seconds: 20));
    });

    test('an upload that runs out of time says so, not "contact IT"', () async {
      for (final type in [
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        await expectLater(
          _client(_Adapter(fail: type))
              .post('add-help-desk', {}, {'attachment': _file()}),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              uploadSlowMessage,
            ),
          ),
        );
      }
    });

    test(
      'a server that cannot be reached still says so for an upload',
      () async {
        await expectLater(
          _client(_Adapter(fail: DioExceptionType.connectionError))
              .post('add-help-desk', {}, {'attachment': _file()}),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              serverDownMessage,
            ),
          ),
        );
      },
    );
  });

  group('a big picture is made smaller before it is sent', () {
    test('a camera sized jpg shrinks to at most 1600 px', () async {
      final big = _noisyPicture(2600, 1900);
      expect(big.length, greaterThan(800 * 1024));

      final out = await shrinkIfImage(big, 'bill.jpg');
      expect(out.bytes.length, lessThan(big.length));
      expect(out.name, 'bill.jpg');
      final decoded = img.decodeJpg(out.bytes)!;
      expect(decoded.width, 1600);
      expect(decoded.height, lessThanOrEqualTo(1600));
    });

    test('a big png becomes a jpg and is renamed', () async {
      final big = _noisyPicture(2000, 1500, png: true);
      final out = await shrinkIfImage(big, 'scan.PNG');
      expect(out.name, 'scan.jpg');
      expect(out.bytes.length, lessThan(big.length));
      expect(img.decodeJpg(out.bytes), isNotNull);
    });

    test('a small picture is left exactly as it is', () async {
      final small = _noisyPicture(100, 100);
      expect(small.length, lessThan(800 * 1024));
      final out = await shrinkIfImage(small, 'a.jpg');
      expect(identical(out.bytes, small), isTrue);
      expect(out.name, 'a.jpg');
    });

    test('a PDF is never touched', () async {
      final pdf = Uint8List.fromList(List.filled(2 * 1024 * 1024, 37));
      final out = await shrinkIfImage(pdf, 'certificate.pdf');
      expect(identical(out.bytes, pdf), isTrue);
      expect(out.name, 'certificate.pdf');
    });

    test('something that is not really a picture is sent as it is', () async {
      final junk = Uint8List.fromList(List.filled(1024 * 1024, 7));
      final out = await shrinkIfImage(junk, 'fake.png');
      expect(identical(out.bytes, junk), isTrue);
      expect(out.name, 'fake.png');
    });
  });
}
