# Production AWS ECS Deployment

> Full-stack application on AWS using Terraform, Docker, ECS Fargate, ALB, Auto Scaling, and GitHub Actions CI/CD.

---

## Architecture Overview

```
Internet
   │
   ▼
Application Load Balancer (public subnets, 2 AZs)
   │  forwards :80
   ▼
ECS Fargate Tasks (private subnets, 2 AZs)
   │  2–4 tasks, auto-scaled on CPU
   │
   ├── Pull images from ECR
   ├── Write logs to CloudWatch
   └── Outbound via NAT Gateway
```

**Key concepts:**

| Service | Role |
|---------|------|
| **VPC** | Isolated network. Public subnets host the ALB; private subnets host tasks (no direct internet exposure). |
| **ALB** | Layer-7 load balancer. Distributes HTTP requests across healthy ECS tasks; performs health checks. |
| **ECS Fargate** | Serverless container runtime — AWS manages the underlying EC2 fleet. You only define CPU/memory. |
| **ECR** | Private Docker registry in your AWS account. Images are scanned for CVEs on push. |
| **Auto Scaling** | Target-tracking policy keeps average CPU at 70%. Scales out fast (60 s cooldown), scales in slowly (300 s). |
| **IAM (OIDC)** | GitHub Actions assumes an IAM role via OIDC — no static AWS keys stored as secrets. |
| **CloudWatch** | Container logs (`/ecs/<app>`) and CPU alarms are created automatically. |

---

## Repository Structure

```
.
├── app/
│   └── Dockerfile                   # Multi-stage production image
├── terraform/
│   ├── main.tf                      # Root: wires all modules together
│   ├── variables.tf                 # All input variables with validation
│   ├── outputs.tf                   # ALB DNS, ECR URL, cluster/service names
│   ├── terraform.tfvars             # Your environment values (no secrets!)
│   ├── github_actions_oidc_role.tf  # IAM role for CI/CD (OIDC, no keys)
│   └── modules/
│       ├── vpc/                     # VPC, subnets, IGW, NAT GWs, route tables
│       ├── security_groups/         # ALB SG + ECS SG (least-privilege)
│       ├── ecr/                     # ECR repo with lifecycle policy
│       ├── iam/                     # Execution role + task role
│       ├── alb/                     # ALB, target group, HTTP listener
│       └── ecs/                     # Cluster, task def, service, auto scaling
└── .github/
    └── workflows/
        └── deploy.yml               # CI/CD: test → build → push → rolling deploy
```

---

## Prerequisites

```bash
# Install tools
brew install terraform awscli docker

# Verify versions
terraform version   # >= 1.6.0
aws --version       # >= 2.x
docker version

# Configure AWS credentials (admin for initial bootstrap)
aws configure
# or: export AWS_PROFILE=my-profile
```

---

## Step 1 — Bootstrap State Backend

Terraform needs an S3 bucket + DynamoDB table for remote state *before* running `init`.

```bash
# Create S3 bucket (replace BUCKET_NAME and REGION)
aws s3api create-bucket \
  --bucket my-tf-state-bucket \
  --region us-east-1 \
  --create-bucket-configuration LocationConstraint=us-east-1

# Enable versioning (lets you roll back state)
aws s3api put-bucket-versioning \
  --bucket my-tf-state-bucket \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket my-tf-state-bucket \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

echo "State backend ready."
```

---

## Step 2 — Deploy Infrastructure with Terraform

```bash
cd terraform

# 1. Initialise — downloads providers, configures backend
terraform init

# 2. Validate syntax
terraform validate

# 3. Preview changes (always review before applying!)
terraform plan -var-file="terraform.tfvars"

# 4. Apply — type "yes" when prompted
terraform apply -var-file="terraform.tfvars"

# 5. Note the outputs — you will need these for GitHub Secrets
terraform output
```

Expected outputs:
```
alb_dns_name        = "myapp-prod-alb-1234567890.us-east-1.elb.amazonaws.com"
ecr_repository_url  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp-prod-app"
ecs_cluster_name    = "myapp-prod-cluster"
ecs_service_name    = "myapp-prod-service"
github_actions_role_arn = "arn:aws:iam::123456789012:role/myapp-prod-github-actions"
```

---

## Step 3 — Configure GitHub Actions OIDC

```bash
# Register GitHub as an OIDC provider in your AWS account (once per account)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
  --client-id-list sts.amazonaws.com
```

