import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Saves a downloaded file in the app's temporary folder and opens it with the
/// phone's own viewer. Returns false when no app can open this kind of file.
Future<bool> saveAndOpen(Uint8List bytes, String filename) async {
  // A name from the server must not point outside the folder.
  final safe = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}${Platform.pathSeparator}$safe';
  await File(path).writeAsBytes(bytes, flush: true);
  final result = await OpenFilex.open(path);
  return result.type == ResultType.done;
}
