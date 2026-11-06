import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../leave/domain/time_off_models.dart';
import '../domain/help_desk_models.dart';

abstract class HelpDeskRepository {
  Future<TicketsData> tickets();

  /// The people of the given departments (the employee himself not included).
  Future<List<TicketPerson>> peopleOf(List<String> departmentIds);

  Future<void> addTicket({
    required String message,
    required List<String> departmentIds,
    List<String> employeeIds = const [],
    Attachment? attachment,
  });

  /// Changes a pending ticket: the departments and people given replace the
  /// old ones, a new file replaces the old one.
  Future<void> updateTicket({
    required String id,
    required String message,
    required List<String> departmentIds,
    List<String> employeeIds = const [],
    Attachment? attachment,
  });

  /// Throws the server's message ("Help desk ticket id is invalid.").
  Future<TicketDetail> detail(String id);

  /// The file of a ticket. Throws "Attachment not found." when there is none.
  Future<({Uint8List bytes, String filename})> attachment(
    String id, {
    String? name,
  });
}

class ApiHelpDeskRepository implements HelpDeskRepository {
  ApiHelpDeskRepository(this._api);

  final ApiClient _api;

  static List<Map> _rows(dynamic list) =>
      list is List ? list.whereType<Map>().toList() : const [];

  /// `name[0]=a&name[1]=b`: how the server reads a list of ids.
  static Map<String, String> _list(String name, List<String> values) => {
    for (var i = 0; i < values.length; i++) '$name[$i]': values[i],
  };

  @override
  Future<TicketsData> tickets() async {
    final data = (await _api.get('my-tickets'))['data'];
    if (data is! Map) return const TicketsData(tickets: [], departments: []);
    return TicketsData(
      tickets: _rows(data['get_my_help_desks']).map(Ticket.fromApi).toList(),
      departments: (data['departments'] is List
          ? (data['departments'] as List)
                .map(HelpDeskDepartment.fromApi)
                .whereType<HelpDeskDepartment>()
                .toList()
          : const <HelpDeskDepartment>[]),
    );
  }

  @override
  Future<List<TicketPerson>> peopleOf(List<String> departmentIds) async {
    if (departmentIds.isEmpty) return const [];
    final json = await _api.post(
      'get-employee-department-hd',
      _list('department', departmentIds),
    );
    final data = json['data'];
    return data is List
        ? data.map(TicketPerson.fromApi).whereType<TicketPerson>().toList()
        : const [];
  }

  @override
  Future<void> addTicket({
    required String message,
    required List<String> departmentIds,
    List<String> employeeIds = const [],
    Attachment? attachment,
  }) async {
    await _api.post(
      'add-help-desk',
      {
        'message': message,
        ..._list('department_id', departmentIds),
        ..._list('employee_id', employeeIds),
      },
      {
        if (attachment != null)
          'attachment': MultipartFile.fromBytes(
            attachment.bytes,
            filename: attachment.name,
          ),
      },
    );
  }

  @override
  Future<void> updateTicket({
    required String id,
    required String message,
    required List<String> departmentIds,
    List<String> employeeIds = const [],
    Attachment? attachment,
  }) async {
    await _api.post(
      'update-help-desk',
      {
        'hd_id': id,
        'message': message,
        ..._list('department_id', departmentIds),
        ..._list('employee_id', employeeIds),
      },
      {
        if (attachment != null)
          'attachment': MultipartFile.fromBytes(
            attachment.bytes,
            filename: attachment.name,
          ),
      },
    );
  }

  @override
  Future<({Uint8List bytes, String filename})> attachment(
    String id, {
    String? name,
  }) => _api.download(
    'my-help-desk-attachment/$id',
    fallbackName: name ?? 'attachment-$id',
  );

  /// ids from a list of ids, or of objects holding one.
  static Set<String> _ids(dynamic list, String key) {
    if (list is! List) return const {};
    return {
      for (final e in list)
        if (e is Map)
          '${e[key] ?? (e.values.isEmpty ? '' : e.values.first)}'
        else
          '$e',
    }..remove('');
  }

  @override
  Future<TicketDetail> detail(String id) async {
    final data = (await _api.get('my-help-desk-detail/$id'))['data'];
    final map = data is Map ? data : const {};
    final head = _rows(map['help_desk']);
    final first = head.isEmpty ? const {} : head.first;
    String? text(dynamic v) {
      final t = v?.toString().trim();
      return t == null || t.isEmpty || t == 'null' ? null : t;
    }

    return TicketDetail(
      message: text(first['help_message']) ?? '',
      employeeName: text(first['employee_name']),
      createdAt: DateTime.tryParse('${first['created_time']}'),
      attachment: text(first['help_attachment']),
      history: [
        for (final s in _rows(map['help_desk_status']))
          TicketStep(
            by: text(s['employee_name']) ?? '',
            status: TicketStatus.fromApi(s['ticket_status']),
            time: DateTime.tryParse('${s['ticket_status_created_time']}'),
          ),
      ],
      departmentIds: _ids(map['help_desk_departments'], 'department_id'),
      employeeIds: _ids(map['help_desk_employees_selected'], 'employee_id'),
    );
  }
}
