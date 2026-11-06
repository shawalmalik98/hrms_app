import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The employee's picture. When there is none (or it cannot be loaded) the app's
/// own "N." logo is shown, or the initials on the brand gradient when
/// [initialsOnly] is set (to tell colleagues apart in a list).
class EmployeeAvatar extends StatelessWidget {
  const EmployeeAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 52,
    this.ring = false,
    this.initialsOnly = false,
  });

  final String name;
  final String? imageUrl;
  final double size;

  /// A light ring around it, for use on a dark background.
  final bool ring;

  /// Show initials rather than the logo when there is no picture.
  final bool initialsOnly;

  static const logoAsset = 'assets/images/nexora-mark.png';

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    // No picture: the logo (or the initials).
    final fallback = initialsOnly
        ? initials
        // The logo has a margin all around: zoom in so the N fills the circle.
        : Transform.scale(
            scale: 1.45,
            child: Image.asset(logoAsset, fit: BoxFit.cover),
          );

    final url = imageUrl;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring ? 3 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ring ? Colors.white.withValues(alpha: 0.25) : null,
      ),
      child: ClipOval(
        child: url == null
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : fallback,
              ),
      ),
    );
  }
}
