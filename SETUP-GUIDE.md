# CI/CD Pipeline — React + GitHub Actions + GHCR

Complete guide to set up, verify, and maintain the pipeline.

---

## Architecture

```
[PR opened]                          [Push to main]
     │                                     │
     ▼                                     ▼
 ┌─────────────────────────────────────────────────┐
 │              JOB: ci                            │
 │  checkout → setup-node 18 → npm ci              │
 │  → lint → test (--coverage) → upload artifact  │
 └───────────────────┬─────────────────────────────┘
         (PR stops here — no deploy on PRs)
                     │ push to main only
                     ▼
 ┌─────────────────────────────────────────────────┐
 │              JOB: cd                            │
 │  checkout → setup-buildx → login ghcr.io        │
 │  → metadata (tags) → build-push                 │
 │  Tags pushed:  :latest  :sha-<7-char>           │
 └───────────────────┬─────────────────────────────┘
                     │
          ┌──────────┴──────────┐
          ▼ (success)           ▼ (failure)
   notify-success          notify-failure
   Slack :white_check_mark:    Slack :x:
```

---

## Step-by-step setup

### 1  Create repository structure

Place files exactly here:

```
your-repo/
├── .github/
│   └── workflows/
│       └── ci-cd.yml       ← the workflow file
├── Dockerfile               ← multi-stage build
├── package.json             ← must have lint + test scripts
└── src/
```

### 2  Verify package.json scripts

The workflow calls `npm run lint` and `npm test`. Both must exist:

```json
{
  "scripts": {
    "start":  "react-scripts start",
    "build":  "react-scripts build",
    "test":   "react-scripts test",
    "lint":   "eslint src --ext .js,.jsx,.ts,.tsx --max-warnings 0"
  }
}
```

If you don't have ESLint configured yet, install it:

```bash
npm install --save-dev eslint eslint-plugin-react
npx eslint --init
```

### 3  Add GitHub Secrets

Go to your repo → **Settings → Secrets and variables → Actions → New repository secret**

| Secret name | How to get the value |
|---|---|
| `SLACK_WEBHOOK_URL` | See step 4 below |

> `GITHUB_TOKEN` is injected automatically by GitHub Actions — you do **not** add it manually.

### 4  Create Slack Incoming Webhook

1. Open https://api.slack.com/apps and click **Create New App → From scratch**
2. Name it (e.g. "GitHub CI") and pick your workspace
3. In the left sidebar choose **Incoming Webhooks → Activate**
4. Click **Add New Webhook to Workspace** → pick a channel → **Allow**
5. Copy the webhook URL (`https://hooks.slack.com/services/…`)
6. Paste it as the `SLACK_WEBHOOK_URL` secret in step 3

### 5  Enable GitHub Actions

Actions are enabled by default. If they were disabled:

Repo → **Settings → Actions → General → Allow all actions** → Save

### 6  Enable GHCR package visibility (optional)

After the first successful push, your image appears under **Packages** on your GitHub profile. By default it is private. To make it public:

GitHub profile → **Packages → your-image → Package Settings → Change visibility → Public**

---

## Verifying the pipeline

### On a pull request

1. Create a feature branch, push a commit, open a PR
2. Navigate to the PR → **Checks** tab
3. You should see `CI — Test & Lint` running
4. The CD job should **not** appear (PRs skip deployment)

### On push to main

1. Merge the PR (or push directly to main)
2. Repo → **Actions** tab → find the latest workflow run
3. Expected job sequence:

```
CI — Test & Lint       ✓  ~2 min
CD — Build & Push      ✓  ~3-4 min (faster on subsequent runs due to cache)
Notify Slack — Success ✓  ~10 sec
```

4. Check **Packages** tab on your GitHub profile for the new image
5. Check your Slack channel for the notification

### Pull the image locally to confirm

```bash
# Authenticate
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin

# Pull by latest
docker pull ghcr.io/YOUR_USERNAME/YOUR_REPO:latest

# Pull by SHA tag
docker pull ghcr.io/YOUR_USERNAME/YOUR_REPO:sha-a1b2c3d

# Run locally on port 8080
docker run -p 8080:80 ghcr.io/YOUR_USERNAME/YOUR_REPO:latest
# Open http://localhost:8080
```

---

## Troubleshooting

### "denied: permission_denied" when pushing to GHCR

The `cd` job needs `packages: write` permission. Confirm the workflow has:

```yaml
permissions:
  contents: read
  packages: write
```

If your organisation has restricted Actions permissions, also check:
Org → **Settings → Actions → General → Workflow permissions → Read and write**

### Tests pass locally but fail in CI

Add `CI: true` to the test step env (already set in the workflow). This tells Create React App to treat warnings as errors and exit with code 1 on failure.

### Slack notification not arriving

- Confirm `SLACK_WEBHOOK_URL` secret is set (no trailing space)
- Confirm `SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK` is in the `env` block
- Test the webhook manually:
  ```bash
  curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"test"}' \
    YOUR_WEBHOOK_URL
  ```

### Slow Docker builds

The first run is always slow (no cache). Subsequent pushes hit the `type=gha` cache and typically build in under 60 seconds. If cache is not being used, confirm Buildx is set up before the build step.

---

## Production hardening checklist

- [ ] Branch protection on `main`: require `CI — Test & Lint` to pass before merge
- [ ] Dependabot alerts enabled for npm and GitHub Actions
- [ ] Rotate `SLACK_WEBHOOK_URL` if it leaks
- [ ] Pin action versions to SHAs in security-sensitive repos (e.g. `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683`)
- [ ] Add `REACT_APP_*` build args if your app needs runtime config
- [ ] Set image visibility (public vs private) intentionally
