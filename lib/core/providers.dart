import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/application/auth_provider.dart';
import 'network/api_client.dart';
import 'storage/session_store.dart';
import 'time/trusted_clock.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

final trustedClockProvider = Provider<TrustedClock>((ref) => TrustedClock());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    session: ref.watch(sessionStoreProvider),
    // Every server answer re-syncs the clock used for offline punches.
    onServerTime: (t) => ref.read(trustedClockProvider).anchor(t),
    // 401 means the token is no longer valid: back to the login screen.
    onUnauthorized: () {
      if (ref.read(authProvider) == null) return;
      ref
          .read(logoutNoticeProvider.notifier)
          .set('You were signed out. Please log in again.');
      ref.read(authProvider.notifier).logout();
    },
  ),
);

/// Connection changes of the phone (WiFi / mobile data on or off). A provider
/// so tests can replace it.
final connectivityStreamProvider = Provider<Stream<List<ConnectivityResult>>>(
  (ref) => Connectivity().onConnectivityChanged,
);
