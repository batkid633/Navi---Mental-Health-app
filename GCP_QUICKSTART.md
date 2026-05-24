# GCP Migration Quick Start Guide

## 🎯 Overview
This is your quick reference for migrating Navi Personal to Google Cloud Platform. Follow these steps in order.

---

## 📋 Prerequisites Checklist

- [ ] GCP account with billing enabled
- [ ] Google Cloud SDK installed (`gcloud` CLI)
- [ ] Docker Desktop installed
- [ ] Flutter SDK installed
- [ ] Git configured
- [ ] Google Cloud Code extension installed in VS Code

---

## 🚀 Quick Start (30 minutes)

### Step 1: Initial Setup (5 min)
```bash
# Set project variables
export PROJECT_ID="project-bc878e6c-6f53-4f24-88a"
export REGION="us-central1"

# Create or select your GCP project
# If the project already exists, skip creation and just set it:
# gcloud config set project $PROJECT_ID
# Otherwise create it if needed:
# gcloud projects create $PROJECT_ID --name="Navi Personal GCP"
gcloud config set project $PROJECT_ID

# Enable billing and APIs
gcloud services enable cloudbilling.googleapis.com run.googleapis.com sqladmin.googleapis.com serviceusage.googleapis.com artifactregistry.googleapis.com

# If you already have Firebase in this project, install FlutterFire CLI if needed and update your Firebase configuration:
# dart pub global activate flutterfire_cli
# flutterfire configure --project $PROJECT_ID
```

### Step 2: Database Setup (10 min)
```bash
# Create Cloud SQL instance
gcloud sql instances create navi-postgresql \
  --database-version=POSTGRES_15 \
  --tier=db-f1-micro \
  --region=$REGION \
  --availability-type=REGIONAL

# Create database and user
gcloud sql databases create navi_db --instance=navi-postgresql
gcloud sql users create navi_admin --instance=navi-postgresql --password=$(openssl rand -base64 32)
```

### Step 3: Build & Deploy Backend (10 min)
```bash
# Navigate to backend directory
cd backend/

# Build Docker image
docker build -t navi-backend:latest .

# Create an Artifact Registry repository if this is your first deploy
gcloud artifacts repositories create navi-backend \
  --repository-format=docker \
  --location=$REGION \
  --description="Navi backend Docker images"

# Let Docker push to Artifact Registry
gcloud auth configure-docker $REGION-docker.pkg.dev

# Push to Artifact Registry
docker tag navi-backend:latest $REGION-docker.pkg.dev/$PROJECT_ID/navi-backend/navi-backend:latest
docker push $REGION-docker.pkg.dev/$PROJECT_ID/navi-backend/navi-backend:latest

# Deploy to Cloud Run
# Use --allow-unauthenticated for a consumer app backend, then enforce
# Firebase ID token auth inside FastAPI. Do not rely on Cloud Run IAM for
# normal app users unless every user has Google Cloud IAM access.
gcloud run deploy navi-backend \
  --image=$REGION-docker.pkg.dev/$PROJECT_ID/navi-backend/navi-backend:latest \
  --platform=managed \
  --region=$REGION \
  --memory=1Gi \
  --allow-unauthenticated \
  --set-env-vars=ENVIRONMENT=production,AUTH_REQUIRED=true,ALLOW_CORS_FROM=https://app.yourdomain.com

# Get backend URL
gcloud run services describe navi-backend --region=$REGION --format='value(status.url)'
```

### Step 4: Deploy Flutter Web Frontend (5 min)
```bash
# From the repo root
flutter pub get
flutter build web --release
firebase deploy --only hosting
```

For local testing, set the backend URL inside the app settings screen. For production, point the app at your Cloud Run URL or your `api.yourdomain.com` URL once the custom backend domain is configured.

### Step 5: Custom Domain Shape

Recommended domain layout:

- `app.yourdomain.com` or `www.yourdomain.com` -> Firebase Hosting for the Flutter web app
- `api.yourdomain.com` -> Cloud Run backend, usually through a Google Cloud external Application Load Balancer for production

If the domain is purchased through Squarespace, Squarespace remains the registrar. You edit DNS records in Squarespace and paste in the TXT, A, AAAA, or CNAME records that Firebase Hosting and Google Cloud give you.

---

## 📚 Detailed Documentation

### Core Guides
1. **[GCP_MIGRATION_GUIDE.md](GCP_MIGRATION_GUIDE.md)** - Strategic overview & benefits
2. **[GCP_SETUP.md](GCP_SETUP.md)** - Comprehensive step-by-step setup
3. **[GCP_FLUTTER_MIGRATION.md](GCP_FLUTTER_MIGRATION.md)** - Flutter app integration
4. **[GCP_PUSH_NOTIFICATIONS.md](GCP_PUSH_NOTIFICATIONS.md)** - Push notifications setup

### Infrastructure Files
- **[Dockerfile](backend/Dockerfile)** - Backend containerization
- **[cloud-run-config.yaml](cloud-run-config.yaml)** - Cloud Run & SQL configuration
- **[.env.example](.env.example)** - Environment variables template
- **[.env.production](.env.production)** - Production configuration

