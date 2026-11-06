// Takes pictures of the main screens so the look can be checked without a
// phone. Not part of the normal test run:
//
//   VISUAL=1 flutter test --update-goldens test/visual_test.dart
//
// The pictures land in test/goldens/. Text uses Roboto from the Flutter SDK
// (the app's own font is downloaded at run time).
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/providers.dart';
import 'package:hrms_app/core/theme/app_theme.dart';
import 'package:hrms_app/features/attendance/application/attendance_providers.dart';
import 'package:hrms_app/features/attendance/data/attendance_repository.dart';
import 'package:hrms_app/features/attendance/domain/attendance_models.dart';
import 'package:hrms_app/features/attendance/presentation/attendance_request_screen.dart';
import 'package:hrms_app/features/auth/application/auth_provider.dart';
import 'package:hrms_app/features/auth/application/profile_provider.dart';
import 'package:hrms_app/features/auth/presentation/profile_screen.dart';
import 'package:hrms_app/features/services/presentation/services_tab.dart';
import 'package:hrms_app/features/home/presentation/home_shell.dart';
import 'package:hrms_app/features/leave/application/time_off_providers.dart';
import 'package:hrms_app/features/leave/domain/time_off_models.dart';
import 'package:hrms_app/features/leave/presentation/leave_tab.dart';
import 'package:hrms_app/features/leave/presentation/time_off_widgets.dart';
import 'package:hrms_app/features/services/application/services_providers.dart';
import 'package:hrms_app/features/services/domain/service_models.dart';
import 'package:hrms_app/features/services/presentation/advance_screen.dart';
import 'package:hrms_app/features/services/presentation/loan_screen.dart';
import 'package:hrms_app/features/services/domain/reimbursement_models.dart';
import 'package:hrms_app/features/services/presentation/payslip_screen.dart';
import 'package:hrms_app/features/services/presentation/reimbursement_screen.dart';
import 'package:hrms_app/features/services/presentation/resignation_screen.dart';

class _Auth extends AuthNotifier {
  @override
  AuthUser? build() => const AuthUser(employeeId: '1000001', name: 'Ali Raza');
}

class _Repo implements AttendanceRepository {
  @override
  Future<AttendanceRecord?> today() async => AttendanceRecord(
    date: DateTime(2026, 11, 4),
    status: AttendanceStatus.onTime,
    statusLabel: 'Present',
    checkIn: DateTime(2026, 11, 4, 9, 5),
  );

  @override
  Future<List<AttendanceRecord>> history() async => [
    for (var i = 0; i < 9; i++)
      AttendanceRecord(
        date: DateTime(2026, 11, 3).subtract(Duration(days: i)),
        status: [
          AttendanceStatus.onTime,
          AttendanceStatus.late,
          AttendanceStatus.halfDay,
          AttendanceStatus.offDay,
        ][i % 4],
        statusLabel: 'x',
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #wfhApprovedDates:
        return Future.value(<String>[]);
      case #officeLocations:
        return Future.value(<OfficeLocation>[]);
      case #geofenceEnforced:
        return Future<bool?>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT']!;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> load(String f) async =>
      ByteData.sublistView(await File('$dir/$f').readAsBytes());
  final roboto = FontLoader('Roboto')
    ..addFont(load('roboto-regular.ttf'))
    ..addFont(load('roboto-medium.ttf'))
    ..addFont(load('roboto-bold.ttf'))
    ..addFont(load('roboto-black.ttf'));
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(load('materialicons-regular.otf'));
  await icons.load();
}

Widget _app(
  Widget home, {
  List<Override> overrides = const [],
  List<Payslip> payslips = const [],
  EmployeeProfile profile = const EmployeeProfile(
    designation: 'Software Engineer',
    department: 'Information Technology',
  ),
}) {
  final base = AppTheme.light;
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(_Auth.new),
      attendanceRepositoryProvider.overrideWithValue(_Repo()),
      connectivityStreamProvider.overrideWithValue(const Stream.empty()),
      profileProvider.overrideWith((ref) async => profile),
      payslipsProvider.overrideWith((ref) async => payslips),
      ...overrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
      ),
      home: home,
    ),
  );
}

Future<void> _shot(
  WidgetTester tester,
  String name, {
  bool settle = true,
}) async {
  // Screens with a running clock or animation never "settle".
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(seconds: 2));
  }
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

