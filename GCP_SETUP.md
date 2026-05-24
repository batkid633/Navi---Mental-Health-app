# GCP Setup & Deployment Guide

## Prerequisites
- GCP account with billing enabled
- Google Cloud SDK installed locally
- Docker Desktop installed
- Flutter SDK (for later steps)
- Admin access to GCP project

---

## Step 1: GCP Project Setup

### 1.1 Select your billing-enabled GCP project
```bash
# Set your project ID
export PROJECT_ID="project-bc878e6c-6f53-4f24-88a"

# If the project already exists, just use it:
gcloud config set project $PROJECT_ID

# If you need to create a new project in the future, use:
# gcloud projects create $PROJECT_ID --name="Navi Personal GCP"
# gcloud config set project $PROJECT_ID

# Billing must already be enabled for this project.
```
### 1.2 Enable required APIs
```bash
gcloud services enable \
  run.googleapis.com \
  sqladmin.googleapis.com \
  compute.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  pubsub.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  cloudbilling.googleapis.com \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  cloudkms.googleapis.com
```

### 1.3 Configure Firebase for the new project
If you want Firebase services in this same project, register your app with Firebase and generate updated config.

```bash
# Install FlutterFire CLI if needed
dart pub global activate flutterfire_cli

# Make sure pub global bin is on your PATH
# For bash:
# export PATH="$PATH":"$HOME/.pub-cache/bin"
# For PowerShell:
# setx PATH "$env:PATH;$env:USERPROFILE\.pub-cache\bin"

# Configure Firebase for the current project
flutterfire configure --project $PROJECT_ID
```

This will regenerate `lib/firebase_options.dart` and update the Firebase configuration for your current project.

### 1.4 Create a service account for Cloud Run
```bash
# Create service account
gcloud iam service-accounts create navi-cloud-run \
  --display-name="Navi Cloud Run Service Account"

# Grant necessary roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:navi-cloud-run@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:navi-cloud-run@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

---

## Step 2: Cloud SQL Setup (HIPAA-Compliant PostgreSQL)

### 2.1 Create Cloud SQL instance
```bash
# Set instance name
export INSTANCE_NAME="navi-postgresql"
export DB_NAME="navi_db"
export DB_USER="navi_admin"
export DB_PASSWORD="$(openssl rand -base64 32)"  # Generate secure password

# Create instance (HIPAA-capable)
gcloud sql instances create $INSTANCE_NAME \
  --database-version=POSTGRES_15 \
  --tier=db-f1-micro \
  --region=us-central1 \
  --availability-type=REGIONAL \
  --enable-bin-log \
  --backup-location=us \
  --no-assign-ip \
  --enable-bin-log
```

### 2.2 Create database and user
```bash
# Create database
gcloud sql databases create $DB_NAME \
  --instance=$INSTANCE_NAME

# Create database user
gcloud sql users create $DB_USER \
  --instance=$INSTANCE_NAME \
  --password=$DB_PASSWORD
```

### 2.3 Enable Cloud SQL Auth proxy for local testing
```bash
# Create service account key
gcloud iam service-accounts keys create ~/key.json \
  --iam-account=navi-cloud-run@$PROJECT_ID.iam.gserviceaccount.com

# Grant Cloud SQL Client role
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:navi-cloud-run@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"
```

### 2.4 Get connection string
```bash
# Get Cloud SQL connection details
gcloud sql instances describe $INSTANCE_NAME --format='value(connectionName)'
# Output will be like: project-bc878e6c-6f53-4f24-88a:us-central1:navi-postgresql

# Store for later use
export CLOUDSQL_CONNECTION_NAME="project-bc878e6c-6f53-4f24-88a:us-central1:navi-postgresql"
```

### 2.5 Store sensitive data in Secret Manager
```bash
# Store database password
echo -n $DB_PASSWORD | gcloud secrets create db-password \
  --replication-policy="automatic" \
  --data-file=-

# Store database connection string
echo -n "$CLOUDSQL_CONNECTION_NAME" | gcloud secrets create db-connection-name \
  --replication-policy="automatic" \
  --data-file=-

