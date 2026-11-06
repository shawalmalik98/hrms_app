import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers.dart';
import '../../attendance/application/attendance_providers.dart';
import '../../attendance/data/offline_queue.dart';
import '../../attendance/domain/attendance_models.dart';
import 'auth_provider.dart';

String? _text(dynamic raw) {
  final v = raw?.toString().trim();
  return v == null || v.isEmpty || v == 'null' ? null : v;
}

/// A colleague the employee reports to: senior manager, junior manager, or
/// head of department.
class ProfilePerson {
  const ProfilePerson({required this.name, this.designation, this.code});

  final String name;
  final String? designation;
  final String? code;

  Map<String, dynamic> toJson() => {
    'name': name,
    'designation': designation,
    'code': code,
  };

  static ProfilePerson? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final name = _text(raw['name']);
    return name == null
        ? null
        : ProfilePerson(
            name: name,
            designation: _text(raw['designation']),
            code: _text(raw['code']),
          );
  }

  /// `{"employee_id":4,"employee_code":"1000004","employee_name":"Bilal",
  /// "designation_name":"Sales Manager"}`, or null when nobody is set.
  static ProfilePerson? fromApi(dynamic raw) {
    if (raw is! Map) return null;
    final name = _text(raw['employee_name']);
    return name == null
        ? null
        : ProfilePerson(
            name: name,
            designation: _text(raw['designation_name']),
            code: _text(raw['employee_code']),
          );
  }
}

/// What the employee's profile shows: designation, department, contact and
/// personal details. Everything is optional: only what the server sends is
/// shown.
class EmployeeProfile {
  const EmployeeProfile({
    this.designation,
    this.department,
    this.jobTitle,
    this.jobType,
    this.cnic,
    this.dateOfBirth,
    this.joiningDate,
    this.phone,
    this.email,
    this.address,
    this.imageUrl,
    this.seniorManager,
    this.juniorManager,
    this.hod,
  });

  final String? designation;
  final String? department;
  final String? jobTitle;
  final String? jobType;
  final String? cnic;
  final String? dateOfBirth;
  final String? joiningDate;
  final String? phone;
  final String? email;
  final String? address;
  final String? imageUrl;

  /// Who the employee reports to. Null: nobody is set ("Not assigned").
  final ProfilePerson? seniorManager;
  final ProfilePerson? juniorManager;
  final ProfilePerson? hod;

  /// What the profile calls "HOD". When the server names a head of department
  /// that is the one; with none, the senior manager takes that place.
  ProfilePerson? get headOfDepartment => hod ?? seniorManager;

  /// What the profile calls "Line Manager". With a head of department the
  /// senior manager is the line manager; with none, the junior manager is.
  ProfilePerson? get lineManager => hod != null ? seniorManager : juniorManager;

  /// True when there is nothing to show under the name.
  bool get isEmpty => toJson().values.every((v) => v == null);

  Map<String, dynamic> toJson() => {
    'designation': designation,
    'department': department,
    'jobTitle': jobTitle,
    'jobType': jobType,
    'cnic': cnic,
    'dateOfBirth': dateOfBirth,
    'joiningDate': joiningDate,
    'phone': phone,
    'email': email,
    'address': address,
    'imageUrl': imageUrl,
    'seniorManager': seniorManager?.toJson(),
    'juniorManager': juniorManager?.toJson(),
    'hod': hod?.toJson(),
  };

  static EmployeeProfile fromJson(dynamic raw) => raw is Map
      ? EmployeeProfile(
          designation: raw['designation'] as String?,
          department: raw['department'] as String?,
          jobTitle: raw['jobTitle'] as String?,
          jobType: raw['jobType'] as String?,
          cnic: raw['cnic'] as String?,
          dateOfBirth: raw['dateOfBirth'] as String?,
          joiningDate: raw['joiningDate'] as String?,
          phone: raw['phone'] as String?,
          email: raw['email'] as String?,
          address: raw['address'] as String?,
          imageUrl: raw['imageUrl'] as String?,
          seniorManager: ProfilePerson.fromJson(raw['seniorManager']),
          juniorManager: ProfilePerson.fromJson(raw['juniorManager']),
          hod: ProfilePerson.fromJson(raw['hod']),
        )
      : const EmployeeProfile();

