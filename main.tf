##############################################################
# main.tf — Root configuration
# Wires together all child modules and configures the
# AWS provider + Terraform backend.
##############################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state — replace bucket/key with your own values
  backend "s3" {
    bucket         = "my-tf-state-bucket"
    key            = "prod/ecs-app/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# ─────────────────────────────────────────────────────────────
# Data sources
# ─────────────────────────────────────────────────────────────

data "aws_availability_zones" "available" {
  state = "available"
}

# ─────────────────────────────────────────────────────────────
# Modules
# ─────────────────────────────────────────────────────────────

module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets     = var.public_subnet_cidrs
  private_subnets    = var.private_subnet_cidrs
}

module "security_groups" {
  source = "./modules/security_groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  app_port     = var.container_port
}

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
}

module "iam" {
  source = "./modules/iam"

  project_name    = var.project_name
  environment     = var.environment
  aws_region      = var.aws_region
  aws_account_id  = data.aws_caller_identity.current.account_id
  ecr_repo_arn    = module.ecr.repository_arn
}

data "aws_caller_identity" "current" {}

module "alb" {
  source = "./modules/alb"

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security_groups.alb_sg_id
  container_port    = var.container_port
  health_check_path = var.health_check_path
}

module "ecs" {
  source = "./modules/ecs"

  project_name         = var.project_name
  environment          = var.environment
  aws_region           = var.aws_region
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  ecs_sg_id            = module.security_groups.ecs_sg_id
  target_group_arn     = module.alb.target_group_arn
  ecr_repository_url   = module.ecr.repository_url
  image_tag            = var.image_tag
  container_port       = var.container_port
  container_cpu        = var.container_cpu
  container_memory     = var.container_memory
  desired_count        = var.desired_count
  min_capacity         = var.min_capacity
  max_capacity         = var.max_capacity
  cpu_scale_out_threshold = var.cpu_scale_out_threshold
  cpu_scale_in_threshold  = var.cpu_scale_in_threshold
  execution_role_arn   = module.iam.ecs_execution_role_arn
  task_role_arn        = module.iam.ecs_task_role_arn
  environment_variables = var.environment_variables
}
