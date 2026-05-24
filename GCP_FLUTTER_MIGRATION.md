# Flutter App GCP Migration Guide

## Overview
This guide explains how to update your Flutter Navi app to work with your new GCP infrastructure, including connecting to Cloud Run backend, Firebase Cloud Messaging for push notifications, and proper authentication.

---

## Step 1: Update Backend Endpoints

### 1.1 Create an environment configuration file
Create `lib/config/gcp_config.dart`:

```dart
class GcpConfig {
  // Cloud Run Backend URL
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:8080', // For local development
  );

  // Firebase Project ID
  static const String firebaseProjectId = 'project-bc878e6c-6f53-4f24-88a';

  // Cloud Pub/Sub Topic for push notifications
  static const String pubsubTopic = 'projects/project-bc878e6c-6f53-4f24-88a/topics/push-notifications';

  // API endpoints
  static const String predictMoodEndpoint = '/predict-mood';
  static const String generateInsightEndpoint = '/insight';
  static const String analyzeAudioEndpoint = '/analyze-audio';
  static const String trainModelEndpoint = '/train-model';
  
  // Timeouts (in seconds)
  static const int connectTimeout = 30;
  static const int receiveTimeout = 30;

  // Feature flags
  static const bool enablePushNotifications = true;
  static const bool enableOfflineMode = true;
}
```

### 1.2 Create an API service for Cloud Run
Create `lib/services/gcp_api_service.dart`:

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/gcp_config.dart';

class GcpApiService {
  static final GcpApiService _instance = GcpApiService._internal();

  factory GcpApiService() {
    return _instance;
  }

  GcpApiService._internal();

  final http.Client _httpClient = http.Client();
  String? _authToken;

  /// Set authentication token for Cloud Run
  void setAuthToken(String token) {
    _authToken = token;
  }

  /// Make authenticated request to Cloud Run
  Future<Map<String, dynamic>> _makeRequest(
    String method,
    String endpoint,
    {Map<String, dynamic>? body}
  ) async {
    try {
      final url = Uri.parse('${GcpConfig.backendUrl}$endpoint');
      
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

      http.Response response;

      switch (method) {
        case 'GET':
          response = await _httpClient.get(url, headers: headers)
              .timeout(Duration(seconds: GcpConfig.connectTimeout));
          break;
        
        case 'POST':
          response = await _httpClient.post(
            url,
            headers: headers,
            body: jsonEncode(body),
          ).timeout(Duration(seconds: GcpConfig.connectTimeout));
          break;
        
        case 'PUT':
          response = await _httpClient.put(
            url,
            headers: headers,
            body: jsonEncode(body),
          ).timeout(Duration(seconds: GcpConfig.connectTimeout));
          break;
        
        default:
          throw Exception('Unsupported HTTP method: $method');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        // Handle authentication error
        _authToken = null;
        throw Exception('Authentication failed. Please log in again.');
      } else if (response.statusCode == 429) {
        throw Exception('Too many requests. Please try again later.');
      } else {
        throw Exception(
          'API Error: ${response.statusCode} - ${response.body}'
        );
      }
    } catch (e) {
      print('API Request Error: $e');
      rethrow;
    }
  }

  /// Predict next day mood
  Future<Map<String, dynamic>> predictNextDayMood(Map<String, dynamic> features) async {
    return _makeRequest(
      'POST',
      GcpConfig.predictMoodEndpoint,
      body: features,
    );
  }

  /// Generate insight from data
  Future<Map<String, dynamic>> generateInsight(Map<String, dynamic> data) async {
    return _makeRequest(
      'POST',
      GcpConfig.generateInsightEndpoint,
      body: data,
    );
  }

  /// Analyze audio file
  Future<Map<String, dynamic>> analyzeAudio(String audioPath) async {
    try {
      final url = Uri.parse('${GcpConfig.backendUrl}${GcpConfig.analyzeAudioEndpoint}');
      final request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Bearer $_authToken'
        ..files.add(await http.MultipartFile.fromPath('audio', audioPath));

      final response = await request.send()
          .timeout(Duration(seconds: GcpConfig.receiveTimeout));
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = await response.stream.bytesToString();
        return jsonDecode(responseData);
      } else {
        throw Exception('Audio analysis failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Audio Analysis Error: $e');
      rethrow;
    }
  }

