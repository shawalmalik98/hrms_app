import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../application/attendance_providers.dart';
import 'attendance_history_screen.dart';
import 'attendance_request_screen.dart';

class AttendanceTab extends ConsumerStatefulWidget {
  const AttendanceTab({super.key});

  @override
  ConsumerState<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends ConsumerState<AttendanceTab>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  late final Timer _clock;
  StreamSubscription<List<ConnectivityResult>>? _connection;
  DateTime _now = DateTime.now();
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // React to the connection changing right away, no restart needed.
    _connection = ref.read(connectivityStreamProvider).listen((results) {
      final notifier = ref.read(todayAttendanceProvider.notifier);
      if (results.every((r) => r == ConnectivityResult.none)) {
        notifier.markOffline();
      } else {
        notifier.refresh();
      }
    });

    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final newDay = now.day != _now.day;
      setState(() => _now = now);
      // A connection can exist without the server being reachable (WiFi with
      // no internet, another network). Keep trying every few seconds while
      // offline; otherwise just send anything saved offline.
      if (++_ticks % 10 == 0) {
        final notifier = ref.read(todayAttendanceProvider.notifier);
        if (ref.read(todayAttendanceProvider).offline) {
          notifier.refresh();
        } else {
          notifier.syncPending();
        }
      }
      // At midnight the day rolls over: reload so check in opens again and
      // yesterday's check out can no longer be updated.
      if (newDay) {
        ref.read(todayAttendanceProvider.notifier).refresh();
        ref.invalidate(attendanceHistoryProvider);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the background (or from the settings screen after switching
    // the internet on): refresh straight away.
    if (state == AppLifecycleState.resumed) {
      ref.read(todayAttendanceProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connection?.cancel();
    _clock.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayAttendanceProvider);
    final notifier = ref.read(todayAttendanceProvider.notifier);
    final time = DateFormat('hh:mm a');

    final checkIn = today.record?.checkIn;
    final checkOut = today.record?.checkOut;

    return ListView(
      // The page ends above the bottom bar, so a small gap is all it needs.
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        FadeInUp(
          child: AppCard(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Column(
                children: [
                  Text(
                    DateFormat('hh:mm:ss a').format(_now),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  Text(
                    DateFormat('EEEE, dd MMMM yyyy').format(_now),
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FadeInUp(
          index: 1,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _PunchCard(
                    pulse: _pulse,
                    title: 'Check In',
                    icon: Icons.login_rounded,
                    time: checkIn == null ? null : time.format(checkIn),
                    // Once a day: open until the check in is done.
                    enabled: !today.checkedIn && !today.busy,
                    highlight: !today.checkedIn,
                    busy: today.busy && today.kind == PunchKind.checkIn,
                    caption: today.checkedIn ? 'Checked in' : 'Tap to check in',
                    onTap: notifier.checkIn,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PunchCard(
                    pulse: _pulse,
                    title: 'Check Out',
                    icon: Icons.logout_rounded,
                    time: checkOut == null ? null : time.format(checkOut),
                    // Needs a check in; can be repeated, the last one counts.
                    enabled: today.checkedIn && !today.busy,
                    highlight: today.checkedIn,
                    busy: today.busy && today.kind == PunchKind.checkOut,
                    caption: !today.checkedIn
                        ? 'Check in first'
                        : (today.checkedOut
                              ? 'Tap to update'
                              : 'Tap to check out'),
                    onTap: notifier.checkOut,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (today.notice != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 18,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    today.notice!,
                    style: const TextStyle(
                      color: Color(0xFF92600A),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (today.error != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    today.error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        FadeInUp(
          index: 2,
          child: _NavTile(
            icon: Icons.calendar_month_rounded,
            color: AppColors.primary,
            title: 'View Attendance',
            subtitle: 'Daily check in / check out history',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const AttendanceHistoryScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        FadeInUp(
          index: 3,
          child: _NavTile(
            icon: Icons.edit_calendar_rounded,
            color: AppColors.info,
            title: 'Attendance Request',
            subtitle: 'Request a correction for a missed punch',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const AttendanceRequestScreen(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One box per action. Shows the round button and, once done, its time.
class _PunchCard extends StatelessWidget {
  const _PunchCard({
    required this.pulse,
    required this.title,
    required this.icon,
    required this.time,
    required this.enabled,
    required this.highlight,
    required this.busy,
    required this.caption,
    required this.onTap,
  });

  final Animation<double> pulse;
  final String title;
  final IconData icon;
  final String? time;
  final bool enabled;

  /// The action the employee is expected to do next (gets the pulse).
  final bool highlight;
  final bool busy;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const size = 84.0;
    final done = time != null;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 128,
            width: 128,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (enabled && highlight)
                  AnimatedBuilder(
                    animation: pulse,
                    builder: (_, _) {
                      final t = pulse.value;
                      return Container(
                        width: size + t * 44,
                        height: size + t * 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(
                            alpha: 0.18 * (1 - t),
                          ),
                        ),
                      );
                    },
                  ),
                GestureDetector(
                  onTap: enabled ? onTap : null,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: enabled
                          ? AppColors.primaryGradient
                          : LinearGradient(
                              colors: done
                                  ? [
                                      AppColors.primary.withValues(alpha: 0.35),
                                      AppColors.primaryActive.withValues(
                                        alpha: 0.35,
                                      ),
                                    ]
                                  : const [
                                      Color(0xFFE2E8F0),
                                      Color(0xFFCBD5E1),
                                    ],
                            ),
                      boxShadow: enabled
                          ? AppColors.glow(AppColors.primary)
                          : null,
                    ),
                    child: busy
                        ? const Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : Icon(
                            // Finished and closed (check in): show a tick.
                            done && !enabled ? Icons.check_rounded : icon,
                            size: 38,
                            color: enabled || done
                                ? Colors.white
                                : AppColors.muted,
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            time ?? '--:--',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: done ? AppColors.navy : AppColors.muted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 16,
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }
}
