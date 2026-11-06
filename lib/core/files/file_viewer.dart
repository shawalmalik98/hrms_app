import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../theme/app_theme.dart';
import 'open_download.dart';

/// What the app can show inside itself.
enum ViewerKind { pdf, image, text, other }

ViewerKind viewerKindFor(String filename) {
  final dot = filename.lastIndexOf('.');
  final ext = dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'pdf' => ViewerKind.pdf,
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' => ViewerKind.image,
    'txt' || 'csv' || 'log' => ViewerKind.text,
    _ => ViewerKind.other,
  };
}

String _mimeFor(String filename) => switch (viewerKindFor(filename)) {
  ViewerKind.pdf => 'application/pdf',
  ViewerKind.image => 'image/${filename.split('.').last.toLowerCase()}',
  ViewerKind.text => 'text/plain',
  ViewerKind.other => 'application/octet-stream',
};

/// Saves the file where the employee chooses (the phone's "Save as" screen,
/// e.g. Downloads). Returns false when cancelled or when it could not.
Future<bool> saveToPhone(Uint8List bytes, String filename) async {
  try {
    final saved = await FilePicker.saveFile(
      fileName: filename,
      bytes: bytes,
      mimeType: _mimeFor(filename),
      dialogTitle: 'Save file',
    );
    return saved != null;
  } catch (_) {
    return false;
  }
}

/// Shows a downloaded file. PDFs, pictures and text open inside the app, so it
/// works whatever apps the phone has. Anything else (Word, Excel) is handed to
/// the phone's own app; when the phone has none, the file is offered for
/// saving instead, so the employee always gets it.
Future<void> openFile(
  BuildContext context,
  Uint8List bytes,
  String filename,
) async {
  final kind = viewerKindFor(filename);
  if (kind != ViewerKind.other) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FileViewerScreen(bytes: bytes, filename: filename, kind: kind),
      ),
    );
    return;
  }

  var opened = false;
  try {
    opened = await saveAndOpen(bytes, filename);
  } catch (_) {}
  if (opened || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(
      content: Text(
        'No app on this phone can open this kind of file. Choose where to '
        'save it.',
      ),
    ),
  );
  final saved = await saveToPhone(bytes, filename);
  if (saved) {
    messenger.showSnackBar(const SnackBar(content: Text('File saved.')));
  }
}

class FileViewerScreen extends StatelessWidget {
  const FileViewerScreen({
    super.key,
    required this.bytes,
    required this.filename,
    required this.kind,
  });

  final Uint8List bytes;
  final String filename;
  final ViewerKind kind;

  Future<void> _save(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await saveToPhone(bytes, filename);
    if (saved) {
      messenger.showSnackBar(const SnackBar(content: Text('File saved.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(filename, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Save to phone',
            icon: const Icon(Icons.download_rounded),
            onPressed: () => _save(context),
          ),
        ],
      ),
      body: switch (kind) {
        ViewerKind.pdf => _PdfBody(
          bytes: bytes,
          filename: filename,
          onSave: () => _save(context),
        ),
        ViewerKind.image => InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: Image.memory(
              bytes,
              errorBuilder: (_, _, _) => _Problem(
                'This picture cannot be shown.',
                onSave: () => _save(context),
              ),
            ),
          ),
        ),
        _ => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SelectableText(
            utf8.decode(bytes, allowMalformed: true),
            style: const TextStyle(fontSize: 14, color: AppColors.navy),
          ),
        ),
      },
    );
  }
}

class _PdfBody extends StatefulWidget {
  const _PdfBody({
    required this.bytes,
    required this.filename,
    required this.onSave,
  });

  final Uint8List bytes;
  final String filename;
  final VoidCallback onSave;

  @override
  State<_PdfBody> createState() => _PdfBodyState();
}

class _PdfBodyState extends State<_PdfBody> {
  late final PdfControllerPinch _controller = PdfControllerPinch(
    document: PdfDocument.openData(widget.bytes),
  );

  /// Why the PDF could not be shown (null while it can).
  Object? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openElsewhere() async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await saveAndOpen(widget.bytes, widget.filename);
    } catch (_) {}
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No other app on this phone can open this PDF.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return _Problem(
        'This PDF cannot be shown here.',
        detail: '$error'.replaceAll(RegExp(r'\s+'), ' '),
        onSave: widget.onSave,
        onOpenElsewhere: _openElsewhere,
      );
    }
    return PdfViewPinch(
      controller: _controller,
      onDocumentError: (e) => setState(() => _error = e),
      backgroundDecoration: const BoxDecoration(color: AppColors.background),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem(
    this.text, {
    required this.onSave,
    this.detail,
    this.onOpenElsewhere,
  });

  final String text;

  /// The technical reason, small, so a developer can tell what happened.
  final String? detail;
  final VoidCallback onSave;
  final VoidCallback? onOpenElsewhere;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_rounded,
            size: 48,
            color: AppColors.border,
          ),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.body),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!.length > 160 ? detail!.substring(0, 160) : detail!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
          const SizedBox(height: 14),
          if (onOpenElsewhere != null) ...[
            FilledButton.icon(
              onPressed: onOpenElsewhere,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open in another app'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Save to phone'),
          ),
        ],
      ),
    ),
  );
}
