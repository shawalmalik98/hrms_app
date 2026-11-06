import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../application/attendance_providers.dart';
import '../domain/attendance_models.dart';

class AttendanceHistoryScreen extends ConsumerWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(attendanceHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Attendance')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load attendance')),
        data: (records) {
          int count(AttendanceStatus s) =>
              records.where((r) => r.status == s).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              SizedBox(
                height: 84,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  children: [
                    _Chip(
                      'On Time',
                      count(AttendanceStatus.onTime),
                      AppColors.primary,
                    ),
                    _Chip(
                      'Absent',
                      count(AttendanceStatus.absent),
                      AppColors.danger,
                    ),
                    _Chip(
                      'Off Days',
                      count(AttendanceStatus.offDay),
                      AppColors.warning,
                    ),
                    _Chip(
                      'Late',
                      count(AttendanceStatus.late),
                      AppColors.warning,
                    ),
                    _Chip(
                      'Half Day',
                      count(AttendanceStatus.halfDay),
                      AppColors.warning,
                    ),
                    _Chip(
                      'Leaves',
                      count(AttendanceStatus.leave),
                      AppColors.info,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < records.length; i++) ...[
                FadeInUp(index: i.clamp(0, 6), child: _RecordCard(records[i])),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard(this.record);

  final AttendanceRecord record;

  static String _hm(DateTime? t) =>
      t == null ? '--:--' : DateFormat('HH:mm').format(t);

  static Color _color(AttendanceStatus s) => switch (s) {
    AttendanceStatus.onTime => AppColors.primary,
    AttendanceStatus.late ||
    AttendanceStatus.halfDay ||
    AttendanceStatus.earlyOut ||
    AttendanceStatus.offDay => AppColors.warning,
    AttendanceStatus.absent => AppColors.danger,
    AttendanceStatus.leave || AttendanceStatus.holiday => AppColors.info,
    AttendanceStatus.notMarked => AppColors.muted,
  };

  static String _label(AttendanceRecord r) => switch (r.status) {
    AttendanceStatus.onTime => 'On Time',
    AttendanceStatus.late => 'Late',
    // Leave and holiday names come from the server ("Annual Leave").
    _ => r.statusLabel,
  };

  @override
  Widget build(BuildContext context) {
    final color = _color(record.status);
    final label = _label(record);
    final worked = record.worked;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  DateFormat('dd').format(record.date),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  DateFormat('MMM').format(record.date).toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE').format(record.date),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_hm(record.checkIn)}  →  ${_hm(record.checkOut)}'
                  '${worked == null ? '' : '  ·  ${worked.inHours}h ${worked.inMinutes % 60}m'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
