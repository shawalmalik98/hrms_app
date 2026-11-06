import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../files/file_viewer.dart';
import '../network/api_client.dart';
import '../theme/app_theme.dart';

/// How a [FileDownload] looks.
enum FileDownloadStyle {
  /// Just a download icon (on a list card).
  icon,

  /// The file's name as a tappable link with a paper clip.
  link,

  /// A full width outlined button.
  button,
}

/// Fetches a file from the server and opens it with the phone's own viewer.
/// Shows a spinner while it works and the server's own message when it
/// cannot ("File Not Found.").
class FileDownload extends StatefulWidget {
  const FileDownload({
    super.key,
    required this.fetch,
    this.style = FileDownloadStyle.icon,
    this.label,
  });

  final Future<({Uint8List bytes, String filename})> Function() fetch;
  final FileDownloadStyle style;

  /// The text of a link or a button.
  final String? label;

  @override
  State<FileDownload> createState() => _FileDownloadState();
}

class _FileDownloadState extends State<FileDownload> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await widget.fetch();
      if (!mounted) return;
      await openFile(context, file.bytes, file.filename);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      // Not one of the server's messages: say what it was, to be fixed.
      final detail = '$e'.replaceAll(RegExp(r'\s+'), ' ');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the file. (${detail.length > 120 ? detail.substring(0, 120) : detail})',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const spinner = SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    switch (widget.style) {
      case FileDownloadStyle.icon:
        return IconButton(
          tooltip: 'Download attachment',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
          onPressed: _busy ? null : _run,
          icon: _busy
              ? spinner
              : const Icon(Icons.download_rounded, color: AppColors.primary),
        );
      case FileDownloadStyle.link:
        return InkWell(
          onTap: _busy ? null : _run,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.attach_file_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    widget.label ?? 'Attachment',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case FileDownloadStyle.button:
        return OutlinedButton.icon(
          onPressed: _busy ? null : _run,
          icon: _busy ? spinner : const Icon(Icons.download_rounded, size: 18),
          label: Text(_busy ? 'Downloading...' : widget.label ?? 'Download'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
    }
  }
}
