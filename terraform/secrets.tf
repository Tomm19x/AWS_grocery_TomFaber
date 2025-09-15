# JWT Secret im AWS Secrets Manager
resource "aws_secretsmanager_secret" "jwt_secret" {
  name = "jwt_secret_key222"
}

resource "aws_secretsmanager_secret_version" "jwt_secret_value" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = var.jwt_secret_key
}

# DB Passwort im AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name = "grocerymate_db_pw222"
}

resource "aws_secretsmanager_secret_version" "db_password_value" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}