  /// Health check
  Future<bool> healthCheck() async {
    try {
      final response = await _httpClient.get(
        Uri.parse('${GcpConfig.backendUrl}/health'),
      ).timeout(Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
```

---

## Step 2: Update Firebase Configuration

### 2.1 Ensure Firebase initialization with GCP settings
Update `lib/main.dart`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'config/gcp_config.dart';
import 'services/gcp_api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with GCP backend
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Firebase Authentication
  await FirebaseAuth.instance.authStateChanges().listen((User? user) {
    if (user != null) {
      // User is signed in
      user.getIdToken(forceRefresh: true).then((token) {
        GcpApiService().setAuthToken(token);
      });
    }
  }).asFuture();

  // Check backend health
  bool backendHealthy = await GcpApiService().healthCheck();
  if (!backendHealthy && GcpConfig.enableOfflineMode) {
    print('Warning: Backend not available. Using offline mode.');
  }

  runApp(const MyApp());
}
```

---

## Step 3: Set Up Push Notifications with FCM

### 3.1 Update pubspec.yaml for push notifications
Add these dependencies if not already present:

```yaml
dependencies:
  firebase_messaging: ^14.6.0
  firebase_core: ^4.7.0
  firebase_auth: ^6.4.0
```

### 3.2 Create push notification service
Create `lib/services/push_notification_service.dart`:

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

/// Background message handler (must be top-level function)
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling a background message: ${message.messageId}');
  print('Message data: ${message.data}');
  
  // Handle background message - store, log, etc.
  _handleNotificationData(message.data);
}

void _handleNotificationData(Map<String, dynamic> data) {
  // Process notification data
  print('Processing notification: $data');
  // Update local state, trigger actions, etc.
}

class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();

  factory PushNotificationService() {
    return _instance;
  }

  PushNotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  VoidCallback? onNotificationReceived;
  VoidCallback? onNotificationTapped;

  /// Initialize push notifications
  Future<void> initialize() async {
    // Request user permission for notifications
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    print('User granted permission: ${settings.authorizationStatus}');

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      print('Message data: ${message.data}');

      if (message.notification != null) {
        print('Message also contained a notification: ${message.notification}');
        _handleNotificationData(message.data);
        onNotificationReceived?.call();
      }
    });

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Handle notification tapped
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('A new onMessageOpenedApp event was published!');
      _handleNotificationData(message.data);
      onNotificationTapped?.call();
    });

    // Get FCM token for subscription to topics
    String? token = await _firebaseMessaging.getToken();
    print('FCM Token: $token');

    // Subscribe to push notification topic
    await _firebaseMessaging.subscribeToTopic('push-notifications');
    print('Subscribed to push-notifications topic');
  }

  /// Subscribe to custom topic
  Future<void> subscribeToTopic(String topic) async {
    await _firebaseMessaging.subscribeToTopic(topic);
    print('Subscribed to topic: $topic');
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    await _firebaseMessaging.unsubscribeFromTopic(topic);
    print('Unsubscribed from topic: $topic');
  }

  /// Get FCM token
  Future<String?> getFCMToken() async {
    return await _firebaseMessaging.getToken();
  }
}
```

### 3.3 Initialize push notifications in main.dart
```dart
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ... existing Firebase initialization ...

  // Initialize push notifications
  await PushNotificationService().initialize();
  
  // Listen for notifications
  PushNotificationService().onNotificationReceived = () {
    // Handle received notification
    print('Notification received!');
  };

  PushNotificationService().onNotificationTapped = () {
    // Handle tapped notification
    print('Notification tapped!');
  };

  runApp(const MyApp());
}
```

---

## Step 4: Add Health Check & Offline Support

### 4.1 Create offline service
Create `lib/services/offline_service.dart`:

```dart
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

class OfflineService {
  static final OfflineService _instance = OfflineService._internal();
  late Box<Map> _offlineQueue;

  factory OfflineService() {
    return _instance;
  }

  OfflineService._internal();

  /// Initialize offline storage
  Future<void> initialize() async {
    await Hive.initFlutter();
    _offlineQueue = await Hive.openBox<Map>('offline_queue');
  }

