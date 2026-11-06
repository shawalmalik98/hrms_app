import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/attendance_models.dart';

/// Punches made without internet, kept on the phone until they are sent.
/// One queue per employee, so a different login never sends someone else's.
class OfflineQueue {
  OfflineQueue(this._key, [FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final String _key;
  final FlutterSecureStorage _storage;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<List<OfflinePunch>> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list.map(OfflinePunch.fromJson).whereType<OfflinePunch>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(OfflinePunch punch) async {
    final list = await load();
    // Only the last check out of a day counts, no need to keep the others.
    if (!punch.isCheckIn) {
      list.removeWhere((p) => !p.isCheckIn && _sameDay(p.time, punch.time));
    }
    list.add(punch);
    await _storage.write(
      key: _key,
      value: jsonEncode(list.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

/// The employee's office locations, saved while online so that the location
/// rule can also be applied when there is no internet.
class OfficeCache {
  OfficeCache(this._key, [FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final String _key;
  final FlutterSecureStorage _storage;

  /// One copy per employee, so another login never sees these.
  factory OfficeCache.forEmployee(String employeeId) =>
      OfficeCache('office_locations_$employeeId');

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
      await _storage.delete(key: '${_key}_skip');
      await _storage.delete(key: '${_key}_wfh');
    } catch (_) {}
  }

  /// The days the employee's work from home is approved, saved while online
  /// so the offline location check can skip those days like the server does.
  Future<void> saveWfhDates(List<String> dates) async {
    try {
      await _storage.write(key: '${_key}_wfh', value: jsonEncode(dates));
    } catch (_) {}
  }

  Future<bool> isWfhDay(DateTime day) async {
    try {
      final raw = await _storage.read(key: '${_key}_wfh');
      if (raw == null) return false;
      return (jsonDecode(raw) as List).contains(_day(day));
    } catch (_) {
      return false;
    }
  }

  Future<void> save(OfficeData data) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(data.toJson()));
    } catch (_) {}
  }

  /// Null when the locations were never downloaded on this phone.
  Future<OfficeData?> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return OfficeData.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The server accepted a punch from a place the app considered outside the
  /// office, so it is not checking this employee today (for example an
  /// approved remote work day). Only valid for the day it was learned.
  Future<void> markServerSkipsToday() async {
    try {
      await _storage.write(key: '${_key}_skip', value: _day(DateTime.now()));
    } catch (_) {}
  }

  Future<void> clearServerSkips() async {
    try {
      await _storage.delete(key: '${_key}_skip');
    } catch (_) {}
  }

  Future<bool> serverSkipsToday() async {
    try {
      return await _storage.read(key: '${_key}_skip') == _day(DateTime.now());
    } catch (_) {
      return false;
    }
  }
}