# Grant Cloud Run service account access
gcloud secrets add-iam-policy-binding db-password \
  --member="serviceAccount:navi-cloud-run@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding db-connection-name \
  --member="serviceAccount:navi-cloud-run@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

---

## Step 3: Container Registry & Cloud Build

### 3.1 Build Docker image locally (for testing)
```bash
cd backend/

# Build image
docker build -t navi-backend:latest .

# Test locally
docker run -p 8080:8080 \
  -e DATABASE_URL="postgresql://..." \
  navi-backend:latest
```

### 3.2 Push to Artifact Registry
```bash
# Set registry location
export REGISTRY_LOCATION="us-central1"

# Create Artifact Registry repository
gcloud artifacts repositories create navi-backend \
  --repository-format=docker \
  --location=$REGISTRY_LOCATION

# Configure Docker authentication
gcloud auth configure-docker $REGISTRY_LOCATION-docker.pkg.dev

# Tag and push image
docker tag navi-backend:latest \
  $REGISTRY_LOCATION-docker.pkg.dev/$PROJECT_ID/navi-backend/navi-backend:latest

docker push \
  $REGISTRY_LOCATION-docker.pkg.dev/$PROJECT_ID/navi-backend/navi-backend:latest
```

---

## Step 4: Deploy to Cloud Run

### 4.1 Deploy using gcloud CLI
```bash
# Set deployment parameters
export SERVICE_NAME="navi-backend"
export MEMORY="1Gi"
export CPU="1"
export TIMEOUT="3600"

# Deploy to Cloud Run
gcloud run deploy $SERVICE_NAME \
  --image=$REGISTRY_LOCATION-docker.pkg.dev/$PROJECT_ID/navi-backend/navi-backend:latest \
  --platform=managed \
  --region=us-central1 \
  --memory=$MEMORY \
  --cpu=$CPU \
  --timeout=$TIMEOUT \
  --service-account=navi-cloud-run@$PROJECT_ID.iam.gserviceaccount.com \
  --no-allow-unauthenticated \
  --set-env-vars="DATABASE_URL=postgresql://$DB_USER:$(gcloud secrets versions access latest --secret=db-password)@cloudsql/$CLOUDSQL_CONNECTION_NAME/$DB_NAME" \
  --cloud-sql-instances=$CLOUDSQL_CONNECTION_NAME \
  --set-cloudsql-instances=$CLOUDSQL_CONNECTION_NAME
```

### 4.2 Get Cloud Run service URL
```bash
gcloud run services describe $SERVICE_NAME \
  --region=us-central1 \
  --format='value(status.url)'

# This will output something like:
# https://navi-backend-xyz123-uc.a.run.app
export BACKEND_URL="https://navi-backend-xyz123-uc.a.run.app"
```

### 4.3 Allow Flutter app to call backend
```bash
# Get Flutter app service account email
export FLUTTER_SERVICE_ACCOUNT="flutter-app@$PROJECT_ID.iam.gserviceaccount.com"

# Create service account if needed
gcloud iam service-accounts create flutter-app \
  --display-name="Flutter App Service Account"

# Grant Cloud Run invoker role
gcloud run services add-iam-policy-binding $SERVICE_NAME \
  --member="serviceAccount:$FLUTTER_SERVICE_ACCOUNT" \
  --role="roles/run.invoker" \
  --region=us-central1
```

---

## Step 5: Database Migration

### 5.1 Update app.py for Cloud SQL
The app.py should connect to Cloud SQL. Update the DATABASE_URL environment variable:

```python
# In app.py
import os
from sqlalchemy import create_engine

# Get from environment or Secret Manager
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://user:password@localhost/navi_db"
)

engine = create_engine(DATABASE_URL)
```

### 5.2 Initialize database schema
```bash
# After deployment, you can run migrations via Cloud Run one-time job
# Or connect via Cloud SQL proxy from local machine

# Local connection using proxy:
cloud_sql_proxy -instances=$CLOUDSQL_CONNECTION_NAME=tcp:5432 &

# Connect to database
psql -h 127.0.0.1 \
  -U $DB_USER \
  -d $DB_NAME

# Run migrations/setup SQL scripts
```