  /// `get-employee-detail` answers with `data: [ {...} ]`. Most details are
  /// looked up by the names they are most likely to have; the three people
  /// have fixed names: `senior_manager`, `junior_manager` and `hod`.
  static EmployeeProfile fromApi(dynamic data) => EmployeeProfile(
    seniorManager: ProfilePerson.fromApi(_find(data, 'senior_manager')),
    juniorManager: ProfilePerson.fromApi(_find(data, 'junior_manager')),
    hod: ProfilePerson.fromApi(_find(data, 'hod')),
    designation: _lookup(
      data,
      const [
        'designation_name',
        'designation_title',
        'employee_designation',
        'designation',
      ],
      like: const ['designation'],
    ),
    department: _lookup(
      data,
      const [
        'department_name',
        'department_title',
        'employee_department',
        'department',
      ],
      like: const ['department'],
    ),
    jobTitle: _lookup(
      data,
      const [
        'employee_job_title',
        'employee_jobtitle',
        'job_title',
        'jobtitle',
      ],
      likeAll: const ['job', 'title'],
    ),
    jobType: _lookup(data, const ['employee_jobtype', 'job_type']),
    cnic: _lookup(
      data,
      const ['employee_cnic', 'cnic', 'employee_nic'],
      like: const ['cnic'],
    ),
    dateOfBirth: _date(
      _lookup(
        data,
        const [
          'employee_dob',
          'employee_date_of_birth',
          'employee_birth_date',
          'date_of_birth',
          'dob',
        ],
        like: const ['birth', 'dob'],
      ),
    ),
    joiningDate: _date(
      _lookup(
        data,
        const [
          'employee_joining_date',
          'employee_date_of_joining',
          'employee_doj',
          'joining_date',
          'date_of_joining',
          'doj',
        ],
        like: const ['joining', 'joined', 'doj', 'hire'],
      ),
    ),
    phone: _lookup(
      data,
      const [
        'employee_phone',
        'employee_mobile',
        'employee_contact',
        'employee_phone_number',
        'employee_contact_number',
        'employee_cell',
        'phone',
        'mobile',
        'contact_no',
      ],
      like: const ['phone', 'mobile', 'contact', 'cell'],
    ),
    email: _lookup(
      data,
      const [
        'employee_email',
        'employee_official_email',
        'employee_personal_email',
        'email',
      ],
      like: const ['email'],
    ),
    address: _lookup(
      data,
      const [
        'employee_address',
        'employee_current_address',
        'employee_permanent_address',
        'address',
      ],
      like: const ['address'],
    ),
    imageUrl: _imageUrl(
      _lookup(data, const [
        'employee_image',
        'employee_profile_image',
        'employee_picture',
        'employee_photo',
        'profile_image',
        'profile_picture',
        'image',
      ]),
    ),
  );

  /// `2026-11-04` (or `04-11-2026`) as "04 Nov 2026". Anything else is shown
  /// as it came.
  static String? _date(String? raw) {
    if (raw == null) return null;
    final d =
        DateTime.tryParse(raw) ??
        (RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(raw)
            ? DateFormat('dd-MM-yyyy').parse(raw)
            : null);
    return d == null || d.year < 1900
        ? raw
        : DateFormat('dd MMM yyyy').format(d);
  }

  /// A picture named by a path is served from the portal itself.
  static String? _imageUrl(String? raw) {
    if (raw == null) return null;
    if (raw.startsWith('http')) return raw;
    final origin = Uri.parse(AppConfig.baseUrl).origin;
    return '$origin/${raw.startsWith('/') ? raw.substring(1) : raw}';
  }

