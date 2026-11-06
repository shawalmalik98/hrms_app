import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../domain/time_off_models.dart';

abstract class TimeOffRepository {
  Future<List<LeaveType>> leaveTypes();
  Future<List<LeaveRequest>> myLeaves();

  /// The file of a leave (by the leave id). Throws "File Not Found." when
  /// there is none.
  Future<({Uint8List bytes, String filename})> attachment(
    String leaveId, {
    String? name,
  });

  /// Changes one day of a pending leave.
  Future<void> updateLeave({
    required String id,
    required String typeId,
    required String reason,
    required DateTime date,
    Attachment? attachment,
  });

  /// One day when [to] is null or the same day, otherwise a range.
  Future<void> applyLeave({
    required String typeId,
    required String reason,
    required DateTime from,
    DateTime? to,
    Attachment? attachment,
  });

  Future<List<WfhRequest>> myWfh();
  Future<void> submitWfh({
    required String reason,
    required DateTime from,
    DateTime? to,
  });
}

class ApiTimeOffRepository implements TimeOffRepository {
  ApiTimeOffRepository(this._api);

  final ApiClient _api;

  static final _day = DateFormat('yyyy-MM-dd');

  static bool _isRange(DateTime from, DateTime? to) =>
      to != null && _day.format(to) != _day.format(from);

  static Map<String, MultipartFile> _file(Attachment? a) => a == null
      ? const {}
      : {
          'leave_applied_attachment': MultipartFile.fromBytes(
            a.bytes,
            filename: a.name,
          ),
        };

  static List<Map> _rows(dynamic list) =>
      list is List ? list.whereType<Map>().toList() : const [];

  @override
  Future<List<LeaveType>> leaveTypes() async {
    final json = await _api.get('leave-management');
    final data = json['data'];
    if (data is! List) return const [];
    return data.map(LeaveType.fromApi).whereType<LeaveType>().toList();
  }

  @override
  Future<List<LeaveRequest>> myLeaves() async {
    final json = await _api.get('my-leaves');
    final data = json['data'];
    final responded = responseIds(
      data is Map ? data['responsed_request'] : null,
    );
    return _rows(data is Map ? data['my_leaves'] : null)
        .map((row) => LeaveRequest.fromApi(row, responded))
        .toList();
  }

  @override
  Future<({Uint8List bytes, String filename})> attachment(
    String leaveId, {
    String? name,
  }) => _api.download(
    'download-leave-file?leave_id=$leaveId',
    fallbackName: name ?? 'leave-$leaveId',
  );

  @override
  Future<void> updateLeave({
    required String id,
    required String typeId,
    required String reason,
    required DateTime date,
    Attachment? attachment,
  }) async {
    await _api.post('update-leave-request', {
      'leave_id': id,
      'leave_date': _day.format(date),
      'edit_leave_type': typeId,
      'edit_leave_reason': reason,
    }, _file(attachment));
  }

  @override
  Future<void> applyLeave({
    required String typeId,
    required String reason,
    required DateTime from,
    DateTime? to,
    Attachment? attachment,
  }) async {
    final range = _isRange(from, to);
    await _api.post('applyfor_leave', {
      'days_assign': range ? 'multiple' : 'single',
      if (range) ...{
        'from_date': _day.format(from),
        'to_date': _day.format(to!),
      } else
        'leave_date': _day.format(from),
      'leave_type': typeId,
      'leave_reason': reason,
    }, _file(attachment));
  }

  @override
  Future<List<WfhRequest>> myWfh() async {
    final json = await _api.get('my-wfh-requests');
    final data = json['data'];
    return _rows(data is Map ? data['my_requests'] : null)
        .map(WfhRequest.fromApi)
        .toList();
  }

  @override
  Future<void> submitWfh({
    required String reason,
    required DateTime from,
    DateTime? to,
  }) async {
    final range = _isRange(from, to);
    await _api.post('submit_wfh_request', {
      'days_assign': range ? 'multiple' : 'single',
      if (range) ...{
        'from_date': _day.format(from),
        'to_date': _day.format(to!),
      } else
        'request_date': _day.format(from),
      'home_work_reason': reason,
    });
  }
}
