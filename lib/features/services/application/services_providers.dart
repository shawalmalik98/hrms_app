import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_provider.dart';
import '../data/help_desk_repository.dart';
import '../data/reimbursement_repository.dart';
import '../data/services_repository.dart';
import '../domain/help_desk_models.dart';
import '../domain/reimbursement_models.dart';
import '../domain/service_models.dart';

final servicesRepositoryProvider = Provider<ServicesRepository>(
  (ref) => ApiServicesRepository(ref.watch(apiClientProvider)),
);

// Each watches authProvider so a different login never shows old data.
Future<T> _load<T>(Future<T> Function() load) => load().timeout(
  listTimeout,
  onTimeout: () => throw const ApiException(serverDownMessage, network: true),
);

/// "Nothing yet" answers from the server are an empty screen, not an error.
Future<T> _orEmpty<T>(Future<T> Function() load, T empty) async {
  try {
    return await _load(load);
  } on ApiException catch (e) {
    final empty0 =
        e.data == null ||
        e.data == '' ||
        (e.data is Iterable && (e.data as Iterable).isEmpty);
    final says = RegExp(
      r'\b(no|not)\b.*\b(found|record|records|data|request|requests|loan|loans|payslip|payslips|resignation|resignations|ticket|tickets|expense|expenses|claim|claims|reimbursement)\b',
      caseSensitive: false,
    ).hasMatch(e.message);
    if (!e.network && empty0 && says) return empty;
    rethrow;
  }
}

final advanceProvider = FutureProvider<AdvanceData>((ref) {
  ref.watch(authProvider);
  final repo = ref.watch(servicesRepositoryProvider);
  return _orEmpty(repo.advances, const AdvanceData(requests: []));
});

final loansProvider = FutureProvider<LoanData>((ref) {
  ref.watch(authProvider);
  final repo = ref.watch(servicesRepositoryProvider);
  return _orEmpty(repo.loans, const LoanData(loans: []));
});

final loanDetailProvider = FutureProvider.family<LoanDetail, String>((ref, id) {
  ref.watch(authProvider);
  return _load(() => ref.watch(servicesRepositoryProvider).loanDetail(id));
});

final payslipsProvider = FutureProvider<List<Payslip>>((ref) {
  ref.watch(authProvider);
  final repo = ref.watch(servicesRepositoryProvider);
  return _orEmpty(repo.payslips, const <Payslip>[]);
});

final resignationsProvider = FutureProvider<List<Resignation>>((ref) {
  ref.watch(authProvider);
  final repo = ref.watch(servicesRepositoryProvider);
  return _orEmpty(repo.resignations, const <Resignation>[]);
});

final helpDeskRepositoryProvider = Provider<HelpDeskRepository>(
  (ref) => ApiHelpDeskRepository(ref.watch(apiClientProvider)),
);

final ticketsProvider = FutureProvider<TicketsData>((ref) {
  ref.watch(authProvider);
  final repo = ref.watch(helpDeskRepositoryProvider);
  return _orEmpty(
    repo.tickets,
    const TicketsData(tickets: [], departments: []),
  );
});

final ticketDetailProvider = FutureProvider.family<TicketDetail, String>((
  ref,
  id,
) {
  ref.watch(authProvider);
  return _load(() => ref.watch(helpDeskRepositoryProvider).detail(id));
});

final reimbursementRepositoryProvider = Provider<ReimbursementRepository>(
  (ref) => ApiReimbursementRepository(ref.watch(apiClientProvider)),
);

final expensesProvider = FutureProvider<ExpenseData>((ref) {
  ref.watch(authProvider);
  final repo = ref.watch(reimbursementRepositoryProvider);
  return _orEmpty(repo.claims, const ExpenseData(claims: []));
});

final amountLogProvider = FutureProvider.family<List<AmountLogEntry>, String>((
  ref,
  id,
) {
  ref.watch(authProvider);
  return _load(() => ref.watch(reimbursementRepositoryProvider).amountLog(id));
});
