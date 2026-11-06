import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/session_store.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.data, this.network = false});
  final String message;

  /// The envelope `data`, e.g. `{device_status: pending}` on login refusals.
  final dynamic data;

  /// True when the server could not be reached at all (no response).
  final bool network;

  @override
  String toString() => message;
}

typedef Json = Map<String, dynamic>;

/// How long a list may take to load before the screen shows a retry message
/// instead of spinning.
const listTimeout = Duration(seconds: 15);

/// Shown when the server cannot be reached while the phone itself is online:
/// it is down, or not answering. Nothing the employee can fix.
const serverDownMessage = 'Cannot connect to the server. Kindly contact IT.';

/// Shown when the phone has no connection at all.
const noInternetMessage =
    'No internet connection. Please check your connection and try again.';

/// Shown when a file upload runs out of time.
const uploadSlowMessage =
    'The upload took too long. Try a smaller file or a better connection.';

/// How long an upload may take. Most requests are tiny; a file is not.
const uploadTimeout = Duration(seconds: 120);

/// Runs a request that loads a list. A server answer meaning "there is
/// nothing yet" ("No record found", with no data) is an empty list, not an
/// error; a request that hangs ends with a message instead of a spinner.
Future<List<T>> loadList<T>(Future<List<T>> Function() load) async {
  try {
    return await load().timeout(
      listTimeout,
      onTimeout: () =>
          throw const ApiException(serverDownMessage, network: true),
    );
  } on ApiException catch (e) {
    final noData = switch (e.data) {
      null => true,
      '' => true,
      List(isEmpty: true) => true,
      Map(isEmpty: true) => true,
      _ => false,
    };
    final saysEmpty = RegExp(
      r'\b(no|not)\b.*\b(found|record|records|data|request|requests|leave|leaves)\b|\bempty\b',
      caseSensitive: false,
    ).hasMatch(e.message);
    if (!e.network && noData && saysEmpty) return const [];
    rethrow;
  }
}

