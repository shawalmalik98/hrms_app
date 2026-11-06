import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/providers.dart';
import 'package:hrms_app/features/auth/application/profile_provider.dart';
import 'package:hrms_app/features/leave/application/time_off_providers.dart';
import 'package:hrms_app/features/leave/data/time_off_repository.dart';
import 'package:hrms_app/features/leave/domain/time_off_models.dart';
import 'package:hrms_app/features/leave/presentation/leave_tab.dart';
import 'package:hrms_app/features/leave/presentation/wfh_tab.dart';

class _FakeTimeOff implements TimeOffRepository {
  @override
  Future<List<LeaveType>> leaveTypes() async => const [
    LeaveType(id: '1', name: 'Casual Leave'),
  ];

  @override
  Future<List<LeaveRequest>> myLeaves() async => [
    LeaveRequest(
      id: '90',
      date: DateTime(2026, 11, 7),
      typeName: 'Casual Leave',
      reason: 'Family event',
      status: TimeOffStatus.pending,
    ),
  ];

  @override
  Future<void> applyLeave({
    required String typeId,
    required String reason,
    required DateTime from,
    DateTime? to,
    Attachment? attachment,
  }) async {}

  @override
  Future<List<WfhRequest>> myWfh() async => [
    WfhRequest(
      id: '180',
      date: DateTime(2026, 11, 6),
      reason: 'Internet work',
      status: TimeOffStatus.approved,
      decision: 'Auto approved by system',
    ),
  ];

  @override
  Future<({Uint8List bytes, String filename})> attachment(
    String leaveId, {
    String? name,
  }) async => (bytes: Uint8List(0), filename: name ?? 'file');

  @override
  Future<void> updateLeave({
    required String id,
    required String typeId,
    required String reason,
    required DateTime date,
    Attachment? attachment,
  }) async {}

  @override
  Future<void> submitWfh({
    required String reason,
    required DateTime from,
    DateTime? to,
  }) async {}
}

Widget _host(Widget child) => ProviderScope(
  overrides: [
    timeOffRepositoryProvider.overrideWithValue(_FakeTimeOff()),
    connectivityStreamProvider.overrideWithValue(const Stream.empty()),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  test('request status follows the server numbers', () {
    expect(TimeOffStatus.fromApi(1), TimeOffStatus.pending);
    expect(TimeOffStatus.fromApi('2'), TimeOffStatus.approved);
    expect(TimeOffStatus.fromApi(3), TimeOffStatus.disapproved);
  });

  test('leave and wfh rows are read from the API shape', () {
    final leave = LeaveRequest.fromApi({
      'leave_applied_id': 90,
      'leave_applied_for_date': '2026-11-07',
      'leave_applied_reason': 'Family event',
      'leave_applied_date': '04-11-2026 11:21:11',
      'leave_approved_by_hr': 2,
      'leave_approved_date_hr': null,
      'leave_applied_attachment': null,
      'leave_name': 'Casual Leave',
    });
    expect(leave.date, DateTime(2026, 11, 7));
    expect(leave.status, TimeOffStatus.approved);
    expect(leave.sentOn, DateTime(2026, 11, 4, 11, 21, 11));
    expect(leave.decision, isNull);

    final wfh = WfhRequest.fromApi({
      'wfh_request_id': 180,
      'wfh_request_date': '2026-11-06',
      'wfh_request_message': 'Internet work',
      'wfh_request_approved_by_hr': 2,
      'wfh_request_approved_date_hr': 'Auto approved by system',
      'wfh_request_submition_date': '04-11-2026 11:21:11',
    });
    expect(wfh.status, TimeOffStatus.approved);
    expect(wfh.decision, 'Auto approved by system');
  });

  test('designation and department are found in the employee detail', () {
    final profile = EmployeeProfile.fromApi({
      'employee': {
        'employee_name': 'Ali',
        'designation_id': 4,
        'designation_name': 'Software Engineer',
        'department': {'name': 'IT'},
      },
    });
    expect(profile.designation, 'Software Engineer');
    expect(profile.department, 'IT');

    // Ids are not shown.
    expect(EmployeeProfile.fromApi({'department': '12'}).isEmpty, isTrue);
  });

  testWidgets('Leave tab lists requests with a filter and an apply button', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const LeaveTab()));
    await tester.pump();
    await tester.pump();

    expect(find.text('APPLY FOR LEAVE'), findsOneWidget);
    expect(find.text('Casual Leave'), findsOneWidget);
    expect(find.text('Pending'), findsWidgets);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Disapproved'), findsOneWidget);

    await tester.tap(find.text('APPLY FOR LEAVE'));
    await tester.pumpAndSettle();
    expect(find.text('SUBMIT LEAVE'), findsOneWidget);
    expect(find.text('One day'), findsOneWidget);
  });

  testWidgets('WFH tab lists requests', (tester) async {
    await tester.pumpWidget(_host(const WfhTab()));
    await tester.pump();
    await tester.pump();

    expect(find.text('REQUEST WFH'), findsOneWidget);
    expect(find.text('Auto approved by system'), findsOneWidget);
  });
}
