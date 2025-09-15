data "aws_ecr_repository" "app_repo" {
  name = "my-python-app"
}

resource "aws_ecr_repository" "seed_repo" {
  name = var.seed_ecr_repo
}