/// Wait for consented input sync before requesting an insight. Failure must not
/// present a cached response as refreshed from the newly saved input.
Future<T?> refreshToday<T>({
  required bool Function() enabled,
  required bool Function() sharingEnabled,
  required Future<bool> Function() syncInputs,
  required Future<T?> Function() load,
}) async {
  if (!enabled()) return null;
  try {
    if (sharingEnabled() && !await syncInputs()) return null;
    if (!enabled()) return null;
    return await load();
  } catch (_) {
    return null;
  }
}
