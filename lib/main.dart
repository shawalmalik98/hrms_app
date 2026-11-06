import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/storage/session_store.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_provider.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/home/presentation/home_shell.dart';
import 'features/home/presentation/update_prompt.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SessionStore();
  final session = await store.load();
  await store.deviceToken();

  runApp(
    ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        initialSessionProvider.overrideWithValue(session),
      ],
      child: const HrmsApp(),
    ),
  );
}

class HrmsApp extends ConsumerWidget {
  const HrmsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    return MaterialApp(
      title: 'Nexora HCM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: UpdateGate(
        child: user == null ? const LoginScreen() : const HomeShell(),
      ),
    );
  }
}
