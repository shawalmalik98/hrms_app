import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/auth_provider.dart';

/// Asks for confirmation, then clears the session and returns to login.
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Sign out?',
        style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy),
      ),
      content: const Text('You will need to log in again to mark attendance.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          child: const Text('Sign Out'),
        ),
      ],
    ),
  );
  if (confirmed == true) await ref.read(authProvider.notifier).logout();
}
