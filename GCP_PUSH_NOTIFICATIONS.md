# GCP Push Notifications Setup Guide

## Overview
This guide explains how to set up Firebase Cloud Messaging (FCM) with Google Cloud Pub/Sub for real-time push notifications across your Navi mobile app.

---

## Architecture

```
┌─────────────────────────────────────┐
│     Backend (Cloud Run)             │
│   Publishes mood alerts, insights   │
│   and daily notifications           │
└────────────────┬────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────┐
│      Cloud Pub/Sub Topic            │
│   (push-notifications)              │
│   Message queue & distribution      │
└────────────────┬────────────────────┘
                 │
         ┌───────┼───────┐
         ↓       ↓       ↓
    ┌─────┐ ┌─────┐ ┌─────┐
    │FCM  │ │Logs │ │Email│
    │SMS  │ │Push │ │Subs │
    │Push │ │Logs │ │Path │
    └─────┘ └─────┘ └─────┘
         │       │       │
         └───────┼───────┘
                 ↓
   ┌──────────────────────────────┐
   │  Firebase Cloud Messaging    │
   │  (FCM) Delivery Service      │
   └──────────────────────────────┘
         │       │       │       │
    ┌────┴──┬────┴──┬────┴──┬────┴──┐
    ↓       ↓       ↓       ↓       ↓
 Android   iOS  Windows  macOS   Web
   Apps    Apps   Apps   Apps   Apps
```

---

## Step 1: Firebase Cloud Messaging (FCM) Setup

### 1.1 Enable FCM in Firebase Console
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your "project-bc878e6c-6f53-4f24-88a" project
3. Navigate to **Cloud Messaging** tab
4. Verify FCM is enabled (it should be automatically)

### 1.2 Get Server API Key
```bash
# In Firebase Console:
# Project Settings → Service Accounts → Generate new private key
# Save this as backend/credentials/firebase-admin-key.json

# Or via CLI:
gcloud iam service-accounts keys create firebase-key.json \
  --iam-account=firebase-adminsdk@project-bc878e6c-6f53-4f24-88a.iam.gserviceaccount.com
```

### 1.3 Configure FCM for each platform

#### Android
1. Upload SHA-1 certificate fingerprint in Firebase Console:
   ```bash
   # Get SHA-1 from your Android app
   cd android
   ./gradlew signingReport
   ```
2. Add to Firebase Console: Project Settings → Your apps → Android app → SHA certificate fingerprints

#### iOS
1. Upload APNS certificate to Firebase Console
2. Project Settings → Your apps → iOS app → APNS Certificates

#### Web
FCM is automatically configured for web in Firebase Console

#### Windows/macOS
Use Firebase Admin SDK for push notifications

---

## Step 2: Cloud Pub/Sub Setup

### 2.1 Create Pub/Sub topic for notifications
```bash
# Create topic
gcloud pubsub topics create push-notifications

# Create subscription for FCM
gcloud pubsub subscriptions create push-notifications-fcm \
  --topic=push-notifications \
  --push-endpoint=https://fcm.googleapis.com/v1/projects/$PROJECT_ID/messages:send \
  --push-auth-service-account=navi-cloud-run@$PROJECT_ID.iam.gserviceaccount.com

# Create subscription for logging
gcloud pubsub subscriptions create push-notifications-logs \
  --topic=push-notifications \
  --ack-deadline=60

# Create subscription for user preferences
gcloud pubsub subscriptions create push-notifications-prefs \
  --topic=push-notifications
```

### 2.2 Grant permissions
```bash
# Allow Cloud Run to publish to Pub/Sub
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:navi-cloud-run@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/pubsub.publisher"

# Allow Cloud Functions to subscribe (if used)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:navi-cloud-run@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/pubsub.subscriber"
```

---

## Step 3: Backend Integration (Cloud Run)

### 3.1 Update requirements.txt
Add these packages to `backend/requirements.txt`:

```
firebase-admin>=6.0.0
google-cloud-pubsub>=2.0.0
google-cloud-logging>=3.0.0
```

### 3.2 Create notification service
Create `backend/ml/notification_service.py`:

