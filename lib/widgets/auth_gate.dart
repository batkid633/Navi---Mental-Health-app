import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import 'auth_screen.dart';
import '../main.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService();
  final DataService _dataService = DataService();

  @override
  void initState() {
    super.initState();
    // Set user ID for local user
    _dataService.setUserId(_authService.currentUserId!);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data == true) {
          return NaviHome(dataService: _dataService, authService: _authService);
        }

        return AuthScreen(authService: _authService);
      },
    );
  }
}