  static String? _lookup(
    dynamic data,
    List<String> keys, {
    List<String> like = const [],
    List<String> likeAll = const [],
  }) {
    final byName = _lookupExact(data, keys);
    if (byName != null) return byName;
    // Not under the usual names: use any field whose name contains the words.
    if (like.isNotEmpty) return _lookupLike(data, (k) => like.any(k.contains));
    if (likeAll.isNotEmpty) {
      return _lookupLike(data, (k) => likeAll.every(k.contains));
    }
    return null;
  }

  /// The people the employee reports to carry their own `designation_name` and
  /// so on. Looking for the employee's own details must never go in there.
  static const _people = {'senior_manager', 'junior_manager', 'hod'};

  /// The first plain value (text or number) under a key that [match]es.
  static String? _lookupLike(dynamic node, bool Function(String key) match) {
    if (node is Map) {
      for (final e in node.entries) {
        final v = e.value;
        if (match('${e.key}'.toLowerCase()) && (v is String || v is num)) {
          final text = v.toString().trim();
          if (text.isNotEmpty &&
              text != 'null' &&
              !RegExp(r'^\d+$').hasMatch(text)) {
            return text;
          }
        }
      }
      for (final e in node.entries) {
        if (_people.contains(e.key)) continue;
        final r = _lookupLike(e.value, match);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _lookupLike(v, match);
        if (r != null) return r;
      }
    }
    return null;
  }

  static String? _lookupExact(dynamic data, List<String> keys) {
    for (final key in keys) {
      final found = _find(data, key);
      if (found == null) continue;
      // A nested object: take its name.
      final value = found is Map
          ? (found['name'] ?? found['title'] ?? found['${key}_name'])
          : found;
      final text = value?.toString().trim();
      if (text == null || text.isEmpty || text == 'null') continue;
      // For the fields that name something, an id (digits only) is useless.
      final namesSomething = const {
        'designation_name',
        'designation_title',
        'employee_designation',
        'designation',
        'department_name',
        'department_title',
        'employee_department',
        'department',
      }.contains(key);
      if (namesSomething && RegExp(r'^\d+$').hasMatch(text)) continue;
      return text;
    }
    return null;
  }

  static dynamic _find(dynamic node, String key) {
    if (node is Map) {
      if (node.containsKey(key)) return node[key];
      for (final e in node.entries) {
        if (_people.contains(e.key)) continue;
        final r = _find(e.value, key);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _find(v, key);
        if (r != null) return r;
      }
    }
    return null;
  }
}

/// The logged in employee's profile. Saved on the phone so it still shows
/// without internet.
final profileProvider = FutureProvider<EmployeeProfile>((ref) async {
  final id = ref.watch(authProvider)?.employeeId;
  if (id == null) return const EmployeeProfile();

  const storage = FlutterSecureStorage();
  final key = 'profile_$id';
  try {
    final json = await ref.watch(apiClientProvider).get('get-employee-detail');
    final profile = EmployeeProfile.fromApi(json['data']);
    if (!profile.isEmpty) {
      try {
        await storage.write(key: key, value: jsonEncode(profile.toJson()));
      } catch (_) {}
    }
    return profile;
  } catch (_) {
    try {
      final raw = await storage.read(key: key);
      if (raw != null) return EmployeeProfile.fromJson(jsonDecode(raw));
    } catch (_) {}
    return const EmployeeProfile();
  }
});

/// Names of the offices the employee may mark attendance from. Falls back to
/// the copy saved on the phone when offline.
final officeNamesProvider = FutureProvider<List<String>>((ref) async {
  final id = ref.watch(authProvider)?.employeeId;
  if (id == null) return const [];

  List<String> names(Iterable<OfficeLocation> offices) => [
    for (final t in offices.map((o) => o.title.trim()).toSet())
      if (t.isNotEmpty) t,
  ];

  try {
    final found = names(
      await ref.watch(attendanceRepositoryProvider).officeLocations(),
    );
    if (found.isNotEmpty) return found;
  } catch (_) {}
  final cached = await OfficeCache.forEmployee(id).load();
  return cached == null ? const [] : names(cached.offices);
});
