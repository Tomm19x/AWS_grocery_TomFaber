output "alb_dns_name" {
  description = "Public DNS name of the application Load Balancer"
  value       = aws_lb.app_alb.dns_name
}

output "db_address" {
  description = "RDS endpoint"
  value       = aws_db_instance.grocerymate_db.address
}

output "db_name" {
  description = "RDS database name"
  value       = aws_db_instance.grocerymate_db.db_name
}

output "db_user" {
  description = "RDS database username"
  value       = aws_db_instance.grocerymate_db.username
}

output "db_password" {
  description = "RDS database password from Secrets Manager"
  value       = aws_secretsmanager_secret_version.db_password_value.secret_string
  sensitive   = true
}

output "jwt_secret_value" {
  description = "RDS database password from Secrets Manager"
  value       = aws_secretsmanager_secret_version.jwt_secret_value.secret_string
  sensitive   = true
}

output "seed_bucket" {
  description = "S3 bucket for seed data"
  value       = aws_s3_bucket.seed.bucket
}

output "seed_key" {
  description = "S3 key for seed SQL file"
  value       = aws_s3_object.seed_sql.key
}
