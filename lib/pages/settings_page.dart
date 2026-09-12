import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/cloud_persistence_service.dart';
import '../services/data_service.dart';
import '../services/health_tracker_service.dart';
import '../services/navi_beacon_ble_service.dart';
import '../services/notification_service.dart';
import '../utils/data_export_saver.dart';
import 'legal_documents_page.dart';
import '../widgets/crisis_resources_card.dart';

class SettingsPage extends StatefulWidget {
  final DataService? dataService;
  final AuthService? authService;
  final Future<void> Function()? onSignOut;

  const SettingsPage({
    super.key,
    this.dataService,
    this.authService,
    this.onSignOut,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _researchDataSharingEnabled = false;
  bool _cloudSyncEnabled = true;
  bool _personalizedInsightsEnabled = true;
  bool _keyboardTrackingEnabled = false;
  bool _checkInNotificationsEnabled = false;
  int _checkInNotificationTimeMinutes = 20 * 60;
  bool _isLoading = false;
  bool _isExporting = false;
  bool _isManagingRecovery = false;
  bool _isDeletingAccount = false;
  bool _isCheckingBackend = false;
  bool _isCheckingCloudJournal = false;
  bool _isSyncingNotifications = false;
  bool _isUploadingResearchPacket = false;
  final Map<HealthTrackerProvider, HealthTrackerStatus> _trackerStatuses = {};
  final Map<HealthTrackerProvider, String> _trackerRedirectUris = {};
  final Map<HealthTrackerProvider, String> _trackerAuthUrls = {};
  HealthTrackerProvider? _connectingTracker;
  HealthTrackerProvider? _syncingTracker;
  final NaviBeaconBleService _beaconBleService = NaviBeaconBleService();
  final List<NaviBeaconDevice> _beaconDevices = [];
  StreamSubscription<NaviBeaconDevice>? _beaconScanSubscription;
  StreamSubscription<NaviBeaconConnectionState>? _beaconStateSubscription;
  NaviBeaconConnectionState _beaconConnectionState =
      NaviBeaconConnectionState.disconnected;
  NaviBeaconDevice? _selectedBeaconDevice;
  int _beaconSamplesSaved = 0;
  String? _lastBeaconSampleLabel;
  String? _statusMessage;
  _BackendHealth? _backendHealth;
  CloudJournalInventory? _cloudJournalInventory;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _beaconScanSubscription?.cancel();
    _beaconStateSubscription?.cancel();
    _beaconBleService.disconnect();
    super.dispose();
  }

  void _listenForBeaconState() {
    _beaconStateSubscription ??= _beaconBleService.connectionState.listen((
      state,
    ) {
      if (!mounted) return;
      setState(() {
        _beaconConnectionState = state;
      });
    });
  }

  Future<void> _scanForBeacon() async {
    if (!_beaconBleService.isSupported) {
      setState(() {
        _statusMessage = 'Navi Beacon BLE is only supported on mobile/desktop.';
      });
      return;
    }
    _listenForBeaconState();
    await _beaconScanSubscription?.cancel();
    setState(() {
      _beaconDevices.clear();
      _selectedBeaconDevice = null;
      _statusMessage = null;
    });
    await AnalyticsService.track('navi_beacon_scan_started');
    _beaconScanSubscription = _beaconBleService.scan().listen(
      (device) {
        if (!mounted) return;
        setState(() {
          final existingIndex = _beaconDevices.indexWhere(
            (existing) => existing.id == device.id,
          );
          if (existingIndex == -1) {
            _beaconDevices.add(device);
          } else {
            _beaconDevices[existingIndex] = device;
          }
          _selectedBeaconDevice ??= device;
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _statusMessage = 'Unable to scan for Navi Beacon: $error';
        });
      },
    );
  }

  Future<void> _connectBeacon(NaviBeaconDevice device) async {
    final dataService = widget.dataService;
    if (dataService == null) {
      setState(() {
        _statusMessage = 'Sign in before connecting Navi Beacon.';
      });
      return;
    }
    _listenForBeaconState();
    setState(() {
      _selectedBeaconDevice = device;
      _statusMessage = null;
    });
    await AnalyticsService.track('navi_beacon_connect_attempted');
    try {
      await _beaconBleService.connectAndListen(
        device.id,
        onSample: (sample) async {
          await dataService.saveNaviBeaconSample(sample);
          if (!mounted) return;
          setState(() {
            _beaconSamplesSaved += 1;
            _lastBeaconSampleLabel =
                'HR ${sample.heartRate ?? '-'} bpm, ${sample.activity}, '
                '${sample.lux?.toStringAsFixed(0) ?? '-'} lux';
          });
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Unable to connect Navi Beacon: $error';
      });
    }
  }

  Future<void> _disconnectBeacon() async {
    await _beaconBleService.disconnect();
    if (!mounted) return;
    setState(() {
      _statusMessage = 'Navi Beacon disconnected.';
    });
  }

  Future<void> _loadSettings() async {
    await SettingsService.init();
    setState(() {
      _researchDataSharingEnabled = SettingsService.researchDataSharingEnabled;
      _cloudSyncEnabled = SettingsService.cloudSyncEnabled;
      _personalizedInsightsEnabled =
          SettingsService.personalizedInsightsEnabled;
      _keyboardTrackingEnabled = SettingsService.keyboardTrackingEnabled;
      _checkInNotificationsEnabled =
          SettingsService.checkInNotificationsEnabled;
      _checkInNotificationTimeMinutes =
          SettingsService.checkInNotificationTimeMinutes;
      _statusMessage = null;
    });
    await _refreshTrackerStatuses();
    await _checkBackendHealth();
    await _checkCloudJournalInventory();
  }

  Future<void> _checkCloudJournalInventory() async {
    final dataService = widget.dataService;
    if (dataService == null || !SettingsService.cloudSyncEnabled) {
      if (mounted) {
        setState(() {
          _cloudJournalInventory = null;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _isCheckingCloudJournal = true;
      });
    }
    try {
      final inventory = await dataService.cloudJournalInventory();
      if (mounted) {
        setState(() {
          _cloudJournalInventory = inventory;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cloudJournalInventory = null;
          _statusMessage = 'Unable to read cloud journal status: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingCloudJournal = false;
        });
      }
    }
  }

  Future<void> _checkBackendHealth() async {
    if (mounted) {
      setState(() {
        _isCheckingBackend = true;
      });
    }

    final started = DateTime.now();
    try {
      final response = await http
          .get(Uri.parse('${BackendConfig.baseUrl}/health'))
          .timeout(const Duration(seconds: 5));
      final latency = DateTime.now().difference(started);
      final body = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};
      if (!mounted) return;
      await AnalyticsService.track(
        'backend_health_checked',
        properties: {
          'connected': response.statusCode >= 200 && response.statusCode < 300,
          'status_code': response.statusCode,
          'latency_ms': latency.inMilliseconds,
        },
      );
      setState(() {
        _backendHealth = _BackendHealth(
          connected: response.statusCode >= 200 && response.statusCode < 300,
          statusCode: response.statusCode,
          latency: latency,
          service: body['service']?.toString(),
          version: body['version']?.toString(),
          environment: body['environment']?.toString(),
          message: body['status']?.toString(),
        );
      });
    } catch (error) {
      await AnalyticsService.track(
        'backend_health_checked',
        properties: {'connected': false},
      );
      if (!mounted) return;
      setState(() {
        _backendHealth = _BackendHealth(
          connected: false,
          message: error.toString(),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingBackend = false;
        });
      }
    }
  }

  Future<void> _refreshTrackerStatuses() async {
    for (final provider in HealthTrackerProvider.values) {
      await _refreshTrackerStatus(provider);
    }
  }

  Future<void> _refreshTrackerStatus(HealthTrackerProvider provider) async {
    try {
      final status = await HealthTrackerService.getStatus(provider);
      if (!mounted) return;
      setState(() {
        _trackerStatuses[provider] = status;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _trackerStatuses[provider] = HealthTrackerStatus(
          connected: false,
          error: error.toString(),
        );
      });
    }
  }

  Future<void> _openTrackerConnection(HealthTrackerProvider provider) async {
    setState(() {
      _isLoading = true;
      _connectingTracker = provider;
      _statusMessage = null;
      _trackerRedirectUris.remove(provider);
      _trackerAuthUrls.remove(provider);
    });

    try {
      await AnalyticsService.track(
        'health_tracker_connect_attempted',
        properties: {'provider': provider.id},
      );
      final info = await HealthTrackerService.launchConnectUrl(provider);
      await AnalyticsService.track(
        'health_tracker_connect_url_opened',
        properties: {'provider': provider.id},
      );
      setState(() {
        _trackerRedirectUris[provider] = info.redirectUri;
        _trackerAuthUrls[provider] = info.authUrl;
        _statusMessage =
            '${provider.label} auth opened in browser. Complete auth flow there.';
      });
    } catch (error) {
      await AnalyticsService.track(
        'health_tracker_connect_failed',
        properties: {'provider': provider.id},
      );
      setState(() {
        _statusMessage = 'Unable to open ${provider.label} login: $error';
      });
    } finally {
      setState(() {
        _isLoading = false;
        _connectingTracker = null;
      });
    }
  }

  Future<void> _syncTrackerMetrics(HealthTrackerProvider provider) async {
    setState(() {
      _isLoading = true;
      _syncingTracker = provider;
      _statusMessage = null;
    });

    try {
      await AnalyticsService.track(
        'health_tracker_sync_attempted',
        properties: {'provider': provider.id},
      );
      final result = await HealthTrackerService.syncDailyMetrics(provider);
      await AnalyticsService.track(
        'health_tracker_sync_completed',
        properties: {
          'provider': provider.id,
          'requested_days': result.requestedDays,
          'fetched': result.fetched,
          'saved': result.saved,
        },
      );
      if (!mounted) return;
      setState(() {
        _statusMessage = result.connected
            ? '${provider.label} synced ${result.saved} biometric days.'
            : result.detail ?? '${provider.label} is not connected.';
      });
      await _refreshTrackerStatus(provider);
    } catch (error) {
      await AnalyticsService.track(
        'health_tracker_sync_failed',
        properties: {'provider': provider.id},
      );
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Unable to sync ${provider.label}: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _syncingTracker = null;
        });
      }
    }
  }

  Future<void> _pickCheckInNotificationTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _checkInNotificationTimeMinutes ~/ 60,
        minute: _checkInNotificationTimeMinutes % 60,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _checkInNotificationTimeMinutes = picked.hour * 60 + picked.minute;
    });
    await _saveNotificationSettings(
      successMessage:
          'Check-in notification time set to ${_formatCheckInNotificationTime()}.',
    );
  }

  String _formatCheckInNotificationTime() {
    final time = TimeOfDay(
      hour: _checkInNotificationTimeMinutes ~/ 60,
      minute: _checkInNotificationTimeMinutes % 60,
    );
    return time.format(context);
  }

  Future<NotificationRegistrationResult> _saveNotificationSettings({
    String successMessage = 'Notification settings saved.',
  }) async {
    await SettingsService.saveCheckInNotificationSettings(
      enabled: _checkInNotificationsEnabled,
      timeMinutes: _checkInNotificationTimeMinutes,
    );
    late final NotificationRegistrationResult result;
    try {
      result = await NotificationService.instance.configureForUser(
        widget.authService?.currentUserId,
      );
    } catch (error) {
      if (!NotificationService.instance.usesLocalReminders) rethrow;
      if (mounted) {
        setState(() {
          _statusMessage = 'Unable to apply the reminder. Please try again.';
        });
      }
      return const NotificationRegistrationResult(
        supported: true,
        enabled: false,
        permissionGranted: false,
        permissionStatus: 'schedule_error',
      );
    }
    if (!mounted) {
      return result;
    }
    setState(() {
      if (!result.supported) {
        _statusMessage = 'Notifications are not supported on this platform.';
      } else if (_checkInNotificationsEnabled &&
          result.permissionStatus == 'signed_out') {
        _statusMessage = 'Sign in to enable your daily check-in reminder.';
      } else if (_checkInNotificationsEnabled && !result.permissionGranted) {
        _statusMessage = NotificationService.instance.usesLocalReminders
            ? 'Allow notifications in iPhone Settings > Notifications > Navi Personal, then apply your reminder settings again.'
            : 'Notification settings saved. Permission was not granted on this device.';
      } else if (_checkInNotificationsEnabled && !result.enabled) {
        _statusMessage = 'The reminder was not scheduled. Please try again.';
      } else {
        _statusMessage = successMessage;
      }
    });
    return result;
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      await SettingsService.saveResearchDataSharingEnabled(
        _researchDataSharingEnabled,
      );
      await SettingsService.saveCloudSyncEnabled(_cloudSyncEnabled);
      await SettingsService.savePersonalizedInsightsEnabled(
        _personalizedInsightsEnabled,
      );
      await SettingsService.saveKeyboardTrackingEnabled(
        _keyboardTrackingEnabled,
      );
      await widget.dataService?.syncPrivacyConsentToCloud();
      final notificationResult = await _saveNotificationSettings(
        successMessage: 'Settings saved',
      );
      await AnalyticsService.track(
        'settings_saved',
        properties: {
          'cloud_sync': _cloudSyncEnabled,
          'personalized_insights': _personalizedInsightsEnabled,
          'keyboard_tracking': _keyboardTrackingEnabled,
          'research_data_sharing': _researchDataSharingEnabled,
          'check_in_notifications': _checkInNotificationsEnabled,
          'notification_permission': notificationResult.permissionStatus,
        },
      );
      await _checkBackendHealth();
    } catch (error) {
      await AnalyticsService.track('settings_save_failed');
      setState(() {
        _statusMessage = 'Unable to save settings: $error';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _exportMyData() async {
    final dataService = widget.dataService;
    if (dataService == null) return;
    setState(() {
      _isExporting = true;
      _statusMessage = null;
    });

    try {
      await AnalyticsService.track('data_export_requested');
      final exportJson = await dataService.exportMyDataJson();
      final savedPath = await saveDataExport(exportJson);
      await Clipboard.setData(ClipboardData(text: exportJson));
      if (!mounted) return;
      setState(() {
        _statusMessage = savedPath == null
            ? 'Data export copied to clipboard.'
            : 'Data export saved to $savedPath and copied to clipboard.';
      });
      await AnalyticsService.track('data_export_succeeded');
      await _showExportPreview(exportJson);
    } catch (error) {
      await AnalyticsService.track('data_export_failed');
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Unable to export data: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _showExportPreview(String exportJson) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your data export'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              exportJson,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadResearchPacket() async {
    final dataService = widget.dataService;
    if (dataService == null) return;
    if (!_researchDataSharingEnabled) {
      setState(() {
        _statusMessage =
            'Turn on research/data-sharing before uploading a research packet.';
      });
      return;
    }

    setState(() {
      _isUploadingResearchPacket = true;
      _statusMessage = null;
    });

    try {
      await SettingsService.saveResearchDataSharingEnabled(true);
      await dataService.syncPrivacyConsentToCloud();
      final result = await dataService.uploadResearchPacketToGcs();
      final uploaded = result['uploaded'] == true;
      final skipped = result['skipped'] == true;
      final reason = result['reason']?.toString();
      final recordCount = result['record_count']?.toString();
      await AnalyticsService.track(
        'research_packet_upload_requested',
        properties: {
          'uploaded': uploaded,
          'skipped': skipped,
          'reason': reason ?? '',
        },
      );
      if (!mounted) return;
      setState(() {
        if (uploaded) {
          _statusMessage =
              'Research packet uploaded${recordCount == null ? '' : ' ($recordCount records)'}.';
        } else if (reason == 'no_research_records') {
          _statusMessage =
              'No research packet was uploaded because there is not enough insight data yet.';
        } else if (skipped &&
            reason == 'research_packet_bucket_not_configured') {
          _statusMessage =
              'Research packet was prepared, but the cloud bucket is not configured yet.';
        } else {
          _statusMessage =
              'Research packet was not uploaded${reason == null ? '' : ': $reason'}.';
        }
      });
    } catch (error) {
      await AnalyticsService.track('research_packet_upload_failed');
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Unable to upload research packet: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingResearchPacket = false;
        });
      }
    }
  }

  Future<void> _exportEncryptionRecoveryKit() async {
    final dataService = widget.dataService;
    if (dataService == null) return;

    final passphrase = await _promptRecoveryPassphrase(
      title: 'Create recovery kit',
      actionLabel: 'Create',
      requireConfirmation: true,
    );
    if (passphrase == null) return;

    setState(() {
      _isManagingRecovery = true;
      _statusMessage = null;
    });

    try {
      final recoveryKit = await dataService.exportEncryptionRecoveryKit(
        passphrase,
      );
      await Clipboard.setData(ClipboardData(text: recoveryKit));
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Encrypted recovery kit copied to clipboard.';
      });
      await AnalyticsService.track('encryption_recovery_exported');
      await _showRecoveryKitPreview(recoveryKit);
    } catch (error) {
      await AnalyticsService.track('encryption_recovery_export_failed');
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Unable to create recovery kit: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isManagingRecovery = false;
        });
      }
    }
  }

  Future<void> _importEncryptionRecoveryKit() async {
    final dataService = widget.dataService;
    if (dataService == null) return;

    final import = await _promptRecoveryImport();
    if (import == null) return;

    setState(() {
      _isManagingRecovery = true;
      _statusMessage = null;
    });

    try {
      final beforeInventory = await dataService.cloudJournalInventory(
        forceCloudRead: true,
      );
      await dataService.importEncryptionRecoveryKit(
        import.passphrase,
        import.recoveryKit,
      );
      final loadResult = await dataService.loadFromCloud(forceCloudRead: true);
      final afterInventory = await dataService.cloudJournalInventory(
        forceCloudRead: true,
      );
      await AnalyticsService.track('encryption_recovery_imported');
      if (!mounted) return;
      setState(() {
        _cloudJournalInventory = afterInventory;
        _statusMessage = _recoveryImportMessage(
          loadResult,
          beforeInventory,
          afterInventory,
        );
      });
    } catch (error) {
      await AnalyticsService.track('encryption_recovery_import_failed');
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Unable to import recovery kit: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isManagingRecovery = false;
        });
      }
    }
  }

  Future<String?> _promptRecoveryPassphrase({
    required String title,
    required String actionLabel,
    bool requireConfirmation = false,
  }) {
    final passphraseController = TextEditingController();
    final confirmationController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passphraseController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Recovery passphrase',
                helperText: 'Use at least 12 characters.',
              ),
            ),
            if (requireConfirmation) ...[
              const SizedBox(height: 12),
              TextField(
                controller: confirmationController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm passphrase',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final passphrase = passphraseController.text.trim();
              if (passphrase.length < 12) {
                return;
              }
              if (requireConfirmation &&
                  passphrase != confirmationController.text.trim()) {
                return;
              }
              Navigator.of(context).pop(passphrase);
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  String _recoveryImportMessage(
    CloudLoadResult loadResult,
    CloudJournalInventory? beforeInventory,
    CloudJournalInventory? afterInventory,
  ) {
    final beforeLocked = beforeInventory?.lockedCount;
    final afterLocked = afterInventory?.lockedCount;
    final afterDecryptable = afterInventory?.decryptableCount;
    final total = afterInventory?.totalCount;

    if (total == 0) {
      return 'Recovery kit imported, but no cloud journal documents were found for this account.';
    }

    if (afterLocked != null && afterLocked > 0) {
      final changed = beforeLocked != null && beforeLocked != afterLocked
          ? 'locked journal docs changed from $beforeLocked to $afterLocked'
          : '$afterLocked journal docs still need a different recovery kit';
      return 'Recovery kit imported, but $changed. Decryptable here: ${afterDecryptable ?? 0}/${total ?? 0}.';
    }

    if (loadResult.journalLoaded == 0) {
      return 'Recovery kit imported and cloud journal is decryptable, but no new journal entries were added locally. Local journal count: ${loadResult.afterJournalCount}.';
    }

    return 'Recovery kit imported. Loaded ${loadResult.journalLoaded} cloud journal entries; local journal count is now ${loadResult.afterJournalCount}.';
  }

  Future<_RecoveryImport?> _promptRecoveryImport() {
    final kitController = TextEditingController();
    final passphraseController = TextEditingController();
    return showDialog<_RecoveryImport>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore recovery kit'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passphraseController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Recovery passphrase',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: kitController,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Recovery kit JSON',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final passphrase = passphraseController.text.trim();
              final recoveryKit = kitController.text.trim();
              if (passphrase.length < 12 || recoveryKit.isEmpty) {
                return;
              }
              Navigator.of(context).pop(
                _RecoveryImport(
                  passphrase: passphrase,
                  recoveryKit: recoveryKit,
                ),
              );
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRecoveryKitPreview(String recoveryKit) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encrypted recovery kit'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              recoveryKit,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account and data?'),
        content: const Text(
          'This deletes local journal/audio records, synced Firestore data, Storage audio files, backend runtime data, and then your Firebase account. You may need to sign in again first if Firebase requires recent authentication.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AnalyticsService.track('account_delete_confirmed');
      await _deleteAccountAndData();
    } else {
      await AnalyticsService.track('account_delete_cancelled');
    }
  }

  Future<void> _deleteAccountAndData() async {
    final dataService = widget.dataService;
    if (dataService == null) return;
    setState(() {
      _isDeletingAccount = true;
      _statusMessage = null;
    });

    try {
      await AnalyticsService.track('account_delete_started');
      await dataService.deleteMyData();
      await widget.authService?.deleteCurrentAccount();
      if (widget.onSignOut != null) {
        await widget.onSignOut!();
      }
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Account and data deleted.';
      });
    } catch (error) {
      await AnalyticsService.track('account_delete_failed');
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Data delete ran, but account deletion needs attention: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingAccount = false;
        });
      }
    }
  }

  Future<void> _showPrivacyReview() {
    final rows = [
      _PrivacyRow('Consent completed', SettingsService.consentCompleted),
      _PrivacyRow('Health data consent', SettingsService.healthDataConsent),
      _PrivacyRow(
        'Privacy policy accepted',
        SettingsService.privacyPolicyAccepted,
      ),
      _PrivacyRow(
        'Not emergency care acknowledged',
        SettingsService.notEmergencyCareAcknowledged,
      ),
      _PrivacyRow('Cloud sync', _cloudSyncEnabled),
      _PrivacyRow('Personalized insights', _personalizedInsightsEnabled),
      _PrivacyRow('In-app typing rhythm', _keyboardTrackingEnabled),
      _PrivacyRow('Research/data-sharing', _researchDataSharingEnabled),
    ];

    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy settings review'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in rows)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  row.enabled ? Icons.check_circle : Icons.cancel,
                  color: row.enabled ? Colors.green : Colors.orange,
                ),
                title: Text(row.label),
                trailing: Text(row.enabled ? 'On' : 'Off'),
              ),
            const Divider(),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Consent version'),
              subtitle: Text(
                SettingsService.consentVersion.isEmpty
                    ? SettingsService.currentConsentVersion
                    : SettingsService.consentVersion,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _backendConnectivityCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final health = _backendHealth;
    final connected = health?.connected == true;
    final title = _isCheckingBackend
        ? 'Checking backend...'
        : connected
        ? 'Backend reachable'
        : 'Backend not reachable';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _isCheckingBackend
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        connected ? Icons.cloud_done : Icons.cloud_off,
                        color: connected
                            ? Colors.green.shade600
                            : colorScheme.error,
                      ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Check backend',
                  onPressed: _isCheckingBackend ? null : _checkBackendHealth,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Effective backend URL'),
            const SizedBox(height: 6),
            SelectableText(
              SettingsService.effectiveBaseUrl,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (health != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    label: 'Status',
                    value: health.statusCode?.toString() ?? 'No response',
                  ),
                  if (health.latency != null)
                    _InfoChip(
                      label: 'Latency',
                      value: '${health.latency!.inMilliseconds} ms',
                    ),
                  if (health.version != null)
                    _InfoChip(label: 'Version', value: health.version!),
                  if (health.service != null)
                    _InfoChip(label: 'Service', value: health.service!),
                  if (health.environment != null)
                    _InfoChip(label: 'Environment', value: health.environment!),
                ],
              ),
              if (!connected && health.message != null) ...[
                const SizedBox(height: 10),
                Text(
                  health.message!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colorScheme.error, fontSize: 12),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _cloudJournalCard() {
    final inventory = _cloudJournalInventory;
    final lockedCount = inventory?.lockedCount ?? 0;
    final hasLockedEntries = lockedCount > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _isCheckingCloudJournal
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        hasLockedEntries ? Icons.lock : Icons.cloud_done,
                        color: hasLockedEntries
                            ? Colors.orange.shade700
                            : Colors.green.shade600,
                      ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Cloud journal status',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Check cloud journal',
                  onPressed: _isCheckingCloudJournal
                      ? null
                      : _checkCloudJournalInventory,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              'User: ${widget.authService?.currentUserId ?? 'not signed in'}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (inventory == null)
              const Text('No cloud journal status loaded.')
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    label: 'Cloud docs',
                    value: inventory.totalCount.toString(),
                  ),
                  _InfoChip(
                    label: 'Decryptable here',
                    value: inventory.decryptableCount.toString(),
                  ),
                  _InfoChip(
                    label: 'Needs recovery kit',
                    value: lockedCount.toString(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Newest cloud entry: ${_formatCloudDate(inventory.newestDate)}',
              ),
              Text(
                'Newest readable entry: ${_formatCloudDate(inventory.newestDecryptableDate)}',
              ),
              if (hasLockedEntries) ...[
                const SizedBox(height: 10),
                Text(
                  'Some encrypted entries were found in cloud but cannot be opened with this browser key. Restore your recovery kit to unlock them.',
                  style: TextStyle(color: Colors.orange.shade800),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _formatCloudDate(DateTime? value) {
    if (value == null) {
      return 'none';
    }
    final local = value.toLocal();
    return '${local.month}/${local.day}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _naviBeaconCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final connected =
        _beaconConnectionState == NaviBeaconConnectionState.connected;
    final scanning =
        _beaconConnectionState == NaviBeaconConnectionState.scanning;
    final connecting =
        _beaconConnectionState == NaviBeaconConnectionState.connecting;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.sensors,
                  color: connected
                      ? Colors.green.shade600
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Navi Beacon',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Chip(
                  label: Text(switch (_beaconConnectionState) {
                    NaviBeaconConnectionState.connected => 'Connected',
                    NaviBeaconConnectionState.connecting => 'Connecting',
                    NaviBeaconConnectionState.scanning => 'Scanning',
                    NaviBeaconConnectionState.disconnected => 'Disconnected',
                  }),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (_lastBeaconSampleLabel != null) ...[
              const SizedBox(height: 8),
              Text(_lastBeaconSampleLabel!),
            ],
            if (_beaconSamplesSaved > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Saved $_beaconSamplesSaved samples locally.',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: scanning || connecting ? null : _scanForBeacon,
                  icon: scanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: const Text('Scan'),
                ),
                if (_selectedBeaconDevice != null)
                  FilledButton.icon(
                    onPressed: connected || connecting
                        ? null
                        : () => _connectBeacon(_selectedBeaconDevice!),
                    icon: connecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bluetooth_connected),
                    label: Text(
                      _selectedBeaconDevice!.name.isEmpty
                          ? 'Connect'
                          : 'Connect ${_selectedBeaconDevice!.name}',
                    ),
                  ),
                IconButton(
                  tooltip: 'Disconnect Navi Beacon',
                  onPressed: connected ? _disconnectBeacon : null,
                  icon: const Icon(Icons.bluetooth_disabled),
                ),
              ],
            ),
            if (_beaconDevices.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final device in _beaconDevices)
                ListTile(
                  leading: Icon(
                    _selectedBeaconDevice?.id == device.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  onTap: () {
                    setState(() {
                      _selectedBeaconDevice = device;
                    });
                  },
                  title: Text(
                    device.name.isEmpty ? 'Navi Beacon' : device.name,
                  ),
                  subtitle: Text(
                    device.rssi == null
                        ? device.id
                        : '${device.id} - RSSI ${device.rssi}',
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _healthTrackerCard(HealthTrackerProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = _trackerStatuses[provider];
    final connected = status?.connected == true;
    final setupRequired =
        status?.setupRequired == true || status?.configured == false;
    final isConnecting = _connectingTracker == provider;
    final isSyncing = _syncingTracker == provider;
    final canConnect =
        provider.connectPath != null && !isConnecting && !_isLoading;
    final canSync =
        provider.syncPath != null && connected && !isSyncing && !_isLoading;
    final icon = switch (provider) {
      HealthTrackerProvider.whoop => Icons.fitness_center,
      HealthTrackerProvider.fitbit => Icons.watch,
      HealthTrackerProvider.appleHealth => Icons.favorite,
    };
    final statusColor = connected
        ? Colors.green.shade600
        : setupRequired
        ? Colors.orange.shade700
        : colorScheme.onSurfaceVariant;
    final redirectUri = _trackerRedirectUris[provider];
    final authUrl = _trackerAuthUrls[provider];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: statusColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    provider.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Chip(
                  label: Text(status?.statusLabel ?? 'Loading'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (status?.expiresAt != null) ...[
              const SizedBox(height: 8),
              Text('Expires at: ${status!.expiresAt}'),
            ],
            if (status?.message != null) ...[
              const SizedBox(height: 8),
              Text(status!.message!, style: const TextStyle(fontSize: 12)),
            ],
            if (status?.error != null) ...[
              const SizedBox(height: 8),
              Text(
                status!.error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.error, fontSize: 12),
              ),
            ],
            if (redirectUri != null) ...[
              const SizedBox(height: 8),
              Text(
                'Redirect URI: $redirectUri',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (authUrl != null) ...[
              const SizedBox(height: 8),
              Text(
                'Auth URL: ${authUrl.replaceAll(RegExp(r'&.*'), '&...')}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: canConnect
                      ? () => _openTrackerConnection(provider)
                      : null,
                  icon: isConnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: Text(
                    provider.connectPath == null
                        ? 'Native setup required'
                        : 'Connect ${provider.label}',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (provider.syncPath != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: canSync
                              ? () => _syncTrackerMetrics(provider)
                              : null,
                          icon: isSyncing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.sync),
                          label: const Text('Sync data'),
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh ${provider.label}',
                      onPressed: _isLoading
                          ? null
                          : () => _refreshTrackerStatus(provider),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Privacy, Safety, and Consent',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const CrisisResourcesCard(),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Consent status',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          SettingsService.consentCompleted
                              ? 'Completed ${SettingsService.consentCompletedAt.isEmpty ? '' : 'on ${SettingsService.consentCompletedAt}'}'
                              : 'Not completed',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Consent version: ${SettingsService.consentVersion.isEmpty ? SettingsService.currentConsentVersion : SettingsService.consentVersion}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Privacy policy: ${SettingsService.privacyPolicyVersion.isEmpty ? 'not recorded' : SettingsService.privacyPolicyVersion}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          'Terms: ${SettingsService.termsVersion.isEmpty ? 'not recorded' : SettingsService.termsVersion}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.privacy_tip_outlined),
                      label: const Text('Privacy policy'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LegalDocumentsPage(),
                          ),
                        );
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Terms'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const LegalDocumentsPage(initialTabIndex: 1),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _cloudSyncEnabled,
                  onChanged: (value) {
                    setState(() {
                      _cloudSyncEnabled = value;
                    });
                  },
                  title: const Text('Cloud sync'),
                  subtitle: const Text(
                    'When off, new local journal/audio data will not sync to Firestore or Storage from this device.',
                  ),
                ),
                SwitchListTile(
                  value: _personalizedInsightsEnabled,
                  onChanged: (value) {
                    setState(() {
                      _personalizedInsightsEnabled = value;
                    });
                  },
                  title: const Text('Personalized insights'),
                  subtitle: const Text(
                    'Allow Navi to use your saved data for trends, predictions, and longitudinal insight features.',
                  ),
                ),
                SwitchListTile(
                  value: _checkInNotificationsEnabled,
                  onChanged: (value) async {
                    setState(() {
                      _checkInNotificationsEnabled = value;
                    });
                    await _saveNotificationSettings(
                      successMessage: value
                          ? 'Check-in notifications enabled for ${_formatCheckInNotificationTime()}.'
                          : 'Check-in notifications disabled.',
                    );
                  },
                  title: const Text('Check-in notifications'),
                  subtitle: Text(
                    NotificationService.instance.usesLocalReminders
                        ? 'This iPhone will remind you daily at ${_formatCheckInNotificationTime()}, even when Navi is closed.'
                        : 'Let Navi send a neutral daily check-in prompt around ${_formatCheckInNotificationTime()}.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _checkInNotificationsEnabled
                              ? _pickCheckInNotificationTime
                              : null,
                          icon: const Icon(Icons.schedule),
                          label: Text(_formatCheckInNotificationTime()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Sync notification settings',
                        onPressed: _isSyncingNotifications
                            ? null
                            : () async {
                                setState(() {
                                  _isSyncingNotifications = true;
                                  _statusMessage = null;
                                });
                                try {
                                  await _saveNotificationSettings(
                                    successMessage:
                                        'Notification settings synced.',
                                  );
                                } catch (error) {
                                  setState(() {
                                    _statusMessage =
                                        'Unable to sync notifications: $error';
                                  });
                                } finally {
                                  if (mounted) {
                                    setState(() {
                                      _isSyncingNotifications = false;
                                    });
                                  }
                                }
                              },
                        icon: _isSyncingNotifications
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_sync),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  value: _researchDataSharingEnabled,
                  onChanged: (value) {
                    setState(() {
                      _researchDataSharingEnabled = value;
                    });
                  },
                  title: const Text('Research/data-sharing opt-in'),
                  subtitle: const Text(
                    'Optional. Allows de-identified feature records to be sent for model improvement and potential long-term academic research.',
                  ),
                ),
                if (_researchDataSharingEnabled) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isUploadingResearchPacket
                        ? null
                        : _uploadResearchPacket,
                    icon: _isUploadingResearchPacket
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Upload research packet'),
                  ),
                ],
                SwitchListTile(
                  value: _keyboardTrackingEnabled,
                  onChanged: (value) {
                    setState(() {
                      _keyboardTrackingEnabled = value;
                    });
                  },
                  title: const Text('In-app typing rhythm tracking'),
                  subtitle: const Text(
                    'Optional. Stores aggregate typing cadence, correction, and pause features from Navi text fields. Typed content and individual keys are not stored.',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _showPrivacyReview,
                  icon: const Icon(Icons.privacy_tip_outlined),
                  label: const Text('Review privacy settings'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveSettings,
                  child: const Text('Save privacy settings'),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Data Controls',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _cloudJournalCard(),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: (_isExporting || _isDeletingAccount)
                              ? null
                              : _exportMyData,
                          icon: _isExporting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download),
                          label: const Text('Export my data'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _isManagingRecovery
                              ? null
                              : _exportEncryptionRecoveryKit,
                          icon: _isManagingRecovery
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.key),
                          label: const Text('Copy encryption recovery kit'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _isManagingRecovery
                              ? null
                              : _importEncryptionRecoveryKit,
                          icon: const Icon(Icons.lock_open),
                          label: const Text('Restore recovery kit'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                          ),
                          onPressed: (_isExporting || _isDeletingAccount)
                              ? null
                              : _confirmDeleteAccount,
                          icon: _isDeletingAccount
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.delete_forever),
                          label: const Text('Delete my account and data'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Cloud Backend',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _backendConnectivityCard(),
                const SizedBox(height: 24),
                const Text(
                  'Biometric Trackers',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _naviBeaconCard(),
                const SizedBox(height: 12),
                for (final provider in HealthTrackerProvider.values) ...[
                  _healthTrackerCard(provider),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 16),
                if (_statusMessage != null)
                  Text(_statusMessage!, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BackendHealth {
  final bool connected;
  final int? statusCode;
  final Duration? latency;
  final String? service;
  final String? version;
  final String? environment;
  final String? message;

  const _BackendHealth({
    required this.connected,
    this.statusCode,
    this.latency,
    this.service,
    this.version,
    this.environment,
    this.message,
  });
}

class _PrivacyRow {
  final String label;
  final bool enabled;

  const _PrivacyRow(this.label, this.enabled);
}

class _RecoveryImport {
  final String passphrase;
  final String recoveryKit;

  const _RecoveryImport({required this.passphrase, required this.recoveryKit});
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
    );
  }
}