---

## 🔑 Key GCP Services Overview

```
┌────────────────────────────────────────────────────────────┐
│                    Your Navi App                           │
│  (Flutter: Android, iOS, macOS, Windows, Web)              │
└────────────────────────┬─────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ↓                ↓                ↓
   ┌─────────┐      ┌─────────┐      ┌─────────────┐
   │Cloud Run│      │Cloud SQL│      │Cloud Pub/Sub│
   │(Backend)│      │(Database)       │(Messaging) │
   └─────────┘      └─────────┘      └─────────────┘
        │                │                │
        └────────────────┼────────────────┘
                         ↓
              ┌──────────────────────┐
              │ Cloud Logging &      │
              │ Monitoring (Dashboards)
              └──────────────────────┘
```

---

## 💰 Cost Estimation

**Monthly Estimate: $50-150**

| Service | Cost | Usage |
|---------|------|-------|
| Cloud Run | $10-50 | 2M free requests, then $0.00002/request |
| Cloud SQL | $30-50 | db-f1-micro instance with daily backups |
| Cloud Storage | $5-20 | Audio files, media storage |
| Cloud Pub/Sub | $5-15 | Push notifications |
| Cloud Logging | $5-10 | Logs retention & analysis |
| **Total** | **$55-145** | Scales with usage |

*GCP offers $300 free credit for new accounts!*

---

## 🔐 Security Best Practices

### Before Going Live
- [ ] Firebase ID token auth enforced on sensitive backend routes (`AUTH_REQUIRED=true`)
- [ ] Cloud Run `ALLOW_CORS_FROM` restricted to real frontend domains
- [ ] Cloud Run service account has only the IAM roles it needs
- [ ] Enable Cloud SQL SSL/TLS
- [ ] Set up VPC peering between Cloud Run and Cloud SQL
- [ ] Configure IAM roles properly
- [ ] Enable Cloud Armor for DDoS protection
- [ ] Set up Cloud Audit Logging
- [ ] Review HIPAA compliance settings
- [ ] Configure Secret Manager for sensitive data
- [ ] Set up Cloud Security Command Center
- [ ] Move durable journal/audio metadata out of local files and into Firestore/Data Connect/Cloud SQL
- [ ] Store raw audio in Cloud Storage, not inside the Cloud Run container
- [ ] Add user data export, account deletion, consent, and retention policies

### Ongoing
- [ ] Monitor error rates and latency
- [ ] Review access logs weekly
- [ ] Rotate secrets quarterly
- [ ] Keep dependencies updated
- [ ] Run security scans regularly

---

## 📊 Monitoring Setup

### View Your Dashboard
```bash
# Create monitoring dashboard
gcloud monitoring dashboards create --config-from-file=cloud-run-config.yaml

# View Cloud Run metrics
gcloud monitoring time-series list --filter 'metric.type="run.googleapis.com/request_latencies"'

# View logs
gcloud run services logs read navi-backend --limit=50 --region=$REGION
```

### Common Metrics to Watch
- Request latency (target: <500ms)
- Error rate (target: <1%)
- CPU usage (target: <70%)
- Memory usage (target: <80%)
- Database connection count
- Per-user ML feature sync success/failure
- LLM fallback insight rate

---

## 🔄 Deployment Workflow

### What To Deploy After Each Kind Of Change

| Changed thing | Deploy action |
|---------------|---------------|
| Backend Python code, backend dependencies, Dockerfile, ML runtime code | Rebuild Docker image, push to Artifact Registry, deploy Cloud Run |
| Flutter web UI or client service code | `flutter build web --release`, then `firebase deploy --only hosting` |
| Android/iOS app code | Build and submit a new mobile release through app stores/TestFlight/internal testing |
| Environment variables, secrets, CORS domains | Update Cloud Run env vars or Secret Manager; usually no code rebuild |
| Firestore or Storage security rules | `firebase deploy --only firestore:rules` or `firebase deploy --only storage` |
| Database schema or Data Connect changes | Deploy the schema/rules and run migrations carefully |
| Static docs only | No cloud deploy unless the docs are hosted publicly |

### Development Flow
```bash
# 1. Make changes locally
# 2. Test locally:
cd backend && python -m uvicorn app:app --reload

# 3. Build & push to Artifact Registry
docker build -t navi-backend:latest .
docker tag navi-backend:latest $REGION-docker.pkg.dev/$PROJECT_ID/navi-backend/navi-backend:latest
docker push $REGION-docker.pkg.dev/$PROJECT_ID/navi-backend/navi-backend:latest

# 4. Deploy to Cloud Run
gcloud run deploy navi-backend \
  --image=$REGION-docker.pkg.dev/$PROJECT_ID/navi-backend/navi-backend:latest \
  --region=$REGION \
  --allow-unauthenticated

# 5. Deploy web frontend if Flutter web changed
flutter build web --release
firebase deploy --only hosting

# 6. Test public health endpoint
curl https://navi-backend-xyz-uc.a.run.app/health
```

