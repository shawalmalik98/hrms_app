import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/update/app_updater.dart';
import '../../../core/widgets/common.dart';

/// Makes every update mandatory: whenever the server has a newer APK, the app
/// shows an "Update now" screen that cannot be dismissed, on the login screen
/// as well as inside the app. It is checked when the app opens and every time
/// it comes back to the foreground. Without internet the server cannot be
/// asked, so the app keeps working offline (attendance is saved and sent
/// later); the next time it is online the update is required.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    // Once an update is required this does not return, so the screen is
    // never shown twice.
    if (_checking || !mounted) return;
    _checking = true;
    try {
      await requireUpdate(context);
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Asks the server if a newer APK exists. If so, keeps asking the user to
/// install it until the app is replaced by the new version. Returns quietly
/// when there is nothing new or the server cannot be reached.
Future<void> requireUpdate(BuildContext context) async {
  final info = await AppUpdater.check();
  if (info == null) return;
  while (true) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateRequiredDialog(info: info),
    );
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadDialog(info: info),
    );
    // Back here when the installer was cancelled: ask again.
  }
}

class UpdateRequiredDialog extends StatelessWidget {
  const UpdateRequiredDialog({super.key, required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Update required',
          style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info.versionName.isNotEmpty)
              Text(
                'Version ${info.versionName}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              info.notes.isNotEmpty
                  ? info.notes
                  : 'A new version of Nexora HCM is ready.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Please update to keep using the app.',
              style: TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Update now'),
          ),
        ],
      ),
    );
  }
}

class _DownloadDialog extends StatefulWidget {
  const _DownloadDialog({required this.info});

  final UpdateInfo info;

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  double? _progress;
  String? _error;

  /// What the plugin reported (status and its text), to find out why an
  /// update failed.
  String? _detail;
  StreamSubscription<OtaEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _progress = 0;
      _error = null;
      _detail = null;
    });
    // A retry must not start while the previous try is still registered.
    await _subscription?.cancel();
    _subscription = null;
    try {
      await OtaUpdate().cancel();
    } catch (_) {}
    if (!mounted) return;
    _subscription = OtaUpdate()
        .execute(widget.info.apkUrl, destinationFilename: 'hrms_update.apk')
        .listen(
          (event) {
            if (!mounted) return;
            switch (event.status) {
              case OtaStatus.DOWNLOADING:
                final percent = double.tryParse(event.value ?? '');
                setState(
                  () => _progress = percent == null ? null : percent / 100,
                );
              case OtaStatus.INSTALLING:
              case OtaStatus.INSTALLATION_DONE:
                // The Android installer takes over from here.
                Navigator.of(context).pop();
              case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                setState(
                  () => _error =
                      'Allow "Install unknown apps" for Nexora HCM in the '
                      'phone settings, then try again.',
                );
              case OtaStatus.CANCELED:
                Navigator.of(context).pop();
              case OtaStatus.ALREADY_RUNNING_ERROR:
                setState(() {
                  _error =
                      'The update is already being downloaded. Wait a moment '
                      'and try again.';
                  _detail = '${event.status.name}: ${event.value}';
                });
              case OtaStatus.INSTALLATION_ERROR:
                setState(() {
                  _error = 'The update could not be installed.';
                  _detail = '${event.status.name}: ${event.value}';
                });
              default:
                setState(() {
                  _error =
                      'Could not download the update. Check your connection '
                      'and try again.';
                  _detail = '${event.status.name}: ${event.value}';
                });
            }
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _error =
                  'Could not download the update. Check your connection and '
                  'try again.';
              _detail = '$e';
            });
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          _error == null ? 'Downloading update' : 'Update failed',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
        content: _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_error!),
                  if (_detail != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _detail!,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 8,
                      color: AppColors.primary,
                      backgroundColor: AppColors.primaryLight,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _progress == null
                        ? 'Please wait...'
                        : '${(_progress! * 100).round()}%',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
        actions: [
          if (_error != null) ...[
            SizedBox(
              width: 120,
              child: GradientButton(label: 'RETRY', onPressed: _start),
            ),
          ],
        ],
      ),
    );
  }
}
