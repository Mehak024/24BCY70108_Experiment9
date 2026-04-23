##############################################################
# github_actions_oidc_role.tf
#
# Creates the IAM role that GitHub Actions assumes via OIDC —
# no long-lived AWS access keys needed in GitHub Secrets.
#
# Place this file in your root Terraform configuration (or a
# separate "bootstrap" module run once by an admin).
##############################################################

data "aws_iam_openid_connect_provider" "github" {
  # Create this once per AWS account (not per repo):
  # aws iam create-open-id-connect-provider \
  #   --url https://token.actions.githubusercontent.com \
  #   --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
  #   --client-id-list sts.amazonaws.com
  url = "https://token.actions.githubusercontent.com"
}

locals {
  github_org  = "your-org"   # <- change to your GitHub org/user
  github_repo = "your-repo"  # <- change to your repo name
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to pushes on the main branch of this repo only
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_org}/${local.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-${var.environment}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
  tags               = { Name = "github-actions-oidc-role" }
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "deploy-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
        Resource = module.ecr.repository_arn
      },
      {
        Sid    = "ECSDeployOnly"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService",
          "ecs:DescribeTasks",
          "ecs:ListTasks"
        ]
        Resource = "*"
      },
      {
        Sid    = "PassExecutionRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          module.iam.ecs_execution_role_arn,
          module.iam.ecs_task_role_arn
        ]
      },
      {
        Sid    = "ALBDescribe"
        Effect = "Allow"
        Action = ["elasticloadbalancing:DescribeLoadBalancers"]
        Resource = "*"
      }
    ]
  })
}

output "github_actions_role_arn" {
  description = "Copy this value into the AWS_ROLE_ARN GitHub Secret"
  value       = aws_iam_role.github_actions.arn
}
