import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? lastError;

  bool get isSignedIn => _auth.currentUser != null;

  String? get currentUserId => _auth.currentUser?.uid;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  bool get supportsGoogleSignIn {
    return kIsWeb || defaultTargetPlatform != TargetPlatform.windows;
  }

  Future<bool> signInWithGoogle() async {
    lastError = null;
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        try {
          await _auth.signInWithPopup(provider);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'popup-blocked' ||
              e.code == 'popup-closed-by-user' ||
              e.code == 'cancelled-popup-request') {
            await _auth.signInWithRedirect(provider);
          } else {
            rethrow;
          }
        }
      } else {
        final googleSignIn = GoogleSignIn();
        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          return false;
        }
        final googleAuth = await googleUser.authentication;
        final idToken = googleAuth.idToken;
        if (idToken == null) {
          return false;
        }

        final credential = GoogleAuthProvider.credential(idToken: idToken);
        await _auth.signInWithCredential(credential);
      }
      return _auth.currentUser != null;
    } on FirebaseAuthException catch (e) {
      lastError = _formatFirebaseError(e);
      debugPrint('Google sign-in failed: $lastError');
      return false;
    } catch (e) {
      lastError = e.toString();
      debugPrint('Google sign-in failed: $lastError');
      return false;
    }
  }

  Future<bool> signInWithEmail(String email, String password) async {
    lastError = null;
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      return _auth.currentUser != null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        try {
          await _auth.createUserWithEmailAndPassword(
            email: email.trim(),
            password: password.trim(),
          );
          return _auth.currentUser != null;
        } on FirebaseAuthException catch (createError) {
          lastError = _formatFirebaseError(createError);
          debugPrint('Email account creation failed: $lastError');
          return false;
        }
      }
      lastError = _formatFirebaseError(e);
      debugPrint('Email sign-in failed: $lastError');
      return false;
    } catch (e) {
      lastError = e.toString();
      debugPrint('Email sign-in failed: $lastError');
      return false;
    }
  }

  String _formatFirebaseError(FirebaseAuthException e) {
    final message = e.message?.trim();
    if (message == null || message.isEmpty || message == 'Error') {
      return 'Firebase Auth error: ${e.code}';
    }
    return 'Firebase Auth error: ${e.code} - $message';
  }

  Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb) {
      await GoogleSignIn().signOut();
    }
  }

  Future<void> deleteCurrentAccount() async {
    lastError = null;
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      lastError = _formatFirebaseError(e);
      rethrow;
    }
  }
}
