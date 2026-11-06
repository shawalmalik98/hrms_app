undef $/;
sub edit { my ($f, $fn) = @_; open my $h, '<', $f or die $f; my $s = <$h>; close $h; $s = $fn->($s); open my $o, '>', $f; print $o $s; close $o; }

edit('lib/core/network/api_client.dart', sub { my $s = shift;
  # messages
  $s =~ s/(const noInternetMessage =\n    'No internet connection\. Please check your connection and try again\.';)/$1\n\n\/\/\/ Shown when a file upload runs out of time.\nconst uploadSlowMessage =\n    'The upload took too long. Try a smaller file or a better connection.';\n\n\/\/\/ How long an upload may take. Most requests are tiny; a file is not.\nconst uploadTimeout = Duration(seconds: 120);/ or die 1;

  # a request with a file gets the long time
  $s =~ s/  \]\) => _send\(\n    \(\) => _dio\.post<dynamic>\(\n      path,\n      data: FormData\.fromMap\(fields\)\.\.files\.addAll\(files\.entries\),\n    \),\n  \);/  ]) => _send(\n    () => _dio.post<dynamic>(\n      path,\n      data: FormData.fromMap(fields)..files.addAll(files.entries),\n      \/\/ A file takes much longer to send than a form: do not give up on it\n      \/\/ after the 15 s of an ordinary request (that cut uploads off halfway).\n      options: files.isEmpty\n          ? null\n          : Options(sendTimeout: uploadTimeout, receiveTimeout: uploadTimeout),\n    ),\n    upload: files.isNotEmpty,\n  );/ or die 2;

  $s =~ s/  Future<Json> _send\(Future<Response<dynamic>> Function\(\) call\) async \{/  Future<Json> _send(\n    Future<Response<dynamic>> Function() call, {\n    bool upload = false,\n  }) async {/ or die 3;

  $s =~ s/      final message = body is Map \? _message\(Json\.from\(body\)\) : null;\n      throw ApiException\(\n        data: body is Map \? body\['data'\] : null,\n        network: e\.response == null,\n        message \?\?\n            \(e\.response == null\n                \? await _networkMessage\(\)\n                : 'Something went wrong\. Please try again\.'\),\n      \);/      final message = body is Map ? _message(Json.from(body)) : null;\n      \/\/ An upload that ran out of time is not "the server is down".\n      final tooSlow =\n          upload \&\&\n          (e.type == DioExceptionType.sendTimeout ||\n              e.type == DioExceptionType.receiveTimeout);\n      throw ApiException(\n        data: body is Map ? body['data'] : null,\n        network: e.response == null,\n        message ??\n            (tooSlow\n                ? uploadSlowMessage\n                : e.response == null\n                ? await _networkMessage()\n                : 'Something went wrong. Please try again.'),\n      );/ or die 4;
  $s; });

# the picker makes a big picture smaller before it is sent
edit('lib/features/leave/presentation/time_off_widgets.dart', sub { my $s = shift;
  $s =~ s/  final size = await file\.length\(\);\n  if \(size != null && size > Attachment\.maxBytes\) \{\n    throw const FormatException\('The file is too big\. The limit is 10 MB\.'\);\n  \}\n  return Attachment\(name: file\.name, bytes: await file\.readAsBytes\(\)\);/  final size = await file.length();\n  \/\/ A picture over the limit may still become small enough once shrunk.\n  final isPicture = RegExp(r'\\.(jpe?g|png)\$', caseSensitive: false).hasMatch(file.name);\n  if (size != null \&\& size > Attachment.maxBytes \&\& !isPicture) {\n    throw const FormatException('The file is too big. The limit is 10 MB.');\n  }\n  \/\/ Pictures from a camera are big: send a smaller copy (it uploads faster).\n  final ready = await shrinkIfImage(await file.readAsBytes(), file.name);\n  if (ready.bytes.length > Attachment.maxBytes) {\n    throw const FormatException('The file is too big. The limit is 10 MB.');\n  }\n  return Attachment(name: ready.name, bytes: ready.bytes);/ or die 5;
  $s =~ s/import 'package:flutter\/material.dart';/import 'package:flutter\/material.dart';\n\nimport '..\/..\/..\/core\/files\/image_shrink.dart';/ or die 6;
  $s; });

# `image` is used by the app now, not only by the icon tool
edit('pubspec.yaml', sub { my $s = shift;
  $s =~ s/  image: \^4\.12\.0\n// or die 7;
  $s =~ s/(  pdfx: \^2\.11\.0\n)/$1  image: ^4.12.0\n/ or die 8;
  $s; });
