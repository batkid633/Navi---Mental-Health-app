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
# dart pub global run flutterfire_cli:flutterfire configure --project=$PROJECT_ID

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

# Push to Container Registry
docker tag navi-backend:latest gcr.io/$PROJECT_ID/navi-backend:latest
docker push gcr.io/$PROJECT_ID/navi-backend:latest

# Deploy to Cloud Run
gcloud run deploy navi-backend \
  --image=gcr.io/$PROJECT_ID/navi-backend:latest \
  --platform=managed \
  --region=$REGION \
  --memory=1Gi \
  --no-allow-unauthenticated

# Get backend URL
gcloud run services describe navi-backend --region=$REGION --format='value(status.url)'
```

### Step 4: Update Flutter App (5 min)
1. Copy backend URL from Step 3
2. Update `lib/config/gcp_config.dart` with new backend URL
3. Run `flutter pub get`

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
- [ ] Enable Cloud SQL SSL/TLS
- [ ] Set up VPC peering between Cloud Run and Cloud SQL
- [ ] Configure IAM roles properly
- [ ] Enable Cloud Armor for DDoS protection
- [ ] Set up Cloud Audit Logging
- [ ] Review HIPAA compliance settings
- [ ] Configure Secret Manager for sensitive data
- [ ] Set up Cloud Security Command Center

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

---

## 🔄 Deployment Workflow

### Development Flow
```bash
# 1. Make changes locally
# 2. Test locally:
cd backend && python -m uvicorn app:main --reload

# 3. Build & push to Container Registry
docker build -t navi-backend:latest .
docker tag navi-backend:latest gcr.io/$PROJECT_ID/navi-backend:latest
docker push gcr.io/$PROJECT_ID/navi-backend:latest

# 4. Deploy to Cloud Run
gcloud run deploy navi-backend --image=gcr.io/$PROJECT_ID/navi-backend:latest

# 5. Test in production
curl -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  https://navi-backend-xyz-uc.a.run.app/health
```

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
print(GcpConfig.backendUrl);

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
- [ ] Database schema initialized
- [ ] Secrets stored in Secret Manager
- [ ] Docker image tested locally
- [ ] Flutter app tested with production backend URL
- [ ] SSL certificates ready (if custom domain)
- [ ] Monitoring dashboards created
- [ ] Backup strategy planned

### Deployment
- [ ] Cloud Run service deployed
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
- Test thoroughly in staging before production deployment
- Monitor costs in the first month - GCP bills based on usage
- Set up billing alerts to avoid surprises
- Document any customizations to the standard setup

---

**Last Updated:** May 13, 2026  
**Status:** Ready for Implementation  
**Questions?** See the detailed guides above or check GCP Documentation

---
