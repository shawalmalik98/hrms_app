import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Pictures from a phone camera are several MB. Sent as they are they take
/// long on a slow server or Wi-Fi, and a long upload is where uploads fail.
/// A bill or a certificate is perfectly readable at this size.
const _maxSide = 1600;
const _quality = 80;

/// Pictures smaller than this are left exactly as they are.
const _leaveAloneBelow = 800 * 1024;

/// A big jpg or png is made smaller (at most 1600 px on its long side, saved as
/// a good quality jpg). Anything else (a PDF, a small picture, a file that
/// cannot be read as a picture) comes back unchanged.
Future<({Uint8List bytes, String name})> shrinkIfImage(
  Uint8List bytes,
  String name,
) async {
  final lower = name.toLowerCase();
  final isPicture =
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png');
  if (!isPicture || bytes.length <= _leaveAloneBelow) {
    return (bytes: bytes, name: name);
  }

  // Off the screen's thread: decoding a big picture takes a moment.
  final smaller = await Isolate.run(() => _shrink(bytes));
  if (smaller == null || smaller.length >= bytes.length) {
    return (bytes: bytes, name: name);
  }
  final dot = name.lastIndexOf('.');
  return (bytes: smaller, name: '${name.substring(0, dot)}.jpg');
}

Uint8List? _shrink(Uint8List bytes) {
  try {
    var image = img.decodeImage(bytes);
    if (image == null) return null;

    if (image.width > _maxSide || image.height > _maxSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: _maxSide)
          : img.copyResize(image, height: _maxSide);
    }
    // A jpg has no see-through parts: put a transparent picture on white.
    if (image.hasAlpha) {
      final flat = img.Image(width: image.width, height: image.height)
        ..clear(img.ColorRgb8(255, 255, 255));
      image = img.compositeImage(flat, image);
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: _quality));
  } catch (_) {
    return null;
  }
}
