import 'package:intl/intl.dart';

enum AttendanceStatus {
  onTime,
  late,
  halfDay,
  earlyOut,
  absent,
  offDay,
  holiday,
  leave,
  notMarked;

  /// Maps the server's day status text. Anything unknown (a leave name such
  /// as "Annual Leave", "RPL") is treated as a leave.
  static AttendanceStatus fromApi(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'present') return onTime;
    if (s == 'late coming') return late;
    if (s == 'half day') return halfDay;
    if (s == 'early out') return earlyOut;
    if (s == 'absent') return absent;
    if (s == 'off day') return offDay;
    if (s.startsWith('holiday')) return holiday;
    if (s == 'not marked yet' || s == '-' || s.isEmpty) return notMarked;
    return leave;
  }
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.date,
    required this.status,
    required this.statusLabel,
    this.checkIn,
    this.checkOut,
  });

  final DateTime date;
  final AttendanceStatus status;

  /// The text from the server, e.g. "Annual Leave" or "Holiday : Eid".
  final String statusLabel;
  final DateTime? checkIn;
  final DateTime? checkOut;

  Duration? get worked => (checkIn != null && checkOut != null)
      ? checkOut!.difference(checkIn!)
      : null;

  AttendanceRecord copyWith({DateTime? checkIn, DateTime? checkOut}) =>
      AttendanceRecord(
        date: date,
        status: status,
        statusLabel: statusLabel,
        checkIn: checkIn ?? this.checkIn,
        checkOut: checkOut ?? this.checkOut,
      );
}

/// A check in / check out made without internet, waiting to be sent.
class OfflinePunch {
  const OfflinePunch({
    required this.isCheckIn,
    required this.time,
    required this.latitude,
    required this.longitude,
  });

  final bool isCheckIn;

  /// Phone time of the punch.
  final DateTime time;
  final double latitude;
  final double longitude;

  static final _format = DateFormat('yyyy-MM-dd HH:mm:ss');

  /// One item of the `attendance_object` array of `offline-attendance`.
  Map<String, dynamic> toApi() => {
    if (isCheckIn) 'checkin': 1 else 'checkout': 1,
    'formatted_date': _format.format(time),
    'location_latitude': '$latitude',
    'location_longitude': '$longitude',
  };

  Map<String, dynamic> toJson() => {
    'in': isCheckIn,
    'time': time.toIso8601String(),
    'lat': latitude,
    'lng': longitude,
  };

  static OfflinePunch? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final time = DateTime.tryParse(raw['time']?.toString() ?? '');
    final lat = (raw['lat'] as num?)?.toDouble();
    final lng = (raw['lng'] as num?)?.toDouble();
    if (time == null || lat == null || lng == null) return null;
    return OfflinePunch(
      isCheckIn: raw['in'] == true,
      time: time,
      latitude: lat,
      longitude: lng,
    );
  }
}

enum RequestType {
  present('Present'),
  halfDay('Half day'),
  onTimeCheckIn('On Time Check In'),
  onTimeCheckOut('On Time Check Out');

  const RequestType(this.apiValue);
  final String apiValue;

  bool get needsCheckIn => this == onTimeCheckIn;
  bool get needsCheckOut => this == onTimeCheckOut;
}

/// 1 = pending, 2 = approved, 3 = rejected on the server.
enum RequestStatus {
  pending,
  approved,
  rejected;

  static RequestStatus fromApi(dynamic raw) {
    final s = raw?.toString().trim().toLowerCase();
    if (s == '2' || s == 'approved') return approved;
    if (s == '3' || s == 'rejected' || s == 'disapproved') return rejected;
    return pending;
  }
}

class AttendanceRequest {
  const AttendanceRequest({
    this.id = '',
    this.responded = false,
    required this.appliedFor,
    required this.typeLabel,
    required this.message,
    required this.status,
    this.checkIn,
    this.checkOut,
  });

  final String id;

  /// A manager has answered it or changed its time.
  final bool responded;
  final DateTime? appliedFor;
  final String typeLabel;
  final String message;
  final RequestStatus status;
  final String? checkIn;
  final String? checkOut;

  /// Only the employee's own, pending request that nobody answered.
  bool get canEdit => status == RequestStatus.pending && !responded;

  RequestType? get type {
    for (final t in RequestType.values) {
      if (t.apiValue.toLowerCase() == typeLabel.toLowerCase()) return t;
    }
    return null;
  }
}

class NewAttendanceRequest {
  const NewAttendanceRequest({
    required this.date,
    required this.type,
    required this.message,
    this.checkIn,
    this.checkOut,
  });

  final DateTime date;
  final RequestType type;
  final String message;

  /// `HH:mm:ss`
  final String? checkIn;
  final String? checkOut;
}

/// An office the employee may mark attendance from (Admin -> Locations).
class OfficeLocation {
  const OfficeLocation({
    required this.title,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final String title;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  /// The server skips offices without coordinates (0 or empty).
  bool get hasCoordinates => latitude != 0 || longitude != 0;

  Map<String, dynamic> toJson() => {
    'title': title,
    'lat': latitude,
    'lng': longitude,
    'radius': radiusMeters,
  };

  static OfficeLocation? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final lat = double.tryParse('${raw['lat']}');
    final lng = double.tryParse('${raw['lng']}');
    final radius = double.tryParse('${raw['radius']}');
    if (lat == null || lng == null || radius == null) return null;
    return OfficeLocation(
      title: raw['title']?.toString() ?? 'Office',
      latitude: lat,
      longitude: lng,
      radiusMeters: radius,
    );
  }

  /// One item of `employee-mapped-location`.
  static OfficeLocation? fromApi(dynamic raw) {
    if (raw is! Map) return null;
    return fromJson({
      'title': raw['location_title'],
      'lat': raw['location_latitude'],
      'lng': raw['location_longitude'],
      'radius': raw['location_attendance_radius'],
    });
  }
}

/// What the phone keeps for the offline location check.
class OfficeData {
  const OfficeData({required this.offices, this.enforce});

  final List<OfficeLocation> offices;

  /// Whether the server checks this employee's location at all: only when
  /// geofencing is on and the job type is Office. `false` means the server
  /// lets this employee punch from anywhere, so the app must too. `null`
  /// means unknown, treated as on.
  final bool? enforce;

  Map<String, dynamic> toJson() => {
    'offices': offices.map((o) => o.toJson()).toList(),
    'enforce': enforce,
  };

  static OfficeData? fromJson(dynamic raw) {
    // Older copies were just the list of offices.
    if (raw is List) {
      return OfficeData(
        offices: raw
            .map(OfficeLocation.fromJson)
            .whereType<OfficeLocation>()
            .toList(),
      );
    }
    if (raw is! Map || raw['offices'] is! List) return null;
    return OfficeData(
      offices: (raw['offices'] as List)
          .map(OfficeLocation.fromJson)
          .whereType<OfficeLocation>()
          .toList(),
      enforce: raw['enforce'] is bool ? raw['enforce'] as bool : null,
    );
  }
}