```python
import firebase_admin
from firebase_admin import messaging
from google.cloud import pubsub_v1
from google.cloud import logging as cloud_logging
import json
from datetime import datetime

# Initialize Firebase Admin
if not firebase_admin.get_app():
    firebase_admin.initialize_app()

publisher = pubsub_v1.PublisherClient()
logger = cloud_logging.Client().logger('navi-notifications')
PROJECT_ID = 'navi-personal-gcp'
TOPIC_ID = 'push-notifications'


class NotificationService:
    """Service for sending push notifications via FCM and Pub/Sub"""

    @staticmethod
    def publish_notification(
        notification_type: str,
        title: str,
        body: str,
        data: dict = None,
        user_id: str = None
    ) -> str:
        """
        Publish notification to Pub/Sub topic for distribution
        
        Args:
            notification_type: Type of notification (mood_alert, insight, reminder, etc)
            title: Notification title
            body: Notification body
            data: Additional data payload
            user_id: Target user ID (optional - None sends to all)
        
        Returns:
            Message ID
        """
        try:
            topic_path = publisher.topic_path(PROJECT_ID, TOPIC_ID)
            
            message_data = {
                'type': notification_type,
                'title': title,
                'body': body,
                'timestamp': datetime.utcnow().isoformat(),
                'data': data or {},
                'user_id': user_id
            }

            # Publish to Pub/Sub
            message_id = publisher.publish(
                topic_path,
                json.dumps(message_data).encode('utf-8'),
                notification_type=notification_type,
                user_id=user_id or 'broadcast'
            ).result()

            logger.log_struct({
                'message_id': message_id,
                'notification_type': notification_type,
                'user_id': user_id,
                'status': 'published'
            }, severity='INFO')

            return message_id

        except Exception as e:
            logger.log_struct({
                'error': str(e),
                'notification_type': notification_type,
                'user_id': user_id
            }, severity='ERROR')
            raise

    @staticmethod
    def send_fcm_notification(
        fcm_token: str,
        title: str,
        body: str,
        data: dict = None
    ) -> str:
        """
        Send direct FCM notification to specific user
        
        Args:
            fcm_token: Firebase Cloud Messaging token
            title: Notification title
            body: Notification body
            data: Additional data
        
        Returns:
            Message ID
        """
        try:
            message = messaging.Message(
                notification=messaging.Notification(
                    title=title,
                    body=body
                ),
                data=data or {},
                token=fcm_token
            )

            message_id = messaging.send(message)

            logger.log_struct({
                'message_id': message_id,
                'fcm_token': fcm_token[:20] + '...',  # Log first 20 chars
                'status': 'sent'
            }, severity='INFO')

            return message_id

        except Exception as e:
            logger.log_struct({
                'error': str(e),
                'fcm_token': fcm_token[:20] + '...'
            }, severity='ERROR')
            raise

    @staticmethod
    def send_multicast_notification(
        fcm_tokens: list,
        title: str,
        body: str,
        data: dict = None
    ) -> dict:
        """
        Send notification to multiple users
        
        Args:
            fcm_tokens: List of FCM tokens
            title: Notification title
            body: Notification body
            data: Additional data
        
        Returns:
            Response with success/failure counts
        """
        try:
            message = messaging.MulticastMessage(
                notification=messaging.Notification(
                    title=title,
                    body=body
                ),
                data=data or {},
                tokens=fcm_tokens
            )

            response = messaging.send_multicast(message)

            logger.log_struct({
                'successful': response.successful,
                'failed': response.failed,
                'status': 'multicast_sent'
            }, severity='INFO')

            return {
                'successful': response.successful,
                'failed': response.failed,
                'total': len(fcm_tokens)
            }

        except Exception as e:
            logger.log_struct({
                'error': str(e),
                'recipient_count': len(fcm_tokens)
            }, severity='ERROR')
            raise

    @staticmethod
    def send_topic_notification(
        topic: str,
        title: str,
        body: str,
        data: dict = None
    ) -> str:
        """
        Send notification to all users subscribed to a topic
        
        Args:
            topic: FCM topic name
            title: Notification title
            body: Notification body
            data: Additional data
        
        Returns:
            Message ID
        """
        try:
            message = messaging.Message(
                notification=messaging.Notification(
                    title=title,
                    body=body
                ),
                data=data or {},
                topic=topic
            )

            message_id = messaging.send(message)

            logger.log_struct({
                'message_id': message_id,
                'topic': topic,
                'status': 'sent'
            }, severity='INFO')

            return message_id

        except Exception as e:
            logger.log_struct({
                'error': str(e),
                'topic': topic
            }, severity='ERROR')
            raise


# Notification templates
NOTIFICATION_TEMPLATES = {
    'mood_prediction': {
        'title': 'Your Mood Prediction',
        'body': 'Based on today\'s data, we predict your mood tomorrow will be: {mood}'
    },
    'insight': {
        'title': 'New Insight',
        'body': '{insight}'
    },
    'daily_reminder': {
        'title': 'Daily Check-in',
        'body': 'Time to log your mood and activities'
    },
    'anomaly_alert': {
        'title': 'Unusual Pattern Detected',
        'body': 'We detected an unusual pattern in your data'
    },
    'achievement': {
        'title': 'Achievement Unlocked',
        'body': 'Great job! {achievement}'
    }
}


def send_templated_notification(
    template_name: str,
    user_id: str,
    **kwargs
) -> str:
    """Helper function to send templated notifications"""
    template = NOTIFICATION_TEMPLATES.get(template_name, {})
    
    if not template:
        raise ValueError(f'Unknown template: {template_name}')
    
    title = template['title'].format(**kwargs)
    body = template['body'].format(**kwargs)
    
    return NotificationService.publish_notification(
        notification_type=template_name,
        title=title,
        body=body,
        user_id=user_id,
        data=kwargs
    )
```

