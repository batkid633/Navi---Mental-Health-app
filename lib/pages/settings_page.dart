import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../services/whoop_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _backendUrlController = TextEditingController();
  final TextEditingController _wifiIPController = TextEditingController();
  bool _useWiFi = false;
  bool _isLoading = false;
  WhoopStatus? _whoopStatus;
  String? _statusMessage;
  String? _whoopRedirectUri;
  String? _whoopAuthUrl;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    _wifiIPController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    await SettingsService.init();
    setState(() {
      _backendUrlController.text = SettingsService.backendUrl;
      _wifiIPController.text = SettingsService.wiFiIP;
      _useWiFi = SettingsService.useWiFi;
      _statusMessage = null;
    });
    await _refreshWhoopStatus();
  }

  Future<void> _refreshWhoopStatus() async {
    try {
      final status = await WhoopService.getStatus();
      setState(() {
        _whoopStatus = status;
      });
    } catch (error) {
      setState(() {
        _whoopStatus = WhoopStatus(connected: false, error: error.toString());
      });
    }
  }

  Future<void> _openWhoopConnection() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _whoopRedirectUri = null;
      _whoopAuthUrl = null;
    });

    try {
      final info = await WhoopService.launchConnectUrl();
      setState(() {
        _whoopRedirectUri = info.redirectUri;
        _whoopAuthUrl = info.authUrl;
        _statusMessage = 'Whoop auth opened in browser. Complete auth flow there.';
      });
    } catch (error) {
      setState(() {
        _statusMessage = 'Unable to open Whoop login: $error';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      await SettingsService.saveBackendUrl(_backendUrlController.text);
      await SettingsService.saveUseWiFi(_useWiFi);
      await SettingsService.saveWiFiIP(_wifiIPController.text);
      setState(() {
        _statusMessage = 'Settings saved';
      });
    } catch (error) {
      setState(() {
        _statusMessage = 'Unable to save settings: $error';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _retrainModel() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      await WhoopService.retrainModel();
      setState(() {
        _statusMessage = 'Retraining started on backend.';
      });
    } catch (error) {
      setState(() {
        _statusMessage = 'Retrain failed: $error';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final customUrlActive = _backendUrlController.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Backend Configuration',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _backendUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Custom backend URL',
                    hintText: 'http://192.168.1.100:8000',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _useWiFi,
                  onChanged: (value) {
                    setState(() {
                      _useWiFi = value;
                    });
                  },
                  title: const Text('Use WiFi backend'),
                ),
                TextField(
                  controller: _wifiIPController,
                  decoration: const InputDecoration(
                    labelText: 'WiFi backend IP',
                    hintText: '192.168.1.100',
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !customUrlActive,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveSettings,
                  child: const Text('Save backend settings'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'If you are running the app on a phone, do not use 127.0.0.1. Use the computer host IP (for example, 192.168.1.100:8000).\nOn Android emulators, use 10.0.2.2:8000.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Effective backend URL'),
                        const SizedBox(height: 8),
                        Text(
                          SettingsService.effectiveBaseUrl,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (customUrlActive) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Custom backend URL takes precedence over WiFi settings.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Whoop Connection',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _whoopStatus?.statusLabel ?? 'Loading...',
                          style: const TextStyle(fontSize: 16),
                        ),
                        if (_whoopStatus?.expiresAt != null) ...[
                          const SizedBox(height: 8),
                          Text('Expires at: ${_whoopStatus!.expiresAt}'),
                        ],
                        if (_whoopRedirectUri != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Redirect URI: $_whoopRedirectUri',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                        if (_whoopAuthUrl != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Auth URL: ${_whoopAuthUrl!.replaceAll(RegExp(r'&.*'), '&...')}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _openWhoopConnection,
                                child: const Text('Connect to Whoop'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: _isLoading ? null : _refreshWhoopStatus,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Model Control',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _retrainModel,
                  child: const Text('Retrain mood model'),
                ),
                const SizedBox(height: 16),
                if (_statusMessage != null)
                  Text(
                    _statusMessage!,
                    style: const TextStyle(fontSize: 14),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
