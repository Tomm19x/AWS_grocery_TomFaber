variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_1_cidr" {
  description = "CIDR block for public subnet 1"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_2_cidr" {
  description = "CIDR block for public subnet 2"
  type        = string
  default     = "10.0.2.0/24"
}

variable "app_port" {
  description = "Port the application listens on inside the container"
  type        = number
  default     = 5000
}

variable "desired_count" {
  description = "Number of ECS tasks to run"
  type        = number
  default     = 1
}

variable "docker_image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "log_group_name" {
  description = "Name of the CloudWatch Log Group for ECS logs"
  type        = string
  default     = "/ecs/my-python-app"
}


variable "jwt_secret_key" {
  description = "JWT secret key for signing tokens"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Postgres database password"
  type        = string
  sensitive   = true
}

variable "task_cpu" {
  description = "ECS task CPU units"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "ECS task memory in MiB"
  type        = string
  default     = "512"
}

variable "db_name" {
  description = "Postgres database name"
  type        = string
  default     = "grocerymate"
}

variable "db_user" {
  description = "Postgres database user"
  type        = string
  default     = "postgres"
}

variable "seed_ecr_repo" {
  type = string
  default ="gm-seed"
}

variable "seed_bucket_prefix" {
  type = string
  default= "grocerymate-seed"
}