import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../config/app_config.dart';

class LocationException implements Exception {
  const LocationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The office geofence itself is enforced by the server (it replies with
/// "You are N m away from Head Office"). This only makes sure we send a fresh,
/// accurate and genuine GPS fix.
class LocationGuard {
  static Future<Position> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('Please turn on location services.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Location permission is required to mark attendance.',
      );
    }

    final position = await _bestFix();
    if (position == null) {
      throw const LocationException(
        'Could not get your location. Move to an open area and try again.',
      );
    }

    if (position.isMocked) {
      throw const LocationException(
        'Fake location detected. Disable mock location apps to continue.',
      );
    }
    if (position.accuracy > AppConfig.maxAccuracyMeters) {
      throw const LocationException(
        'GPS signal is weak. Move to an open area and try again.',
      );
    }
    return position;
  }

  /// The first GPS fix is often the worst one, mostly without internet when
  /// there is no WiFi / tower help. Listen for a few seconds and keep the most
  /// accurate fix, stopping early once it is good enough.
  static Future<Position?> _bestFix() async {
    const goodEnough = 25.0;
    const maxWait = Duration(seconds: 12);

    Position? best;
    final done = Completer<void>();
    final subscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
          ),
        ).listen(
          (p) {
            // A fake fix must not be replaced by a real one: keep it so the
            // isMocked check refuses the punch.
            if (best?.isMocked ?? false) return;
            if (p.isMocked || best == null || p.accuracy < best!.accuracy) {
              best = p;
            }
            if ((best!.isMocked || best!.accuracy <= goodEnough) &&
                !done.isCompleted) {
              done.complete();
            }
          },
          onError: (_) {
            if (!done.isCompleted) done.complete();
          },
        );

    await Future.any([done.future, Future<void>.delayed(maxWait)]);
    await subscription.cancel();
    return best;
  }

  /// Best effort fix for the login history. Never throws.
  static Future<Position?> tryCurrentPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 6),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
