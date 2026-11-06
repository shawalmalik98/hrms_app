import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../attendance/application/attendance_providers.dart';
import '../../attendance/domain/attendance_models.dart';
import '../../auth/application/auth_provider.dart';
import '../../../core/widgets/avatar.dart';
import '../../auth/application/profile_provider.dart';
import '../../auth/presentation/profile_screen.dart';

class DashboardTab extends ConsumerWidget {
  const DashboardTab({super.key});

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final today = ref.watch(todayAttendanceProvider);
    final history = ref.watch(attendanceHistoryProvider).value ?? const [];
    final time = DateFormat('hh:mm a');
    final profile = ref.watch(profileProvider).value;
    final role = [
      profile?.designation,
      profile?.department,
    ].whereType<String>().join('  •  ');

    // Present covers every day the employee came: on time, late, half day or
    // early out. The View Attendance page keeps the detailed statuses.
    final present = [
      AttendanceStatus.onTime,
      AttendanceStatus.late,
      AttendanceStatus.halfDay,
      AttendanceStatus.earlyOut,
    ].fold<int>(0, (n, s) => n + history.where((r) => r.status == s).length);
    int count(AttendanceStatus s) => history.where((r) => r.status == s).length;

    return ListView(
      // The page ends above the bottom bar, so a small gap is all it needs.
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        FadeInUp(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: AppColors.darkGradient,
              borderRadius: BorderRadius.circular(28),
              boxShadow: AppColors.glow(AppColors.primary),
            ),
            child: Stack(
              children: [
                const Positioned.fill(child: Bubbles()),
                Positioned(
                  top: 18,
                  right: 18,
                  child: Semantics(
                    button: true,
                    label: 'My profile',
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ProfileScreen(),
                        ),
                      ),
                      child: EmployeeAvatar(
                        name: user?.name ?? '',
                        imageUrl: profile?.imageUrl,
                        size: 54,
                        ring: true,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              DateFormat('EEE, dd MMM yyyy')
                                  .format(DateTime.now()),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${_greeting()} 👋',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.name ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (role.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.badge_outlined,
                              size: 15,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                role,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _Punch(
                              icon: Icons.login_rounded,
                              label: 'Check In',
                              value: today.record?.checkIn == null
                                  ? '--:--'
                                  : time.format(today.record!.checkIn!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _Punch(
                              icon: Icons.logout_rounded,
                              label: 'Check Out',
                              value: today.record?.checkOut == null
                                  ? '--:--'
                                  : time.format(today.record!.checkOut!),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const _SectionTitle('This Period'),
        const SizedBox(height: 12),
        FadeInUp(
          index: 1,
          child: GridView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            // A fixed height, so the cards look the same on every screen.
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 92,
            ),
            children: [
              _Stat(
                label: 'Present',
                value: present,
                icon: Icons.check_circle_rounded,
                color: AppColors.primary,
              ),
              _Stat(
                label: 'Absent',
                value: count(AttendanceStatus.absent),
                icon: Icons.cancel_rounded,
                color: AppColors.danger,
              ),
              _Stat(
                label: 'Off Days',
                value: count(AttendanceStatus.offDay),
                icon: Icons.beach_access_rounded,
                color: AppColors.warning,
              ),
              _Stat(
                label: 'Leaves',
                value: count(AttendanceStatus.leave),
                icon: Icons.flight_takeoff_rounded,
                color: AppColors.info,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Punch extends StatelessWidget {
  const _Punch({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w800,
      color: AppColors.navy,
    ),
  );
}
