// Temporarily disabled Firebase auth due to Windows compilation issues
// Using local-only authentication for now

class AuthService {
  // Mock user for testing - always "signed in"
  bool get isSignedIn => true;

  // Get current user - return a mock user ID
  String? get currentUserId => 'local_user_001';

  // Stream of auth state changes - always signed in
  Stream<bool> get authStateChanges => Stream.value(true);

  // Sign in - mock implementation
  Future<bool> signIn() async {
    // TODO: Implement local authentication
    return true;
  }

  // Sign out
  Future<void> signOut() async {
    // TODO: Implement sign out
  }
}