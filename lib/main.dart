import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';
import 'models/journal_entry.dart';
import 'models/audio_entry.dart';
import 'models/evaluation_feedback.dart';
import 'models/keyboard_session_entry.dart';
import 'pages/journal_page.dart';
import 'pages/today_page.dart';
import 'pages/audio_page.dart';
import 'pages/insights_page.dart';
import 'pages/settings_page.dart';
import 'services/auth_service.dart';
import 'services/analytics_service.dart';
import 'services/data_service.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'widgets/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize Hive with the default directory (Documents) to preserve existing data
  await Hive.initFlutter();

  Hive.registerAdapter(JournalEntryAdapter());
  Hive.registerAdapter(AudioEntryAdapter());
  Hive.registerAdapter(EvaluationFeedbackAdapter());
  Hive.registerAdapter(KeyboardSessionEntryAdapter());

  await SettingsService.init();
  await NotificationService.instance.init();
  await AnalyticsService.track('app_started');

  runApp(const NaviApp());
}

class NaviApp extends StatelessWidget {
  final Widget? home;

  const NaviApp({super.key, this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Navi',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: home ?? const AuthGate(),
    );
  }
}

class NaviHome extends StatefulWidget {
  final DataService dataService;
  final AuthService authService;
  final Future<void> Function()? onSignOut;

  const NaviHome({
    super.key,
    required this.dataService,
    required this.authService,
    this.onSignOut,
  });

  @override
  State<NaviHome> createState() => _NaviHomeState();
}

class _NaviHomeState extends State<NaviHome> {
  int _tabIndex = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      TodayPage(dataService: widget.dataService),
      JournalPage(dataService: widget.dataService),
      AudioPage(dataService: widget.dataService),
      InsightsPage(dataService: widget.dataService),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    dataService: widget.dataService,
                    authService: widget.authService,
                    onSignOut: widget.onSignOut,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              if (widget.onSignOut != null) {
                await widget.onSignOut!();
              } else {
                await widget.authService.signOut();
              }
            },
          ),
        ],
      ),
      body: _pages[_tabIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) {
          setState(() => _tabIndex = index);
          AnalyticsService.track('tab_viewed', properties: {'index': index});
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note),
            label: 'Journal',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_none),
            selectedIcon: Icon(Icons.mic),
            label: 'Audio',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Insights',
          ),
        ],
      ),
    );
  }
}
