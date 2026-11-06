import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../attendance/presentation/attendance_tab.dart';
import '../../auth/presentation/sign_out.dart';
import '../../services/presentation/services_tab.dart';
import 'dashboard_tab.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The logo is the avatar of everybody without a picture: have it ready.
    precacheImage(const AssetImage(EmployeeAvatar.logoAsset), context);
  }

  static const _items = [
    (Icons.grid_view_rounded, 'Dashboard'),
    (Icons.fingerprint, 'Attendance'),
    (Icons.apps_rounded, 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The pages end where the bar begins, so they never scroll behind it.
      extendBody: false,
      appBar: AppBar(
        title: Text(_items[_index].$2),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filledTonal(
              tooltip: 'Sign out',
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
              ),
              icon: const Icon(Icons.logout_rounded, size: 20),
              onPressed: () => confirmSignOut(context, ref),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          const DashboardTab(),
          const AttendanceTab(),
          const ServicesTab(),
        ],
      ),
      bottomNavigationBar: _NavBar(
        items: _items,
        index: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// The floating bottom bar. One glowing capsule glides from tab to tab when
/// another is chosen; the icon of the open tab grows a little and its name
/// turns white. Every tab always shows its name.
class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.items,
    required this.index,
    required this.onTap,
  });

  final List<(IconData, String)> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(22, 0, 22, 12),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          // Deep teal, a shade lighter at the top, like a lit glass bar.
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF14444A), AppColors.dark],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF031A1C).withValues(alpha: 0.35),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SizedBox(
          // Slim: the icon and the name sit side by side, one line.
          height: 40,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Every tab is as wide as its own icon and name plus the SAME
              // space on its left and right, so the open one's capsule is
              // evenly padded whichever tab it is. The tabs are spread so the
              // gaps between them (and at both ends) are all equal.
              final style =
                  (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                      .copyWith(
                        fontSize: 12,
                        letterSpacing: 0.2,
                        fontWeight: FontWeight.w800,
                      );
              final contents = [
                for (final item in items)
                  21 +
                      5 +
                      (TextPainter(
                        text: TextSpan(text: item.$2, style: style),
                        textDirection: TextDirection.ltr,
                        maxLines: 1,
                      )..layout()).width,
              ];
              final contentTotal = contents.fold<double>(0, (a, b) => a + b);
              // 14 on each side; less on a very narrow phone.
              final pad =
                  ((constraints.maxWidth - contentTotal) / (2 * items.length))
                      .clamp(2.0, 14.0);
              final widths = [for (final c in contents) c + 2 * pad];
              final gap =
                  ((constraints.maxWidth -
                              widths.fold<double>(0, (a, b) => a + b)) /
                          (items.length + 1))
                      .clamp(0.0, double.infinity);
              final lefts = <double>[];
              var x = gap;
              for (final w in widths) {
                lefts.add(x);
                x += w + gap;
              }
              return Stack(
                children: [
                  // The capsule: slides (and resizes) to the open tab.
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    left: lefts[index],
                    top: 0,
                    bottom: 0,
                    width: widths[index],
                    child: const _Capsule(),
                  ),
                  for (var i = 0; i < items.length; i++)
                    // The tap area reaches half way into the gaps.
                    Positioned(
                      left: lefts[i] - gap / 2,
                      top: 0,
                      bottom: 0,
                      width: widths[i] + gap,
                      child: _NavItem(
                        icon: items[i].$1,
                        label: items[i].$2,
                        selected: i == index,
                        onTap: () {
                          if (i != index) HapticFeedback.selectionClick();
                          onTap(i);
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The glowing capsule behind the open tab: the brand teal, lit from above.
class _Capsule extends StatelessWidget {
  const _Capsule();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary, AppColors.primaryActive],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.38),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Align(
            alignment: Alignment.topCenter,
            // A soft light along the top edge.
            child: FractionallySizedBox(
              heightFactor: 0.5,
              widthFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.20),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dim = Colors.white.withValues(alpha: 0.55);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutBack,
                child: Icon(
                  icon,
                  size: 19,
                  color: selected ? Colors.white : dim,
                ),
              ),
              const SizedBox(width: 5),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                // Built on the theme's text style, so the app's own font is kept.
                style:
                    (Theme.of(context).textTheme.bodyMedium ??
                            const TextStyle())
                        .copyWith(
                          fontSize: 12,
                          letterSpacing: 0.2,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: selected ? Colors.white : dim,
                        ),
                child: Text(label, maxLines: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