  /// Queue request for later sync when online
  Future<void> queueRequest({
    required String endpoint,
    required String method,
    required Map<String, dynamic> data,
  }) async {
    final request = {
      'id': const Uuid().v4(),
      'endpoint': endpoint,
      'method': method,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    await _offlineQueue.add(request);
    print('Request queued for sync: ${request['id']}');
  }

  /// Get all queued requests
  Future<List<Map>> getQueuedRequests() async {
    return _offlineQueue.values.toList().cast<Map>();
  }

  /// Remove request from queue after successful sync
  Future<void> removeQueuedRequest(String requestId) async {
    final requests = _offlineQueue.values.toList();
    for (int i = 0; i < requests.length; i++) {
      if (requests[i]['id'] == requestId) {
        await _offlineQueue.deleteAt(i);
        break;
      }
    }
  }

  /// Clear all queued requests
  Future<void> clearQueue() async {
    await _offlineQueue.clear();
  }
}
```

### 4.2 Add connectivity check
Create `lib/utils/connectivity_helper.dart`:

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityHelper {
  static final ConnectivityHelper _instance = ConnectivityHelper._internal();
  final Connectivity _connectivity = Connectivity();

  factory ConnectivityHelper() {
    return _instance;
  }

  ConnectivityHelper._internal();

  Future<bool> isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Stream<bool> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged
        .map((result) => result != ConnectivityResult.none);
  }
}
```

---

## Step 5: Update pubspec.yaml

Add these dependencies for GCP integration:

```yaml
dependencies:
  # Existing dependencies
  flutter:
    sdk: flutter
  
  # GCP & Firebase
  firebase_core: ^4.7.0
  firebase_auth: ^6.4.0
  firebase_messaging: ^14.6.0
  google_sign_in: ^6.3.0
  
  # API & Networking
  http: ^1.1.0
  
  # Local Storage & Offline
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  
  # Connectivity
  connectivity_plus: ^6.0.0
  
  # Utilities
  uuid: ^3.0.7
  dotenv: ^4.1.0  # For managing environment variables

dev_dependencies:
  flutter_test:
    sdk: flutter
  # ... other dev dependencies
```

---

## Step 6: Environment Configuration

### 6.1 Create environment files

**`.env.production`:**
```
BACKEND_URL=https://navi-backend-xyz123-uc.a.run.app
ENVIRONMENT=production
```

**`.env.development`:**
```
BACKEND_URL=http://localhost:8080
ENVIRONMENT=development
```

### 6.2 Load environment variables in main.dart
```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  String env = const String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );
  await dotenv.load(fileName: '.env.$env');

  // ... rest of initialization ...
}
```

---

## Step 7: Testing & Deployment

### 7.1 Test Cloud Run backend locally
```bash
# Terminal 1: Start your local backend
cd backend
python -m uvicorn app:main --reload --host 0.0.0.0 --port 8080

# Terminal 2: Run Flutter app
flutter run --dart-define=APP_ENV=development
```

### 7.2 Update for production build
```bash
# Build for Android
flutter build apk --dart-define=APP_ENV=production

# Build for iOS
flutter build ios --dart-define=APP_ENV=production

# Build for web
flutter build web --dart-define=APP_ENV=production

# Build for Windows
flutter build windows --dart-define=APP_ENV=production
```

---

## Step 8: Authentication Flow

### 8.1 Secure authentication with GCP
```dart
class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final GcpApiService _apiService = GcpApiService();

  /// Sign in with Google (uses Firebase + GCP)
  Future<UserCredential> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      final GoogleSignInAuthentication? googleAuth = await googleUser?.authentication;
      
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth?.accessToken,
        idToken: googleAuth?.idToken,
      );

      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      
      // Get ID token and set on API service for Cloud Run auth
      String? token = await userCredential.user?.getIdToken();
      if (token != null) {
        _apiService.setAuthToken(token);
      }

      return userCredential;
    } catch (e) {
      print('Google sign-in error: $e');
      rethrow;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _firebaseAuth.signOut();
  }
}
```

---

## Deployment Checklist

- [ ] Update all API endpoints to Cloud Run URL
- [ ] Configure Firebase Cloud Messaging
- [ ] Test push notifications on device
- [ ] Update environment variables for production
- [ ] Test offline mode functionality
- [ ] Verify authentication flow with GCP
- [ ] Test audio upload to Cloud Storage
- [ ] Verify Cloud SQL connection
- [ ] Test mood prediction with new backend
- [ ] Monitor Cloud Run logs during testing
- [ ] Set up monitoring alerts
- [ ] Complete security review

---

## Troubleshooting

### Backend connection failed
```dart
// Check backend health
bool healthy = await GcpApiService().healthCheck();
if (!healthy) {
  print('Backend is not reachable');
  // Activate offline mode
}
```

### Authentication errors
```dart
// Refresh token
User? user = FirebaseAuth.instance.currentUser;
if (user != null) {
  String? newToken = await user.getIdToken(forceRefresh: true);
  GcpApiService().setAuthToken(newToken!);
}
```

### Push notifications not working
```dart
// Check FCM token
String? token = await PushNotificationService().getFCMToken();
print('FCM Token: $token');

// Verify Cloud Pub/Sub subscription
// Check GCP console for topic subscriptions
```

---

## Next Steps

1. Deploy backend to Cloud Run (see **GCP_SETUP.md**)
2. Configure push notifications (see **GCP_PUSH_NOTIFICATIONS.md**)
3. Monitor application metrics in Cloud Logging
4. Set up automated deployments with Cloud Build

---

Generated: May 13, 2026