### 3.3 Add notification endpoints to app.py
Add to `backend/app.py`:

```python
from ml.notification_service import NotificationService, send_templated_notification
from fastapi import Depends, HTTPException, Header

@app.post("/notify/prediction")
async def notify_mood_prediction(
    user_id: str,
    predicted_mood: str,
    confidence: float = None,
    authorization: str = Header(None)
):
    """Send mood prediction notification"""
    try:
        if not authorization:
            raise HTTPException(status_code=401, detail="Not authenticated")
        
        message_id = send_templated_notification(
            'mood_prediction',
            user_id=user_id,
            mood=predicted_mood
        )
        
        return {
            'status': 'success',
            'message_id': message_id,
            'notification_type': 'mood_prediction'
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/notify/insight")
async def notify_insight(
    user_id: str,
    insight: str,
    authorization: str = Header(None)
):
    """Send insight notification"""
    try:
        if not authorization:
            raise HTTPException(status_code=401, detail="Not authenticated")
        
        message_id = send_templated_notification(
            'insight',
            user_id=user_id,
            insight=insight
        )
        
        return {
            'status': 'success',
            'message_id': message_id,
            'notification_type': 'insight'
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/notify/topic")
async def notify_topic(
    topic: str,
    title: str,
    body: str,
    data: dict = None,
    authorization: str = Header(None)
):
    """Send notification to topic subscribers"""
    try:
        if not authorization:
            raise HTTPException(status_code=401, detail="Not authenticated")
        
        message_id = NotificationService.send_topic_notification(
            topic=topic,
            title=title,
            body=body,
            data=data
        )
        
        return {
            'status': 'success',
            'message_id': message_id,
            'topic': topic
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
async def health_check():
    """Health check endpoint for Cloud Run"""
    return {
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat()
    }


@app.get("/ready")
async def readiness_check():
    """Readiness check for Cloud Run startup"""
    try:
        # Check database connectivity
        # Check external service dependencies
        return {
            'status': 'ready',
            'timestamp': datetime.utcnow().isoformat()
        }
    except Exception as e:
        raise HTTPException(
            status_code=503,
            detail=f"Service not ready: {str(e)}"
        )
```

---

## Step 4: Testing Push Notifications

### 4.1 Test from Cloud Run via curl
```bash
# Get authentication token
TOKEN=$(gcloud auth application-default print-access-token)

# Send test notification
curl -X POST "https://navi-backend-xyz123-uc.a.run.app/notify/topic" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "topic": "push-notifications",
    "title": "Test Notification",
    "body": "This is a test notification from GCP"
  }'
```

### 4.2 Test from Flutter app
```dart
// In your app
Future<void> testNotification() async {
  try {
    final response = await http.post(
      Uri.parse('${GcpConfig.backendUrl}/notify/topic'),
      headers: {
        'Authorization': 'Bearer <YOUR_TOKEN>',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'topic': 'push-notifications',
        'title': 'Test from Flutter',
        'body': 'This is a test',
      }),
    );
    
    if (response.statusCode == 200) {
      print('Notification sent successfully!');
    }
  } catch (e) {
    print('Error sending notification: $e');
  }
}
```

### 4.3 Verify FCM token registration
```dart
// In push_notification_service.dart
Future<void> verifyToken() async {
  String? token = await _firebaseMessaging.getToken();
  print('FCM Token: $token');
  
  // Send to backend to store in user profile
  await GcpApiService().saveUserFcmToken(token!);
}
```

---

## Step 5: Notification User Preferences

### 5.1 Create notification preferences model
Create `backend/models/notification_preference.py`:

