# NAVI marketing site

This is a standalone static site for the Firebase Hosting site `navi-mentalhealth`.

Recommended final setup:
- `navi-mentalhealth.com` -> this marketing site
- `www.navi-mentalhealth.com` -> this marketing site
- `app.navi-mentalhealth.com` -> your existing NAVI web app

## Preview locally
From this folder:
`python -m http.server 8080`

Then open `http://localhost:8080`.

## Deploy to the new Firebase Hosting site
From your Firebase project folder:

1. Associate a deploy target:
`firebase target:apply hosting marketing navi-mentalhealth`

2. Merge this into your existing `firebase.json` rather than replacing it blindly:

{
  "hosting": [
    {
      "target": "marketing",
      "public": "marketing_site",
      "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
      "cleanUrls": true
    }
  ]
}

3. Deploy only this site:
`firebase deploy --only hosting:marketing`

4. Confirm it works at:
`https://navi-mentalhealth.web.app`

Only after that should you move your custom domain.
