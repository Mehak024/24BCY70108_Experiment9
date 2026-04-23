##############################################################
# terraform.tfvars — Override defaults for your environment.
# DO NOT commit secrets here; use environment variables or
# AWS Secrets Manager instead.
##############################################################

aws_region   = "us-east-1"
project_name = "myapp"
environment  = "prod"

# Networking
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]

# Container
container_port   = 3000
container_cpu    = 256
container_memory = 512
image_tag        = "latest"

# ECS scaling
desired_count           = 2
min_capacity            = 2
max_capacity            = 4
cpu_scale_out_threshold = 70
cpu_scale_in_threshold  = 30

# ALB
health_check_path = "/health"

# Runtime env vars (non-secret only; use Secrets Manager for secrets)
environment_variables = {
  NODE_ENV = "production"
  LOG_LEVEL = "info"
}