Then add these **GitHub Secrets** (`Settings → Secrets and variables → Actions`):

| Secret | Value |
|--------|-------|
| `AWS_ACCOUNT_ID` | Your 12-digit account ID |
| `AWS_REGION` | e.g. `us-east-1` |
| `AWS_ROLE_ARN` | `github_actions_role_arn` output |
| `ECR_REPOSITORY` | `myapp-prod-app` |
| `ECS_CLUSTER_NAME` | `ecs_cluster_name` output |
| `ECS_SERVICE_NAME` | `ecs_service_name` output |
| `ECS_TASK_FAMILY` | `myapp-prod-task` |
| `CONTAINER_NAME` | `myapp-prod-app` |

---

## Step 4 — First Docker Push (Manual Bootstrap)

```bash
# Log in to ECR
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
    $(terraform output -raw ecr_repository_url | cut -d/ -f1)

ECR_URL=$(terraform output -raw ecr_repository_url)

# Build and push
docker build -t $ECR_URL:latest ./app
docker push $ECR_URL:latest

# Force ECS to pull the new image
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw ecs_service_name) \
  --force-new-deployment
```

---

## Step 5 — Verify Deployment

```bash
# Check ECS service status
aws ecs describe-services \
  --cluster $(cd terraform && terraform output -raw ecs_cluster_name) \
  --services $(cd terraform && terraform output -raw ecs_service_name) \
  --query "services[0].{Status:status,Running:runningCount,Desired:desiredCount,Pending:pendingCount}"

# Hit the health check endpoint
curl http://$(cd terraform && terraform output -raw alb_dns_name)/health

# Tail container logs
aws logs tail /ecs/myapp-prod --follow
```

---

## CI/CD Workflow — What Happens on `git push main`

```
Push to main
     │
     ▼
[test] npm test + lint
     │
     ▼
[build] docker build (multi-stage, with layer cache)
     │
     ▼
[push] docker push <ECR>:<git-sha>  +  :latest tag
     │
     ▼
[deploy] aws ecs update-service (rolling, 100% min healthy)
     │
     ▼
[smoke] curl ALB /health — 3 retries, fail pipeline if unhealthy
```

Rolling deployment guarantees zero downtime:
- `deployment_minimum_healthy_percent = 100` — old tasks stay up until new ones are healthy
- `deployment_maximum_percent = 200` — ECS can temporarily double capacity during rollout
- `deployment_circuit_breaker.rollback = true` — automatic rollback if new tasks fail

---

## Auto Scaling Behaviour

| Metric | Threshold | Action |
|--------|-----------|--------|
| CPU > 70% for 2 min | Scale out | +1 task (up to 4) |
| CPU < 30% for 3 min | Scale in | -1 task (floor 2) |
| Memory > 80% for 2 min | Scale out | +1 task (up to 4) |

Scale-out cooldown: 60 s (respond quickly to spikes).
Scale-in cooldown: 300 s (avoid thrashing).

---

## Updating Infrastructure

```bash
cd terraform

# Preview changes
terraform plan -var-file="terraform.tfvars"

# Apply specific changes only
terraform apply -target=module.ecs -var-file="terraform.tfvars"

# Destroy everything (careful in production!)
terraform destroy -var-file="terraform.tfvars"
```

---

## Security Notes

- ECS tasks run in **private subnets** — no public IPs, no direct internet exposure.
- ALB is the only ingress point; ECS SG only accepts traffic from the ALB SG.
- IAM roles follow **least privilege** — execution role can only pull ECR images and write logs; task role has only what the app needs.
- **No hardcoded credentials** anywhere. CI/CD uses OIDC; containers use IAM task roles.
- Secrets go in **AWS Secrets Manager** and are injected at task start — never in environment variable plaintext or Docker images.
- ECR images are **scanned on push** for CVEs.
- Terraform state is **encrypted at rest** and **version-controlled** in S3.

---

## Cost Estimate (us-east-1, 2 tasks × 256 CPU / 512 MB)

| Resource | Estimated monthly cost |
|----------|----------------------|
| 2× Fargate tasks | ~$12 |
| 2× NAT Gateways | ~$65 |
| ALB | ~$18 |
| ECR storage (10 images) | ~$1 |
| CloudWatch logs | ~$2 |
| **Total** | **~$98/month** |

> NAT Gateways are the dominant cost. For non-production, consider a single NAT GW or VPC endpoints for ECR/CloudWatch.
