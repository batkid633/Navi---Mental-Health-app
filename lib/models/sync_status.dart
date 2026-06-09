class SyncStatus {
  static const synced = 'synced';
  static const pending = 'pending';
  static const failed = 'failed';

  static bool canRetry(String value) {
    return value == pending || value == failed;
  }
}
