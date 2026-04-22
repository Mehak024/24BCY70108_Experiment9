# CI/CD Pipeline — React App with GitHub Actions

End-to-end automation from code commit to production deployment using GitHub Actions, Docker, and GitHub Container Registry (GHCR).

---

## What this pipeline does

| Trigger | Jobs that run |
|---|---|
| Pull request to `main` | Test + Lint only |
| Push to `main` | Test → Docker Build → Push to GHCR → Slack notify |

### Image tags produced on every merge to main
- `ghcr.io/<owner>/<repo>:latest`
- `ghcr.io/<owner>/<repo>:sha-<short-sha>` (e.g. `sha-a1b2c3d`)

---

## Setup checklist

### 1. Repository secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret name | Value |
|---|---|
| `SLACK_WEBHOOK_URL` | Your Slack Incoming Webhook URL |

> `GITHUB_TOKEN` is **automatic** — no setup needed for GHCR.

### 2. Enable GitHub Packages (GHCR)

GHCR is enabled by default on all GitHub repos. Ensure your workflow has `packages: write` permission (already set in the workflow file).

### 3. Add scripts to package.json

Your `package.json` must expose these scripts:

```json
{
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "lint": "eslint src --ext .js,.jsx,.ts,.tsx"
  }
}
```

### 4. Place workflow file

```
your-repo/
├── .github/
│   └── workflows/
│       └── ci-cd.yml       ← the workflow file
├── Dockerfile               ← multi-stage build
└── src/
```

### 5. Branch protection (recommended)

Go to **Settings → Branches → Add rule** for `main`:
- ✅ Require status checks to pass: `Test & Lint`
- ✅ Require branches to be up to date before merging

---

## Slack webhook setup

1. Go to https://api.slack.com/apps → Create New App → From scratch
2. Enable **Incoming Webhooks** → Add to Workspace → Pick a channel
3. Copy the webhook URL → add it as `SLACK_WEBHOOK_URL` secret

---

## Local Docker test

```bash
# Build
docker build -t my-react-app .

# Run locally
docker run -p 8080:80 my-react-app

# Open http://localhost:8080
```

---

## Pipeline overview

```
[PR opened]
     │
     ▼
 Test & Lint ──✗──▶ Block merge
     │ ✓
     │    [push to main]
     │         │
     ▼         ▼
 (skipped) Test & Lint
                │ ✓
                ▼
         Docker Build
         (cached layers)
                │ ✓
                ▼
      Push to ghcr.io
      :latest + :sha-xxxxx
                │ ✓
                ▼
       Slack notification
```

---

## Files

| File | Purpose |
|---|---|
| `.github/workflows/ci-cd.yml` | Full pipeline definition |
| `Dockerfile` | Multi-stage React build (Node 18 → Nginx) |