Sensitive endpoints now expect a Firebase ID token in `Authorization: Bearer <token>`. The Flutter app sends this automatically after sign-in. `GET /health`, `GET /ready`, and the WHOOP OAuth callback stay public because monitoring systems and WHOOP cannot attach a signed-in app user's Firebase token.

### CI/CD (Optional - Cloud Build)
```bash
# Set up automatic deployment on git push
gcloud builds submit --config=cloudbuild.yaml
```

---

## 🆘 Troubleshooting

### Backend won't start
```bash
# Check Cloud Run logs
gcloud run services logs read navi-backend --region=$REGION --limit=100

# Common issues:
# 1. Wrong Cloud SQL connection string
# 2. Missing environment variables
# 3. Port not 8080
# 4. Insufficient memory allocation
```

### Database connection failed
```bash
# Test Cloud SQL proxy locally
cloud_sql_proxy -instances=$PROJECT_ID:$REGION:navi-postgresql=tcp:5432 &

# Connect to database
psql -h 127.0.0.1 -U navi_admin -d navi_db

# Check connection string format:
# postgresql://USER:PASSWORD@HOST:PORT/DATABASE
```

### Flutter app can't reach backend
```dart
// Check network connectivity
bool online = await ConnectivityHelper().isOnline();

// Verify backend URL
print(BackendConfig.baseUrl);

// Test health endpoint
bool healthy = await GcpApiService().healthCheck();
```

### Push notifications not working
```bash
# Verify FCM topic
gcloud pubsub topics describe push-notifications

# Check subscriptions
gcloud pubsub subscriptions list

# Test message publishing
gcloud pubsub topics publish push-notifications \
  --message '{"test":"message"}'
```

---

## ✅ Deployment Checklist

### Pre-Deployment
- [ ] All environment variables configured
- [ ] `ENVIRONMENT=production`
- [ ] `AUTH_REQUIRED=true`
- [ ] `ALLOW_CORS_FROM` contains only production frontend domains
- [ ] Database schema initialized
- [ ] Secrets stored in Secret Manager
- [ ] Docker image tested locally
- [ ] Flutter app tested with production backend URL
- [ ] SSL certificates ready (if custom domain)
- [ ] Monitoring dashboards created
- [ ] Backup strategy planned

### Deployment
- [ ] Cloud Run service deployed
- [ ] Firebase Hosting deployed for Flutter web
- [ ] Firestore rules deployed: `firebase deploy --only firestore:rules`
- [ ] Storage rules deployed: `firebase deploy --only storage`
- [ ] Database running and accessible
- [ ] Push notifications working
- [ ] Firebase Cloud Messaging configured
- [ ] Health checks passing
- [ ] Logs flowing to Cloud Logging
- [ ] Metrics visible in monitoring dashboard

### Post-Deployment
- [ ] Smoke tests passed
- [ ] Real user testing completed
- [ ] Performance benchmarks met
- [ ] Cost within estimates
- [ ] Security review completed
- [ ] Team training completed
- [ ] Runbook documented
- [ ] Escalation procedures ready

---

## 📞 Getting Help

### GCP Resources
- [Google Cloud Console](https://console.cloud.google.com)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Cloud SQL Documentation](https://cloud.google.com/sql/docs)
- [GCP Support](https://support.google.com/cloud)

### Your Team Resources
- Check Cloud Logging for error details
- Review Cloud Run metrics
- Ask in project Slack channel
- Contact your GCP admin

### Common Commands Reference
```bash
# List all services
gcloud run services list

# Get service details
gcloud run services describe navi-backend --region=$REGION

# View service URL
gcloud run services describe navi-backend --region=$REGION --format='value(status.url)'

# Tail logs
gcloud run services logs read navi-backend --region=$REGION --follow

# SSH into Cloud Shell for debugging
gcloud cloud-shell ssh

# Monitor costs
gcloud billing accounts list
gcloud compute project-info describe --project=$PROJECT_ID
```

---

## 🎓 Next Steps

1. **Immediate** (This week)
   - [ ] Complete GCP project setup
   - [ ] Deploy backend to Cloud Run
   - [ ] Update Flutter app
   - [ ] Run integration tests

2. **Short-term** (This month)
   - [ ] Set up push notifications
   - [ ] Configure monitoring dashboards
   - [ ] Implement offline mode
   - [ ] Beta test with team

3. **Medium-term** (This quarter)
   - [ ] Migrate production data
   - [ ] Set up CI/CD pipeline
   - [ ] Complete HIPAA compliance review
   - [ ] Launch to production

4. **Long-term** (This year)
   - [ ] Optimize costs
   - [ ] Implement auto-scaling policies
   - [ ] Add caching layer
   - [ ] Plan multi-region setup

---

## 📝 Notes

- Keep environment variables secure - never commit `.env.production`
- For local backend runs, edit `.env` or set shell environment variables. `.env.production` is a production template and is not automatically read by `flutter run`.
- Test thoroughly in staging before production deployment
- Monitor costs in the first month - GCP bills based on usage
- Set up billing alerts to avoid surprises
- Document any customizations to the standard setup

---

**Last Updated:** May 13, 2026  
**Status:** Ready for Implementation  
**Questions?** See the detailed guides above or check GCP Documentation

---
