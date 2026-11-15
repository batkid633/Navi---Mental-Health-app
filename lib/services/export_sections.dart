/// Preserve successful sections when another source is unavailable.
/// Error messages deliberately omit record contents and credential details.
Future<Map<String, dynamic>> collectExportSections(
  Map<String, Future<dynamic> Function()> loaders,
) async {
  final data = <String, dynamic>{};
  final errors = <String, String>{};
  for (final entry in loaders.entries) {
    try {
      data[entry.key] = await entry.value().timeout(
        const Duration(seconds: 30),
      );
    } catch (_) {
      errors[entry.key] = 'unavailable_or_unreadable';
    }
  }
  return {'data': data, 'errors': errors, 'complete': errors.isEmpty};
}
