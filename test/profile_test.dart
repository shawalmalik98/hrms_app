import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/core/widgets/avatar.dart';
import 'package:hrms_app/features/auth/application/auth_provider.dart';
import 'package:hrms_app/features/auth/application/profile_provider.dart';
import 'package:hrms_app/features/auth/presentation/profile_screen.dart';

class _Auth extends AuthNotifier {
  @override
  AuthUser? build() => const AuthUser(employeeId: '1000001', name: 'Ali Raza');
}

Widget _host(EmployeeProfile profile, {List<String> offices = const []}) =>
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_Auth.new),
        profileProvider.overrideWith((ref) async => profile),
        officeNamesProvider.overrideWith((ref) async => offices),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    );

void main() {
  test('personal and work details are found by their usual names', () {
    final p = EmployeeProfile.fromApi({
      'employee': {
        'employee_name': 'Ali Raza',
        'employee_cnic': '42101-1234567-1',
        'employee_dob': '1995-05-20',
        'employee_phone': '0300-1234567',
        'employee_email': 'ali@telecard.com.pk',
        'employee_address': 'House 5, Karachi',
        'employee_jobtype': 'Office',
        'employee_job_title': 'Backend Developer',
        'employee_joining_date': '2022-01-03',
        'designation_name': 'Software Engineer',
        'department': {'name': 'IT'},
        'employee_image': 'uploads/ali.png',
      },
    });

    expect(p.cnic, '42101-1234567-1');
    expect(p.dateOfBirth, '20 May 1995');
    expect(p.joiningDate, '03 Jan 2022');
    expect(p.phone, '0300-1234567');
    expect(p.email, 'ali@telecard.com.pk');
    expect(p.address, 'House 5, Karachi');
    expect(p.jobType, 'Office');
    expect(p.jobTitle, 'Backend Developer');
    expect(p.designation, 'Software Engineer');
    expect(p.department, 'IT');
    expect(p.imageUrl, 'http://192.168.88.71:8001/uploads/ali.png');
  });

  test('a full address of a picture is kept; missing details stay empty', () {
    final p = EmployeeProfile.fromApi({
      'employee_image': 'https://cdn.example.com/a.png',
      'employee_dob': '04-11-1990',
    });
    expect(p.imageUrl, 'https://cdn.example.com/a.png');
    expect(p.dateOfBirth, '04 Nov 1990');
    expect(p.cnic, isNull);
    expect(p.isEmpty, isFalse);
    expect(EmployeeProfile.fromApi({'x': 1}).isEmpty, isTrue);
  });

  test('a saved profile comes back the same', () {
    const p = EmployeeProfile(
      designation: 'Engineer',
      cnic: '1',
      phone: '2',
      imageUrl: 'http://x/y.png',
    );
    final back = EmployeeProfile.fromJson(p.toJson());
    expect(back.designation, 'Engineer');
    expect(back.cnic, '1');
    expect(back.phone, '2');
    expect(back.imageUrl, 'http://x/y.png');
    expect(back.email, isNull);
  });

  test('fields under other names are still found', () {
    final p = EmployeeProfile.fromApi({
      'data': {
        'emp_cnic_no': '42101-7654321-9',
        'date_of_birth_text': '1991-02-14',
        'mobile_number': '0321-5551234',
        'official_email_id': 'sara@telecard.com.pk',
        'home_address_line': 'Flat 2, Lahore',
        'emp_job_title_name': 'Team Lead',
        'designation_title_name': 'Manager',
      },
    });
    expect(p.cnic, '42101-7654321-9');
    expect(p.dateOfBirth, '14 Feb 1991');
    expect(p.phone, '0321-5551234');
    expect(p.email, 'sara@telecard.com.pk');
    expect(p.address, 'Flat 2, Lahore');
    expect(p.jobTitle, 'Team Lead');
    expect(p.designation, 'Manager');
  });

  testWidgets('every detail has a row; a missing one reads a dash', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const EmployeeProfile(
          designation: 'Software Engineer',
          department: 'IT',
          cnic: '42101-1234567-1',
          jobTitle: 'Backend Developer',
        ),
        offices: ['Head Office', 'Branch Office'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ali Raza'), findsOneWidget);
    expect(find.text('Software Engineer  •  IT'), findsOneWidget);

    // The list builds rows as they scroll into view.
    for (final label in [
      'CNIC',
      'Date of birth',
      'Phone',
      'Email',
      'Job title',
      'Office location',
      'Date of joining',
    ]) {
      await tester.scrollUntilVisible(find.text(label), 200);
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.scrollUntilVisible(find.text('Backend Developer'), 200);
    expect(find.text('Backend Developer'), findsOneWidget);
    expect(find.text('Head Office\nBranch Office'), findsOneWidget);
    // Not sent: a dash.
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('with nothing from the server it says so', (tester) async {
    await tester.pumpWidget(_host(const EmployeeProfile()));
    await tester.pumpAndSettle();
    expect(find.textContaining('not available'), findsOneWidget);
  });

  testWidgets('the app logo shows when there is no picture', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: EmployeeAvatar(name: 'Ali Raza')),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, EmployeeAvatar.logoAsset);
    expect(find.text('AR'), findsNothing);
  });

  testWidgets('initials are used to tell colleagues apart', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmployeeAvatar(name: 'Sara Khan', initialsOnly: true),
        ),
      ),
    );
    expect(find.text('SK'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  const detail = {
    'status': true,
    'message': 'Employee Detail',
    'data': [
      {
        'employee_id': 5,
        'employee_code': '1000001',
        'employee_name': 'Ali',
        'department_name': 'Sales',
        'designation_name': 'Executive',
        'senior_manager': {
          'employee_id': 4,
          'employee_code': '1000004',
          'employee_name': 'Bilal',
          'designation_name': 'Sales Manager',
        },
        'junior_manager': {
          'employee_id': 9,
          'employee_code': '1000009',
          'employee_name': 'Hina',
          'designation_name': 'Team Lead',
        },
        'hod': {
          'employee_id': 3,
          'employee_code': '1000003',
          'employee_name': 'Usman',
          'designation_name': 'Head of Sales',
        },
      },
    ],
  };

  test('senior manager, junior manager and hod are read from data[0]', () {
    final p = EmployeeProfile.fromApi(detail['data']);
    expect(p.seniorManager?.name, 'Bilal');
    expect(p.seniorManager?.designation, 'Sales Manager');
    expect(p.juniorManager?.name, 'Hina');
    expect(p.juniorManager?.designation, 'Team Lead');
    expect(p.hod?.name, 'Usman');
    expect(p.hod?.designation, 'Head of Sales');
    expect(p.hod?.code, '1000003');
    // The employee's own details are not the manager's.
    expect(p.designation, 'Executive');
    expect(p.department, 'Sales');
  });

  test('nobody set is null, and no crash', () {
    final p = EmployeeProfile.fromApi([
      {
        'employee_name': 'Ali',
        'designation_name': 'Executive',
        'senior_manager': null,
        'junior_manager': null,
        'hod': null,
      },
    ]);
    expect(p.seniorManager, isNull);
    expect(p.juniorManager, isNull);
    expect(p.hod, isNull);
    expect(p.designation, 'Executive');

    // A person without a designation still shows.
    final q = EmployeeProfile.fromApi([
      {
        'hod': {'employee_name': 'Usman', 'designation_name': null},
      },
    ]);
    expect(q.hod?.name, 'Usman');
    expect(q.hod?.designation, isNull);
  });

  test('the employee without a designation does not get the manager\'s', () {
    final p = EmployeeProfile.fromApi([
      {
        'employee_name': 'Ali',
        'designation_name': null,
        'department_name': null,
        'senior_manager': {
          'employee_name': 'Bilal',
          'designation_name': 'Sales Manager',
          'department_name': 'Sales',
        },
        'hod': {'employee_name': 'Usman', 'designation_name': 'Head of Sales'},
      },
    ]);
    expect(p.designation, isNull);
    expect(p.department, isNull);
  });

  test('the people come back from the saved copy', () {
    final p = EmployeeProfile.fromApi(detail['data']);
    final back = EmployeeProfile.fromJson(p.toJson());
    expect(back.juniorManager?.name, 'Hina');
    expect(back.hod?.designation, 'Head of Sales');
    expect(back.seniorManager?.code, '1000004');
  });

  test('how long someone has been here', () {
    final now = DateTime(2026, 11, 5);
    expect(tenure('03 Jan 2022', now: now), '4 yrs 10 mo');
    expect(tenure('05 Nov 2025', now: now), '1 yr');
    expect(tenure('20 Jun 2026', now: now), '4 mo');
    expect(tenure('01 Nov 2026', now: now), '4 days');
    expect(tenure('01 Jan 2030', now: now), isNull);
    expect(tenure('soon', now: now), isNull);
    expect(tenure(null, now: now), isNull);
  });

  group('who is HOD and who is the line manager', () {
    const senior = ProfilePerson(name: 'Bilal', designation: 'Sales Manager');
    const junior = ProfilePerson(name: 'Hina', designation: 'Team Lead');
    const head = ProfilePerson(name: 'Usman', designation: 'Head of Sales');

    test('with a hod: the hod is HOD, the senior manager the line manager', () {
      const p = EmployeeProfile(
        seniorManager: senior,
        juniorManager: junior,
        hod: head,
      );
      expect(p.headOfDepartment?.name, 'Usman');
      expect(p.lineManager?.name, 'Bilal');
    });

    test('without a hod: the senior is HOD, the junior the line manager', () {
      const p = EmployeeProfile(seniorManager: senior, juniorManager: junior);
      expect(p.headOfDepartment?.name, 'Bilal');
      expect(p.lineManager?.name, 'Hina');
    });

    test('a hod alone: no line manager, and nobody twice', () {
      const p = EmployeeProfile(hod: head);
      expect(p.headOfDepartment?.name, 'Usman');
      expect(p.lineManager, isNull);
    });

    test('nobody set: nobody', () {
      const p = EmployeeProfile();
      expect(p.headOfDepartment, isNull);
      expect(p.lineManager, isNull);
    });

    testWidgets('with a hod the screen shows HOD and the senior manager', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const EmployeeProfile(
            designation: 'Engineer',
            seniorManager: senior,
            juniorManager: junior,
            hod: head,
            joiningDate: '03 Jan 2022',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reporting'), findsOneWidget);
      expect(find.text('HOD'), findsOneWidget);
      expect(find.text('Usman'), findsOneWidget);
      expect(find.text('Head of Sales'), findsOneWidget);
      expect(find.text('Line Manager'), findsOneWidget);
      expect(find.text('Bilal'), findsOneWidget);
      expect(find.text('Sales Manager'), findsOneWidget);
      // The junior manager is not listed when there is a hod.
      expect(find.text('Hina'), findsNothing);
      // Only these two headings.
      expect(find.text('Senior manager'), findsNothing);
      expect(find.text('Junior manager'), findsNothing);
      expect(find.text('Head of department'), findsNothing);
      expect(find.textContaining('With us'), findsOneWidget);
    });

    testWidgets('without a hod the screen shows senior and junior manager', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const EmployeeProfile(
            designation: 'Engineer',
            seniorManager: senior,
            juniorManager: junior,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('HOD'), findsOneWidget);
      expect(find.text('Bilal'), findsOneWidget);
      expect(find.text('Sales Manager'), findsOneWidget);
      expect(find.text('Line Manager'), findsOneWidget);
      expect(find.text('Hina'), findsOneWidget);
      expect(find.text('Team Lead'), findsOneWidget);
    });

    testWidgets('only a senior manager: HOD shows, line manager not assigned', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const EmployeeProfile(designation: 'Engineer', seniorManager: senior),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bilal'), findsOneWidget);
      expect(find.text('Not assigned'), findsOneWidget);
    });
  });

  testWidgets('nobody set reads Not assigned', (tester) async {
    await tester.pumpWidget(
      _host(const EmployeeProfile(designation: 'Engineer')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reporting'), findsOneWidget);
    expect(find.text('Line Manager'), findsOneWidget);
    expect(find.text('HOD'), findsOneWidget);
    expect(find.text('Not assigned'), findsNWidgets(2));
  });
}