```python
from sqlalchemy import Column, String, Boolean, DateTime
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime

Base = declarative_base()

class NotificationPreference(Base):
    __tablename__ = 'notification_preferences'
    
    user_id = Column(String, primary_key=True)
    fcm_token = Column(String)
    
    # Notification types
    mood_predictions = Column(Boolean, default=True)
    insights = Column(Boolean, default=True)
    daily_reminders = Column(Boolean, default=True)
    anomaly_alerts = Column(Boolean, default=True)
    achievements = Column(Boolean, default=True)
    
    # Notification channels
    push_enabled = Column(Boolean, default=True)
    email_enabled = Column(Boolean, default=False)
    sms_enabled = Column(Boolean, default=False)
    
    # Quiet hours
    quiet_hours_start = Column(String, default="22:00")
    quiet_hours_end = Column(String, default="08:00")
    respect_quiet_hours = Column(Boolean, default=True)
    
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
```

### 5.2 Add preferences endpoints
```python
@app.get("/preferences/notifications/{user_id}")
async def get_notification_preferences(user_id: str, authorization: str = Header(None)):
    """Get user notification preferences"""
    try:
        if not authorization:
            raise HTTPException(status_code=401, detail="Not authenticated")
        
        # Query from database
        preferences = db.query(NotificationPreference).filter_by(user_id=user_id).first()
        
        if not preferences:
            # Return defaults
            return {
                'user_id': user_id,
                'mood_predictions': True,
                'insights': True,
                'daily_reminders': True,
                'anomaly_alerts': True,
                'achievements': True,
                'push_enabled': True
            }
        
        return preferences.to_dict()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.put("/preferences/notifications/{user_id}")
async def update_notification_preferences(
    user_id: str,
    preferences: dict,
    authorization: str = Header(None)
):
    """Update user notification preferences"""
    try:
        if not authorization:
            raise HTTPException(status_code=401, detail="Not authenticated")
        
        # Update in database
        pref = db.query(NotificationPreference).filter_by(user_id=user_id).first()
        if pref:
            for key, value in preferences.items():
                if hasattr(pref, key):
                    setattr(pref, key, value)
        else:
            pref = NotificationPreference(user_id=user_id, **preferences)
        
        db.add(pref)
        db.commit()
        
        return {'status': 'success', 'preferences': pref.to_dict()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
```

---

## Step 6: Monitoring & Debugging

### 6.1 View Pub/Sub metrics
```bash
# Check topic metrics
gcloud pubsub topics describe push-notifications

# Check subscription metrics
gcloud pubsub subscriptions describe push-notifications-fcm

# View published messages
gcloud pubsub subscriptions pull push-notifications-logs --auto-ack --limit=10
```

### 6.2 View FCM delivery logs
```bash
# Cloud Run logs
gcloud run services logs read navi-backend --region=us-central1 --limit=100 | grep notification

# Cloud Logging
gcloud logging read "resource.type=cloud_run_revision AND jsonPayload.severity=INFO" --limit=50
```

### 6.3 Set up alerting
```bash
# Create alert for notification failures
gcloud alpha monitoring policies create \
  --display-name="High notification failure rate" \
  --condition-display-name="Notification failures > 10%" \
  --condition-threshold-value=10 \
  --notification-channels=[YOUR_CHANNEL_ID]
```

---

## Cost Estimate

| Service | Monthly Cost | Notes |
|---------|---|---|
| Cloud Pub/Sub | $5-20 | Per million messages |
| FCM | $0 | Free (part of Firebase) |
| Cloud Logging | $5-10 | Ingested log volume |
| **Total** | **$10-30** | Scales with usage |

---

## Deployment Checklist

- [ ] FCM enabled in Firebase Console
- [ ] APNS certificates uploaded (iOS)
- [ ] SHA-1 fingerprint added (Android)
- [ ] Pub/Sub topic and subscriptions created
- [ ] Service account permissions configured
- [ ] Firebase Admin SDK key stored in Secret Manager
- [ ] Backend notification endpoints deployed
- [ ] Flutter app receiving FCM tokens
- [ ] Test notification sent successfully
- [ ] Logs visible in Cloud Logging
- [ ] User preferences stored in Cloud SQL
- [ ] Monitoring alerts configured

---

## Troubleshooting

### FCM tokens not registering
```
1. Check Firebase console for app registration
2. Verify SHA-1 fingerprint for Android
3. Check Cloud Logging for registration errors
```

### Notifications not being delivered
```
1. Verify FCM token is valid and recent
2. Check Pub/Sub subscription configuration
3. Review Cloud Logging for delivery failures
4. Check user notification preferences
```

### High Pub/Sub latency
```
1. Scale Pub/Sub subscription (increase ackDeadline)
2. Add more Cloud Run replicas
3. Optimize backend message processing
```

---

## Next Steps

1. Configure notification preferences UI in Flutter app
2. Implement batch notification sending for efficiency
3. Set up scheduled notifications (Cloud Scheduler)
4. Add analytics for notification engagement
5. Implement notification templates and personalization

---

Generated: May 13, 2026
