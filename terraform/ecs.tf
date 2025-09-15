# CloudWatch Log Group für den Task (muss existieren, bevor Logs geschrieben werden)
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = var.log_group_name
  retention_in_days = 7
}

# ECS-Cluster
resource "aws_ecs_cluster" "app_cluster" {
  name = "my-python-cluster"
}

resource "aws_cloudwatch_log_group" "db_seed" {
  name              = "/ecs/db-seed"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "app_task" {
  family                   = "my-python-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
  name       = "my-python-app",
  image      = "${data.aws_ecr_repository.app_repo.repository_url}:${var.docker_image_tag}",
  essential  = true,

  portMappings = [{ containerPort = 5000, protocol = "tcp" }],

  environment = [
    { name = "POSTGRES_HOST", value = aws_db_instance.grocerymate_db.address },
    { name = "POSTGRES_DB",   value = var.db_name },
    { name = "POSTGRES_USER", value = var.db_user },
  ],
  secrets = [
    { name = "POSTGRES_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn }
  ],

  logConfiguration = {
    logDriver = "awslogs",
    options = {
      awslogs-group         = var.log_group_name,
      awslogs-region        = var.aws_region,
      awslogs-stream-prefix = "ecs"
    }
  }
}])
}

# Service (hinter ALB)
resource "aws_ecs_service" "app_service" {
 name            = "my-python-service"
 cluster         = aws_ecs_cluster.app_cluster.id
 task_definition = aws_ecs_task_definition.app_task.arn
 launch_type     = "FARGATE"
 desired_count   = var.desired_count

 network_configuration {
   subnets          = [aws_subnet.public1.id, aws_subnet.public2.id]
   security_groups  = [aws_security_group.ecs_service.id]
   assign_public_ip = true
 }

 load_balancer {
   target_group_arn = aws_lb_target_group.app_tg.arn
   container_name   = "my-python-app"
   container_port   = var.app_port
 }

 depends_on = [
   aws_lb_listener.http,
   aws_cloudwatch_log_group.ecs_log_group
 ]
}

resource "aws_ecs_task_definition" "db_seed" {
  family                   = "db-seed-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "db-seeder",
    image = "${aws_ecr_repository.seed_repo.repository_url}:latest"
    essential = true,
    environment = [
      { name = "S3_BUCKET",      value = aws_s3_bucket.seed.bucket },
      { name = "S3_KEY",         value = aws_s3_object.seed_sql.key },
      { name = "POSTGRES_HOST",  value = aws_db_instance.grocerymate_db.address },
      { name = "POSTGRES_DB",    value = var.db_name },
      { name = "POSTGRES_USER",  value = var.db_user }
    ],
    secrets = [
  {
    name      = "DB_PASSWORD"
    valueFrom = aws_secretsmanager_secret.db_password.arn
  }
]
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        awslogs-group         = "/ecs/db-seed",
        awslogs-region        = var.aws_region,
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}