---

## Step 6: Monitoring & Logging

### 6.1 View Cloud Run logs
```bash
# Real-time logs
gcloud run services logs read $SERVICE_NAME \
  --region=us-central1 \
  --limit 50 \
  --follow

# View specific error
gcloud run services logs read $SERVICE_NAME \
  --region=us-central1 \
  --limit 100 | grep ERROR
```

### 6.2 Set up monitoring alerts
```bash
# Create alert policy for high error rate
gcloud alpha monitoring policies create \
  --display-name="High error rate" \
  --condition-display-name="Error rate > 5%" \
  --condition-threshold-value=5 \
  --notification-channels=[CHANNEL_ID]
```

---

## Step 7: Security Hardening

### 7.1 Configure Cloud SQL for HIPAA
```bash
# Enable SSL connections
gcloud sql instances patch $INSTANCE_NAME \
  --require-ssl

# View SSL configuration
gcloud sql instances describe $INSTANCE_NAME \
  --format='value(settings.ipConfiguration.requireSsl)'
```

### 7.2 Set up VPC for private connectivity
```bash
# Create VPC network
gcloud compute networks create navi-vpc --subnet-mode=custom

# Create subnet
gcloud compute networks subnets create navi-subnet \
  --network=navi-vpc \
  --range=10.0.0.0/24

# Allocate IP range for VPC peering
gcloud compute addresses create navi-private-ip \
  --global \
  --purpose=VPC_PEERING \
  --prefix-length=16 \
  --network=navi-vpc

# Enable private service connection
gcloud services vpc-peerings connect \
  --service=servicenetworking.googleapis.com \
  --ranges=navi-private-ip \
  --network=navi-vpc
```

---

## Step 8: Continuous Deployment (Optional)

### 8.1 Set up Cloud Build for automatic deployment
Create `backend/cloudbuild.yaml`:
```yaml
steps:
  # Build image
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'gcr.io/$PROJECT_ID/navi-backend', '.']
  
  # Push to registry
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'gcr.io/$PROJECT_ID/navi-backend']
  
  # Deploy to Cloud Run
  - name: 'gcr.io/cloud-builders/gke-deploy'
    args:
      - run
      - --filename=.
      - --image=gcr.io/$PROJECT_ID/navi-backend
      - --location=us-central1
      - --cluster=navi-cluster
```

---

## Verification Checklist

- [ ] GCP project created and billing enabled
- [ ] APIs enabled successfully
- [ ] Service accounts created with proper roles
- [ ] Cloud SQL instance running
- [ ] Database created and user configured
- [ ] Backend Docker image built locally
- [ ] Image pushed to Artifact Registry
- [ ] Cloud Run service deployed
- [ ] Backend URL accessible
- [ ] Cloud SQL connection working
- [ ] Monitoring and logging configured
- [ ] Security settings hardened

---

## Troubleshooting

### Cloud Run service not starting
```bash
# Check logs
gcloud run services logs read navi-backend --region=us-central1 --limit 100

# Common issues:
# - Wrong Cloud SQL connection string
# - Missing environment variables
# - Insufficient memory/CPU allocation
```

### Database connection failures
```bash
# Check Cloud SQL proxy status
ps aux | grep cloud_sql_proxy

# Test connection locally
cloud_sql_proxy -instances=$CLOUDSQL_CONNECTION_NAME=tcp:5432 &
psql -h 127.0.0.1 -U $DB_USER -d $DB_NAME
```

### High costs
```bash
# Review usage
gcloud compute project-info describe --project=$PROJECT_ID

# Set up budget alerts
gcloud billing budgets create \
  --billing-account=BILLING_ACCOUNT_ID \
  --display-name="Navi Monthly Budget" \
  --budget-amount=100 \
  --threshold-rule=percent=50 \
  --threshold-rule=percent=100
```

---

## Next Steps

1. Follow **GCP_FLUTTER_MIGRATION.md** to update your Flutter app
2. Configure push notifications in **GCP_PUSH_NOTIFICATIONS.md**
3. Set up monitoring dashboards
4. Plan HIPAA compliance review with your legal team

---

Generated: May 13, 2026
