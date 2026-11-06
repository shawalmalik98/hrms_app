import 'attendance_repository.dart';
import 'offline_queue.dart';
import '../domain/attendance_models.dart';

/// Downloads the employee's office locations (all of them) and whether the
/// server checks the location at all, and replaces the copy kept on the phone
/// for the offline location check.
Future<void> downloadOffices(
  AttendanceRepository repo,
  OfficeCache cache, {
  bool Function()? shouldSave,
}) async {
  final offices = await repo.officeLocations();

  bool? enforce;
  try {
    enforce = await repo.geofenceEnforced();
  } catch (_) {}
  // Could not read it this time: keep what was known.
  enforce ??= (await cache.load())?.enforce;

  // Work from home days: no location check on those. Keep the last saved
  // list when it cannot be read now.
  List<String>? wfh;
  try {
    wfh = await repo.wfhApprovedDates();
  } catch (_) {}

  if (shouldSave != null && !shouldSave()) return;
  await cache.save(OfficeData(offices: offices, enforce: enforce));
  if (wfh != null) await cache.saveWfhDates(wfh);
}