/// Thin wrapper over Dio for the Nexora HCM envelope:
/// `{status, message, data}`. Throws [ApiException] whenever `status` is
/// false, even when HTTP is 200.
class ApiClient {
  ApiClient({
    required SessionStore session,
    required this.onUnauthorized,
    this.onServerTime,
    Dio? dio,
  }) : _session = session,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: AppConfig.baseUrl,
               connectTimeout: const Duration(seconds: 8),
               sendTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 20),
               headers: {
                 'Accept': 'application/json',
                 'apk-version': AppConfig.appVersion,
               },
             ),
           ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = session.token;
          if (token != null) options.headers['Bearer-Token'] = token;
          final device = session.cachedDeviceToken;
          if (device != null) options.headers['Device-Token'] = device;
          handler.next(options);
        },
        onResponse: (response, handler) {
          _noteServerTime(response);
          handler.next(response);
        },
        onError: (error, handler) {
          final response = error.response;
          if (response != null) _noteServerTime(response);
          handler.next(error);
        },
      ),
    );
  }

  final SessionStore _session;
  final Dio _dio;
  final void Function() onUnauthorized;

  /// Called with the server time (HTTP `Date` header) of every answer.
  final void Function(DateTime serverTime)? onServerTime;

  void _noteServerTime(Response<dynamic> response) {
    final header = response.headers.value('date');
    if (header == null) return;
    try {
      onServerTime?.call(HttpDate.parse(header));
    } catch (_) {}
  }

  Future<Json> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get<dynamic>(path, queryParameters: query));

  /// [files] are sent as a multipart upload next to the [fields].
  Future<Json> post(
    String path, [
    Map<String, dynamic> fields = const {},
    Map<String, MultipartFile> files = const {},
  ]) => _send(
    () => _dio.post<dynamic>(
      path,
      data: FormData.fromMap(fields)..files.addAll(files.entries),
      // A file takes much longer to send than a form: do not give up on it
      // after the 15 s of an ordinary request (that cut uploads off halfway).
      options: files.isEmpty
          ? null
          : Options(sendTimeout: uploadTimeout, receiveTimeout: uploadTimeout),
    ),
    upload: files.isNotEmpty,
  );

  /// Downloads the payslip PDF. It lives outside `/api/v1` and takes the
  /// token in the URL. When something is wrong the server answers with JSON
  /// (`{"status":"FALSE","msg":"..."}`) instead of a PDF: that message is
  /// thrown. A PDF is recognised by what it starts with (`%PDF`), not only by
  /// the content type a server happens to send.
  Future<({Uint8List bytes, String filename})> downloadPayslip(
    String payslipId,
  ) async {
    final url = Uri.parse(AppConfig.baseUrl)
        .resolve('/payslip-pdf')
        .replace(
          queryParameters: {
            'token': _session.token ?? '',
            'device_token': _session.cachedDeviceToken ?? '',
            'pc_id': payslipId,
          },
        );

    /// The server's own words from a JSON body, when there are some.
    String? serverMessage(List<int>? bytes) {
      try {
        final body = jsonDecode(utf8.decode(bytes ?? const []));
        return body is Map ? _message(Json.from(body)) : null;
      } catch (_) {
        return null;
      }
    }

    try {
      final res = await _dio.getUri<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          // Making the PDF can take a while (the first one longest).
          receiveTimeout: const Duration(seconds: 40),
          // The app asks for JSON everywhere else; here a file is wanted.
          headers: {
            'Accept': 'application/pdf, application/json;q=0.9, */*;q=0.8',
          },
        ),
      );
      final bytes = Uint8List.fromList(res.data ?? const []);
      final isPdf =
          bytes.length > 4 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46; // "%PDF"
      if (!isPdf) {
        throw ApiException(
          serverMessage(bytes) ??
              'The server did not send a PDF (answered ${res.statusCode}).',
        );
      }
      final disposition = res.headers.value('content-disposition') ?? '';
      final name = RegExp(r'filename="?([^";]+)"?')
          .firstMatch(disposition)
          ?.group(1);
      return (bytes: bytes, filename: name ?? 'Payslip-$payslipId.pdf');
    } on DioException catch (e) {
      final res = e.response;
      if (res == null) {
        throw ApiException(await _networkMessage(), network: true);
      }
      final data = res.data;
      throw ApiException(
        (data is List<int> ? serverMessage(data) : null) ??
            'The server could not give the payslip (error ${res.statusCode}).',
      );
    }
  }

  /// Downloads a file from an `api/v1` path. When the server cannot give it
  /// (not found, not yours) it answers with JSON instead: that message is
  /// thrown.
  Future<({Uint8List bytes, String filename})> download(
    String path, {
    String fallbackName = 'file',
  }) async {
    try {
      final res = await _dio.get<List<int>>(
        path,
        options: Options(
          responseType: ResponseType.bytes,
          // A file is wanted here, not the JSON the app asks for elsewhere.
          headers: {'Accept': '*/*'},
        ),
      );
      final bytes = Uint8List.fromList(res.data ?? const []);
      final type = res.headers.value('content-type') ?? '';
      if (type.contains('json')) {
        String? message;
        try {
          final body = jsonDecode(utf8.decode(bytes));
          if (body is Map) message = _message(Json.from(body));
        } catch (_) {}
        throw ApiException(message ?? 'Could not get the file.');
      }
      final disposition = res.headers.value('content-disposition') ?? '';
      final name = RegExp(r'filename="?([^";]+)"?')
          .firstMatch(disposition)
          ?.group(1);
      return (bytes: bytes, filename: name ?? fallbackName);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) onUnauthorized();
      throw ApiException(
        network: e.response == null,
        e.response == null
            ? await _networkMessage()
            : 'Something went wrong. Please try again.',
      );
    }
  }

  Future<Json> _send(
    Future<Response<dynamic>> Function() call, {
    bool upload = false,
  }) async {
    try {
      final res = await call();
      final body = res.data;
      if (body is! Map) {
        throw const ApiException('Unexpected response from server.');
      }
      final json = Json.from(body);
      // `reset-password` answers with the string "TRUE" / "FALSE".
      final ok = json['status']?.toString().toLowerCase() == 'true';
      if (!ok) {
        throw ApiException(
          _message(json) ?? 'Request failed.',
          data: json['data'],
        );
      }
      return json;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401) onUnauthorized();
      final body = e.response?.data;
      final message = body is Map ? _message(Json.from(body)) : null;
      // An upload that ran out of time is not "the server is down".
      final tooSlow =
          upload &&
          (e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.receiveTimeout);
      throw ApiException(
        data: body is Map ? body['data'] : null,
        network: e.response == null,
        message ??
            (tooSlow
                ? uploadSlowMessage
                : e.response == null
                ? await _networkMessage()
                : 'Something went wrong. Please try again.'),
      );
    }
  }

  /// Why the server could not be reached: the phone has no connection, or the
  /// server is down. Without a way to tell (e.g. in tests) it is the server.
  static Future<String> _networkMessage() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (result.every((r) => r == ConnectivityResult.none)) {
        return noInternetMessage;
      }
    } catch (_) {}
    return serverDownMessage;
  }

  /// Middleware errors use `msg`, controllers use `message`.
  static String? _message(Json json) =>
      (json['message'] ?? json['msg'])?.toString();
}