final _leaves = [
  LeaveRequest(
    id: '1',
    date: DateTime(2026, 11, 7),
    typeName: 'Casual Leave',
    reason: 'Family event',
    status: TimeOffStatus.pending,
    sentOn: DateTime(2026, 11, 4, 11, 21),
    attachment: 'certificate.pdf',
  ),
  LeaveRequest(
    id: '2',
    date: DateTime(2026, 10, 20),
    typeName: 'Sick Leave',
    reason: 'Fever',
    status: TimeOffStatus.approved,
    decision: 'Approved by Sara Khan on 20-10-2026',
    sentOn: DateTime(2026, 10, 19, 9, 0),
  ),
  LeaveRequest(
    id: '3',
    date: DateTime(2026, 10, 2),
    typeName: 'Annual Leave',
    reason: 'Trip',
    status: TimeOffStatus.disapproved,
    decision: 'Disapproved by HR',
    sentOn: DateTime(2026, 9, 30, 15, 30),
  ),
];

void main() {
  final enabled = Platform.environment['VISUAL'] == '1';

  setUpAll(() async {
    if (enabled) await _loadFonts();
  });

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('dashboard', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        const HomeShell(),
        overrides: [
          myLeavesProvider.overrideWith((ref) async => _leaves),
          myWfhProvider.overrideWith((ref) async => []),
        ],
      ),
    );
    await _shot(tester, 'dashboard', settle: false);
  }, skip: !enabled);

  testWidgets('leave', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        const Scaffold(body: SafeArea(child: LeaveTab())),
        overrides: [myLeavesProvider.overrideWith((ref) async => _leaves)],
      ),
    );
    await _shot(tester, 'leave');
  }, skip: !enabled);

  testWidgets('leave form', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        const Scaffold(body: SafeArea(child: LeaveTab())),
        overrides: [
          myLeavesProvider.overrideWith((ref) async => _leaves),
          leaveTypesProvider.overrideWith(
            (ref) async => const [LeaveType(id: '1', name: 'Casual Leave')],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit').first);
    await _shot(tester, 'leave_form');
  }, skip: !enabled);

  testWidgets('advance', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        const AdvanceScreen(),
        overrides: [
          advanceProvider.overrideWith(
            (ref) async => AdvanceData(
              salary: 60000,
              requests: [
                const AdvanceRequest(
                  id: '1',
                  period: '2026-12',
                  amount: 12000,
                  message: 'Medical bills',
                  status: TimeOffStatus.pending,
                  responded: false,
                ),
                const AdvanceRequest(
                  id: '2',
                  period: '2026-11',
                  amount: 7000,
                  message: 'Rent',
                  status: TimeOffStatus.approved,
                  responded: true,
                  decision: 'Approved by Finance',
                  approverMessage: 'Approved',
                ),
              ],
            ),
          ),
        ],
      ),
    );
    await _shot(tester, 'advance');
  }, skip: !enabled);

  testWidgets('loan', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        const LoanScreen(),
        overrides: [
          loansProvider.overrideWith(
            (ref) async => const LoanData(
              given: 50000,
              returned: 5000,
              remaining: 45000,
              loans: [
                Loan(
                  id: '1',
                  reason: 'Bike Loan',
                  message: 'New bike',
                  amount: 50000,
                  percentDeduction: true,
                  deduction: 10,
                  start: '2026-12',
                  status: TimeOffStatus.pending,
                  responded: false,
                ),
                Loan(
                  id: '2',
                  reason: 'Other',
                  message: 'Wedding',
                  amount: 20000,
                  percentDeduction: false,
                  deduction: 2000,
                  start: '2026-11',
                  status: TimeOffStatus.approved,
                  responded: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    await _shot(tester, 'loan');
  }, skip: !enabled);

  testWidgets('loan form', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        const LoanScreen(),
        overrides: [
          loansProvider.overrideWith((ref) async => const LoanData(loans: [])),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('REQUEST A LOAN'));
    await _shot(tester, 'loan_form');
  }, skip: !enabled);

  testWidgets('payslips', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        const PayslipScreen(),
        payslips: const [
          Payslip(
            id: '1',
            month: 10,
            year: 2026,
            gross: 60000,
            extra: 2500,
            deduction: 6870,
            net: 55630,
          ),
          Payslip(
            id: '2',
            month: 9,
            year: 2026,
            gross: 60000,
            extra: 0,
            deduction: 6200,
            net: 53800,
          ),
        ],
      ),
    );
    await _shot(tester, 'payslips');
  }, skip: !enabled);

  testWidgets('attendance requests', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        const AttendanceRequestScreen(),
        overrides: [
          attendanceRequestsProvider.overrideWith(
            (ref) async => [
              AttendanceRequest(
                id: '1',
                appliedFor: DateTime(2026, 11, 3),
                typeLabel: 'On Time Check Out',
                message: 'Forgot check out',
                status: RequestStatus.pending,
                checkOut: '18:00:00',
              ),
              AttendanceRequest(
                id: '2',
                appliedFor: DateTime(2026, 10, 28),
                typeLabel: 'Present',
                message: 'Was on site',
                status: RequestStatus.approved,
              ),
            ],
          ),
        ],
      ),
    );
    await _shot(tester, 'attendance_requests');
  }, skip: !enabled);

  testWidgets('attendance tab', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_app(const HomeShell()));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.fingerprint).last);
    await _shot(tester, 'attendance_tab', settle: false);
  }, skip: !enabled);

  testWidgets('profile', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        const ProfileScreen(),
        profile: EmployeeProfile(
          designation: 'Software Engineer',
          department: 'Information Technology',
          juniorManager: ProfilePerson(
            name: 'Hina Malik',
            designation: 'Team Lead',
          ),
          hod: ProfilePerson(name: 'Usman Ali', designation: 'Head of Sales'),
          jobTitle: 'Backend Developer',
          jobType: 'Office',
          cnic: '42101-1234567-1',
          dateOfBirth: '20 May 1995',
          joiningDate: '03 Jan 2022',
          phone: '0300-1234567',
          email: 'ali.raza@telecard.com.pk',
          address: 'House 5, Block 7, Gulshan-e-Iqbal, Karachi',
        ),
      ),
    );
    await _shot(tester, 'profile');
  }, skip: !enabled);

  testWidgets('more', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(const Scaffold(body: SafeArea(child: ServicesTab()))),
    );
    await _shot(tester, 'more');
  }, skip: !enabled);

  testWidgets('resignation', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        const ResignationScreen(),
        overrides: [
          resignationsProvider.overrideWith(
            (ref) async => [
              Resignation(
                id: '12',
                reason: 'Personal reasons',
                from: DateTime(2026, 11, 10),
                to: DateTime(2026, 12, 10),
                status: TimeOffStatus.pending,
                responded: false,
              ),
            ],
          ),
        ],
      ),
    );
    await _shot(tester, 'resignation');
  }, skip: !enabled);

  testWidgets('more in the shell, scrolled to the end', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_app(const HomeShell()));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.apps_rounded).last);
    await tester.pump(const Duration(seconds: 1));
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await _shot(tester, 'more_in_shell', settle: false);
  }, skip: !enabled);

  testWidgets('reimbursement', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        const ReimbursementScreen(),
        overrides: [
          expensesProvider.overrideWith(
            (ref) async => ExpenseData(
              total: 11300,
              approvedTotal: 9000,
              claims: [
                ExpenseClaim(
                  id: '15',
                  date: DateTime(2026, 11, 4),
                  description: 'Taxi to client office',
                  typeId: 1,
                  typeName: 'Travel and accommodation',
                  amount: 1500,
                  status: TimeOffStatus.pending,
                  paid: false,
                  responded: false,
                  amountChanged: false,
                  attachment: 'bill.pdf',
                ),
                ExpenseClaim(
                  id: '17',
                  date: DateTime(2026, 10, 20),
                  description: 'Hotel in Lahore',
                  typeId: 1,
                  typeName: 'Travel and accommodation',
                  amount: 9000,
                  status: TimeOffStatus.approved,
                  paid: true,
                  responded: true,
                  amountChanged: true,
                  approver: 'Zeeshan',
                  approvedAt: '21-10-2026 10:00',
                  reason: 'Approved with a lower amount',
                  payslipMonth: 10,
                  payslipYear: 2026,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    await _shot(tester, 'reimbursement');
  }, skip: !enabled);

  testWidgets('attachment field', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                AttachmentField(value: null, onChanged: (_) {}),
                const SizedBox(height: 16),
                AttachmentField(
                  value: null,
                  current: 'certificate.pdf',
                  onChanged: (_) {},
                ),
                const SizedBox(height: 16),
                AttachmentField(
                  value: Attachment(
                    name: 'medical-certificate-november.pdf',
                    bytes: Uint8List(1),
                  ),
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await _shot(tester, 'attachment');
  }, skip: !enabled);
}
