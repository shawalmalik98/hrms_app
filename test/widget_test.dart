import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/providers.dart';
import 'package:hrms_app/features/attendance/application/attendance_providers.dart';
import 'package:hrms_app/features/attendance/data/attendance_repository.dart';
import 'package:hrms_app/features/attendance/domain/attendance_models.dart';
import 'package:hrms_app/features/auth/application/auth_provider.dart';
import 'package:hrms_app/features/auth/application/profile_provider.dart';
import 'package:hrms_app/features/leave/application/time_off_providers.dart';
import 'package:hrms_app/features/services/application/services_providers.dart';
import 'package:hrms_app/main.dart';

class _FakeAuth extends AuthNotifier {
  @override
  Future<void> login(String employeeCode, String password) async {
    state = AuthUser(employeeId: employeeCode, name: 'Test User');
  }
}

class _FakeRepository implements AttendanceRepository {
  @override
  Future<AttendanceRecord?> today() async => null;

  @override
  Future<void> checkIn({
    required double latitude,
    required double longitude,
  }) async {}

  @override
  Future<void> checkOut({
    required double latitude,
    required double longitude,
  }) async {}

  @override
  Future<List<AttendanceRecord>> history() async => [
    AttendanceRecord(
      date: DateTime(2026, 11, 1),
      status: AttendanceStatus.onTime,
      statusLabel: 'Present',
    ),
  ];

  @override
  Future<List<AttendanceRequest>> requests() async => const [];

  @override
  Future<void> submitRequest(NewAttendanceRequest request) async {}

  @override
  Future<void> updateRequest(String id, NewAttendanceRequest request) async {}

  @override
  Future<void> pushOffline(List<OfflinePunch> punches) async {}

  @override
  Future<List<OfficeLocation>> officeLocations() async => const [];

  @override
  Future<bool?> geofenceEnforced() async => null;

  @override
  Future<List<String>> wfhApprovedDates() async => const [];
}

Widget _app() => ProviderScope(
  overrides: [
    authProvider.overrideWith(_FakeAuth.new),
    attendanceRepositoryProvider.overrideWithValue(_FakeRepository()),
    connectivityStreamProvider.overrideWithValue(const Stream.empty()),
    profileProvider.overrideWith(
      (ref) async => const EmployeeProfile(
        designation: 'Software Engineer',
        department: 'IT',
      ),
    ),
    myLeavesProvider.overrideWith((ref) async => []),
    myWfhProvider.overrideWith((ref) async => []),
    leaveTypesProvider.overrideWith((ref) async => []),
    payslipsProvider.overrideWith((ref) async => []),
  ],
  child: const HrmsApp(),
);

void main() {
  test('server day status maps to the app status', () {
    expect(AttendanceStatus.fromApi('Present'), AttendanceStatus.onTime);
    expect(AttendanceStatus.fromApi('Late Coming'), AttendanceStatus.late);
    expect(AttendanceStatus.fromApi('Half day'), AttendanceStatus.halfDay);
    expect(AttendanceStatus.fromApi('Off Day'), AttendanceStatus.offDay);
    expect(AttendanceStatus.fromApi('Holiday : Eid'), AttendanceStatus.holiday);
    expect(AttendanceStatus.fromApi('Annual Leave'), AttendanceStatus.leave);
    expect(
      AttendanceStatus.fromApi('Not marked yet'),
      AttendanceStatus.notMarked,
    );
  });

  testWidgets('Login screen validates empty fields', (tester) async {
    await tester.pumpWidget(_app());

    await tester.tap(find.text('LOG IN'));
    await tester.pump();
    expect(find.text('Employee ID is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
  });

  testWidgets('Login opens dashboard with attendance options', (tester) async {
    await tester.pumpWidget(_app());

    await tester.enterText(find.byType(TextField).at(0), '1000000');
    await tester.enterText(find.byType(TextField).at(1), '123');
    await tester.tap(find.text('LOG IN'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.textContaining('Software Engineer'), findsOneWidget);
    expect(find.textContaining('IT'), findsWidgets);

    await tester.tap(find.byIcon(Icons.fingerprint).last);
    await tester.pump();
    expect(find.text('Check In'), findsWidgets);
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pump();
    expect(find.text('View Attendance'), findsOneWidget);
    expect(find.text('Attendance Request'), findsOneWidget);
  });
}
