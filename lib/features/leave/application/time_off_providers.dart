import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_provider.dart';
import '../data/time_off_repository.dart';
import '../domain/time_off_models.dart';

final timeOffRepositoryProvider = Provider<TimeOffRepository>(
  (ref) => ApiTimeOffRepository(ref.watch(apiClientProvider)),
);

// Each watches authProvider so a different login never shows old data.
final leaveTypesProvider = FutureProvider<List<LeaveType>>((ref) {
  ref.watch(authProvider);
  return loadList(ref.watch(timeOffRepositoryProvider).leaveTypes);
});

final myLeavesProvider = FutureProvider<List<LeaveRequest>>((ref) {
  ref.watch(authProvider);
  return loadList(ref.watch(timeOffRepositoryProvider).myLeaves);
});

final myWfhProvider = FutureProvider<List<WfhRequest>>((ref) {
  ref.watch(authProvider);
  return loadList(ref.watch(timeOffRepositoryProvider).myWfh);
});
