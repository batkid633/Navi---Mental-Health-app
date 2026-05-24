# Navi Personal - GCP Migration Guide

## Overview
This document provides a complete migration strategy for moving Navi Personal to Google Cloud Platform with a focus on scaling, database management, HIPAA compliance, and mobile app delivery.

## Current Architecture
- **Frontend**: Flutter app (Android, iOS, macOS, Windows, Web)
- **Backend**: FastAPI (Python) with ML/AI components
- **Storage**: Local Hive database (will migrate to Cloud SQL)
- **Features**: Audio analysis, mood prediction, WHOOP API integration, sentiment analysis

---

## Why GCP is Better for Your Use Case

### 1. **Scaling**
- **Cloud Run**: Auto-scales from 0 to 1000+ instances based on traffic
- **No cold starts for sustained use**: Maintains containers when needed
- **Cost-effective**: Pay per request, not hourly
- **Current state**: Local development can't handle concurrent users

### 2. **Database Management (HIPAA Compliance)**
- **Cloud SQL**: Enterprise-grade, HIPAA Business Associate Agreement (BAA) available
- **Automatic backups**: Daily backups with point-in-time recovery
- **SSL/TLS encryption**: In-transit and at-rest encryption
- **Access control**: VPC isolation, IAM roles, audit logging
- **Current state**: Local storage is vulnerable and non-compliant

### 3. **Mobile App Pushing (Push Notifications)**
- **Firebase Cloud Messaging (FCM)**: Integrated with GCP
- **Cloud Pub/Sub**: Event streaming for real-time notifications
- **Latency**: <10ms delivery
- **Current state**: No push notification infrastructure

### 4. **Mobile App Distribution**
- **Google Play Console integration**: Direct publishing from GCP
- **Staged rollouts**: Gradual deployment to test safety
- **Beta testing**: TestFlight-equivalent for Android
- **Current state**: Manual APK distribution

### 5. **ML/AI Infrastructure**
- **Vertex AI**: Train ML models at scale (audio analysis, mood prediction)
- **BigQuery**: Analyze user behavior patterns
- **Cloud AI APIs**: Vision, Speech, NLP services
- **Current state**: Local ML model training, limited data

### 6. **Additional Benefits**
| Aspect | Local | GCP |
|--------|-------|-----|
| Uptime SLA | N/A | 99.95% |
| Security Monitoring | Manual | 24/7 automated |
| Data Center Redundancy | Single machine | Multi-region |
| Cost Scaling | Exponential | Linear/Predictable |
| Disaster Recovery | Manual | Automated |
| HIPAA Compliance | Manual | Built-in |

---

## GCP Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Mobile App                        │
│         (Android, iOS, macOS, Windows, Web)                 │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────────┐
│            Cloud Load Balancer (Global)                      │
│         (Optional: CDN for static assets)                    │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────────┐
│         Cloud Run (Python FastAPI Backend)                  │
│    • Auto-scaling (0-1000 instances)                        │
│    • Container Registry integration                         │
│    • VPC connector for secure access                        │
└────────────────────────┬────────────────────────────────────┘
         │               │               │
         ↓               ↓               ↓
    ┌────────────┐  ┌──────────┐  ┌─────────────┐
    │ Cloud SQL  │  │Cloud     │  │Cloud        │
    │PostgreSQL  │  │Storage   │  │Pub/Sub      │
    │(HIPAA BAA) │  │(Audio,   │  │(Push        │
    │            │  │Files)    │  │Notif)       │
    └────────────┘  └──────────┘  └─────────────┘
         │               │               │
         └───────────────┼───────────────┘
                         ↓
              ┌──────────────────────┐
              │  Cloud Logging &     │
              │  Cloud Monitoring    │
              │  (Real-time metrics) │
              └──────────────────────┘
```

---

## Migration Steps

### Phase 1: Project Setup
1. Create GCP project
2. Enable required APIs
3. Set up billing alerts
4. Configure VPC network
5. Set up Cloud SQL instance

### Phase 2: Backend Containerization
1. Create Dockerfile for FastAPI app
2. Build and push to Container Registry
3. Deploy to Cloud Run
4. Set environment variables and secrets

### Phase 3: Database Migration
1. Create Cloud SQL database
2. Migrate data schema
3. Test connectivity from Cloud Run
4. Set up backups and monitoring

### Phase 4: Flutter App Updates
1. Update API endpoints
2. Configure authentication
3. Set up Firebase Cloud Messaging
4. Test all services

### Phase 5: Push Notifications
1. Set up Cloud Pub/Sub topic
2. Configure FCM integration
3. Update app to handle notifications

### Phase 6: Monitoring & Optimization
1. Enable Cloud Logging
2. Set up monitoring dashboards
3. Configure alerts
4. Optimize costs

---

## Cost Estimates (Monthly)

| Service | Estimated Cost | Notes |
|---------|---|---|
| Cloud Run | $10-50 | Depends on traffic; includes 2M free requests/month |
| Cloud SQL (PostgreSQL) | $30-50 | Small instance; includes daily backups |
| Cloud Storage | $5-20 | For audio files and media |
| Cloud Pub/Sub | $5-15 | For push notifications |
| **Total** | **$50-135** | Highly scalable, minimal initial cost |

*These are conservative estimates. GCP has generous free tier and discounts for sustained use.*

---

## Security & Compliance Checklist

- [ ] Enable VPC Service Controls
- [ ] Configure Cloud SQL with private IP
- [ ] Enable Cloud SQL automatic backups
- [ ] Set up audit logging
- [ ] Configure IAM roles properly
- [ ] Enable encryption at rest and in transit
- [ ] Set up Cloud Armor for DDoS protection
- [ ] Enable Cloud Security Command Center
- [ ] Complete HIPAA BAA addendum with Google
- [ ] Regular security reviews

---

## Next Steps

1. Review the `GCP_SETUP.md` for step-by-step setup
2. Check `Dockerfile` for backend containerization
3. Review `cloud-run-config.yaml` for deployment
4. Update `pubspec.yaml` if needed for GCP integrations
5. Follow the Flutter app updates in `GCP_FLUTTER_MIGRATION.md`

---

## Support & Documentation

- [Google Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Cloud SQL Documentation](https://cloud.google.com/sql/docs)
- [Firebase Cloud Messaging](https://firebase.google.com/docs/cloud-messaging)
- [Google Cloud Security Best Practices](https://cloud.google.com/architecture/best-practices-for-security)
- [HIPAA Compliance on GCP](https://cloud.google.com/security/compliance/hipaa)

---

Generated: May 13, 2026
Status: Ready for implementation
