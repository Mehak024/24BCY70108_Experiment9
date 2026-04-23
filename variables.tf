##############################################################
# variables.tf — All input variables with descriptions
#                and sensible defaults
##############################################################

# ─── General ────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix all resource names (lowercase, no spaces)"
  type        = string
  default     = "myapp"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric with dashes only."
  }
}

variable "environment" {
  description = "Deployment environment (prod | staging | dev)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment must be prod, staging, or dev."
  }
}

# ─── Networking ─────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

# ─── Container ──────────────────────────────────────────────

variable "container_port" {
  description = "Port the application container listens on"
  type        = number
  default     = 3000
}

variable "container_cpu" {
  description = "Fargate task CPU units (256 | 512 | 1024 | 2048 | 4096)"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Fargate task memory in MiB (must be compatible with CPU)"
  type        = number
  default     = 512
}

variable "image_tag" {
  description = "Docker image tag to deploy — typically set by CI/CD pipeline"
  type        = string
  default     = "latest"
}

variable "environment_variables" {
  description = "Map of environment variables injected into the container at runtime"
  type        = map(string)
  default     = {}
  sensitive   = true
}

# ─── ECS service ────────────────────────────────────────────

variable "desired_count" {
  description = "Initial number of ECS tasks to run"
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum number of ECS tasks (Auto Scaling floor)"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks (Auto Scaling ceiling)"
  type        = number
  default     = 4
}

# ─── Auto Scaling ────────────────────────────────────────────

variable "cpu_scale_out_threshold" {
  description = "CPU % that triggers scale-out (add tasks)"
  type        = number
  default     = 70
}

variable "cpu_scale_in_threshold" {
  description = "CPU % that triggers scale-in (remove tasks)"
  type        = number
  default     = 30
}

# ─── Health check ────────────────────────────────────────────

variable "health_check_path" {
  description = "HTTP path the ALB uses for target health checks"
  type        = string
  default     = "/health"
}
