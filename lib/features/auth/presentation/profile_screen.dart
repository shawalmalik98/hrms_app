import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/common.dart';
import '../application/auth_provider.dart';
import '../application/profile_provider.dart';

/// How long someone has been here, from the joining date as shown
/// ("03 Jan 2022"): "3 yrs 10 mo", "8 mo", "12 days". Null when unknown.
String? tenure(String? joined, {DateTime? now}) {
  if (joined == null) return null;
  DateTime start;
  try {
    start = DateFormat('dd MMM yyyy').parseStrict(joined);
  } catch (_) {
    return null;
  }
  final today = now ?? DateTime.now();
  if (start.isAfter(today)) return null;
  var months = (today.year - start.year) * 12 + today.month - start.month;
  if (today.day < start.day) months--;
  if (months < 1) {
    final days = today.difference(start).inDays;
    return '$days ${days == 1 ? 'day' : 'days'}';
  }
  final years = months ~/ 12;
  final rest = months % 12;
  return [
    if (years > 0) '$years ${years == 1 ? 'yr' : 'yrs'}',
    if (rest > 0) '$rest mo',
  ].join(' ');
}

/// "My Profile": the employee's own details, as far as the server sends them.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final profile = ref.watch(profileProvider);
    final p = profile.value ?? const EmployeeProfile();
    final offices = ref.watch(officeNamesProvider).value ?? const <String>[];

    final role = [
      p.designation,
      p.department,
    ].whereType<String>().join('  •  ');
    final served = tenure(p.joiningDate);

    // (icon, label, value). A detail the server did not send is shown as "—"
    // so the employee sees what is missing.
    final personal = <(IconData, String, String?)>[
      (Icons.badge_rounded, 'CNIC', p.cnic),
      (Icons.cake_rounded, 'Date of birth', p.dateOfBirth),
      (Icons.phone_rounded, 'Phone', p.phone),
      (Icons.email_rounded, 'Email', p.email),
    ];
    final work = <(IconData, String, String?)>[
      (Icons.tag_rounded, 'Employee ID', user?.employeeId),
      (Icons.work_rounded, 'Designation', p.designation),
      (Icons.apartment_rounded, 'Department', p.department),
      (Icons.assignment_ind_rounded, 'Job title', p.jobTitle),
      (Icons.home_work_rounded, 'Job type', p.jobType),
      (
        Icons.pin_drop_rounded,
        'Office location',
        offices.isEmpty ? null : offices.join('\n'),
      ),
      (Icons.event_available_rounded, 'Date of joining', p.joiningDate),
    ];

    // Only these two headings. Someone who is not set reads "Not assigned".
    // (Which person is which: see [EmployeeProfile.headOfDepartment] and
    // [EmployeeProfile.lineManager].)
    final reporting = <(String, ProfilePerson?)>[
      ('Line Manager', p.lineManager),
      ('HOD', p.headOfDepartment),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(profileProvider);
          await ref.read(profileProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            FadeInUp(
              child: _Header(
                name: user?.name ?? '',
                imageUrl: p.imageUrl,
                role: role,
                chips: [
                  'ID  ${user?.employeeId ?? ''}',
                  ?p.jobType,
                  ?(served == null ? null : 'With us  $served'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (profile.isLoading && p.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (p.isEmpty) const _Empty(),
              FadeInUp(index: 1, child: _People(people: reporting)),
              const SizedBox(height: 16),
              FadeInUp(
                index: 2,
                child: _Section(title: 'Personal', rows: personal),
              ),
              const SizedBox(height: 16),
              FadeInUp(
                index: 3,
                child: _Section(title: 'Work', rows: work),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.imageUrl,
    required this.role,
    required this.chips,
  });

  final String name;
  final String? imageUrl;
  final String role;
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppColors.darkGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppColors.glow(AppColors.primary),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: Bubbles()),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  EmployeeAvatar(
                    name: name,
                    imageUrl: imageUrl,
                    size: 96,
                    ring: true,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (role.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      role,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in chips)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            c,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Row(
      children: [
        Icon(Icons.info_rounded, color: AppColors.primary),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Your details are not available right now. Pull down to try again.',
            style: TextStyle(
              color: AppColors.primaryActive,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Who the employee reports to: line manager and head of department, each with
/// their designation; "Not assigned" when not set.
class _People extends StatelessWidget {
  const _People({required this.people});

  /// (role, person)
  final List<(String, ProfilePerson?)> people;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Reporting',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < people.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.border),
                _PersonRow(role: people[i].$1, person: people[i].$2),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.role, required this.person});

  final String role;
  final ProfilePerson? person;

  @override
  Widget build(BuildContext context) {
    final p = person;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          p == null
              ? Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_off_rounded,
                    size: 22,
                    color: AppColors.muted,
                  ),
                )
              : EmployeeAvatar(name: p.name, size: 44, initialsOnly: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  p?.name ?? 'Not assigned',
                  style: TextStyle(
                    color: p == null ? AppColors.muted : AppColors.navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (p?.designation != null)
                  Text(
                    p!.designation!,
                    style: const TextStyle(
                      color: AppColors.body,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<(IconData, String, String?)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.border),
                _Row(icon: rows[i].$1, label: rows[i].$2, value: rows[i].$3),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final shown = value ?? '—';
    return InkWell(
      // Press and hold copies the value (a phone number, an email...).
      onLongPress: value == null
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: value!));
              messenger.showSnackBar(
                SnackBar(
                  content: Text('$label copied'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    shown,
                    style: TextStyle(
                      color: value == null ? AppColors.muted : AppColors.navy,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
