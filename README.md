# AWS Grocery Store Deployment Automation

## 1. Overwiev
This project extends the “AWS_grocery” application by Alejandro Roman Ibanez from Masterschool (many thanks for allowing me to use his work!). The app is a grocery store with an integrated database.
Using Terraform and Shell scripts, this configuration automatically sets up the entire AWS infrastructure required for the Grocery Store web application.
To deploy, the user simply runs the deploy.sh script in the backend directory. After signing in to AWS and providing the database password and JWT secret key, the deployment process runs fully automatically.
Prerequisites and a detailed explanation of the created infrastructure and deployment process follows below.

Developer Push        ──▶  ECR (App)
      │                     │
      │                     └─▶  docker build/push
      ▼
ALB (HTTP)  ◀── Internet Traffic ──▶  ECS Service (App Tasks)
      │
      ▼
TargetGroup
      │
      ▼
ECS Seed Task ──▶ Downloads SQL from S3
      │
      ▼
Amazon RDS (PostgreSQL)
      │
      ▼
Amazon S3 (SQL dump storage)


## 2. Prerequisites
The application is deployed in the AWS region eu-central-1 (Frankfurt).
Docker Desktop must be installed and running on your system.
The default database user is set to postgres.
If you use a different username, make sure to update the variable both in the Shell script (variables section) and in the variables.tf file.


## 3. Components:
 
### 3.1 Terraform Configuration
Terraform code is organized into multiple .tf files for modularity:

main.tf:
Defines the VPC, subnets, Internet gateway, route tables, security groups, and RDS PostgreSQL instance.
RDS is configured with user-defined database name, username, and password.
Security groups control traffic between ALB, ECS, and RDS.

alb.tf:
Configures an Application Load Balancer, target groups, and listeners.
Exposes HTTP (port 80) to the public internet.
Routes requests to ECS tasks on port 5000.

ecs.tf:
Defines ECS cluster, task definitions, services, and CloudWatch log groups.
App Task: Runs the GroceryMate application container.
Seed Task: Runs a one-off container that downloads SQL from S3 and applies it to RDS.
ECS services are integrated with the ALB.

ecr.tf:
Creates ECR repositories for the app and seed images.

s3.tf:
Provisions an S3 bucket (with randomized suffix to avoid collisions).
Uploads the SQL seed file as an S3 object.

secrets.tf:
Stores sensitive data in AWS Secrets Manager:
Database password
JWT secret for the app

roles.tf:
IAM roles for ECS tasks and execution:
Execution role: pull images from ECR, write logs to CloudWatch.
Task role: retrieve secrets and access S3 seed files.
variables.tf
Defines project variables: AWS region, app/seed repo names, DB settings, etc.
outputs.tf
Exposes useful values after deployment:
ALB DNS name
RDS endpoint
Database credentials (optional, but not recommended to expose in plaintext)

## 3.2 Docker Containers
App Image (Dockerfile)
Based on python:3.12-slim.
Copies application source code into /app.
Exposes port 5000.
Runs python run.py when started.
Seed Image (Dockerfile.seed)
Installs awscli and psql.
Copies entrypoint.sh into container.
Entrypoint downloads a SQL file from S3 and executes it against RDS using environment variables for DB connection.

## 3.3 Shell Scripts
deploy.sh
Automates end-to-end deployment:
Initializes and applies Terraform (provisioning infra).
Builds and tags Docker images (app + seed).
Logs into ECR and pushes images.
Updates ECS services to use the latest images.
Optionally triggers the seed task to populate the database.
entrypoint.sh (Seed)
Reads environment variables (DB host, user, password, S3 bucket/key).
Downloads SQL dump from S3.
Executes SQL commands against the RDS database.
Deployment Workflow
Infrastructure Deployment
Run Terraform to create/update AWS resources:
cd terraform
terraform init
terraform apply -auto-approve
Build & Push Images

App:
docker build -t my-python-app:latest -f Dockerfile .
docker tag my-python-app:latest <account_id>.dkr.ecr.<region>.amazonaws.com/my-python-app:latest
docker push <account_id>.dkr.ecr.<region>.amazonaws.com/my-python-app:latest

Seed:
docker build -t gm-seed:latest -f Dockerfile.seed ./seed
docker tag gm-seed:latest <account_id>.dkr.ecr.<region>.amazonaws.com/gm-seed:latest
docker push <account_id>.dkr.ecr.<region>.amazonaws.com/gm-seed:latest
Update ECS Service
Force a new deployment of the ECS service to pull the new app image:
aws ecs update-service \
  --cluster grocerymate-cluster \
  --service grocerymate-service \
  --force-new-deployment
Seed Database (optional)
Trigger a one-off ECS task using the seed image:
aws ecs run-task \
  --cluster grocerymate-cluster \
  --task-definition gm-seed-task \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[...],securityGroups=[...],assignPublicIp=ENABLED}"


## 4. Test Application:
Access the ALB DNS name:
curl http://<alb_dns_name>/health
Security Considerations
RDS Accessibility: Current setup uses a public RDS with restricted IP access.
Recommended: place RDS in private subnets and allow access only from ECS tasks.
Secrets Management:
Prefer injecting database credentials from AWS Secrets Manager into ECS tasks.
Avoid passing passwords as plain Terraform variables.
Terraform State:
Do not commit terraform.tfstate to version control.
Use a remote backend (S3 + DynamoDB) for state storage and locking.
HTTPS:
ALB should terminate TLS using an ACM certificate.
Redirect HTTP (80) to HTTPS (443).
Improvements / Future Work
Add CloudWatch Alarms (RDS CPU/storage, ECS task health, ALB errors).
Add Auto Scaling for ECS tasks based on CPU/memory.
Use private subnets for ECS and RDS, public subnets only for ALB.
Implement CI/CD pipeline (e.g., GitHub Actions, CodePipeline) to automate deploy.sh steps.
Harden containers with non-root users, health checks, and smaller base images.


## 5. Additional Information
In a future version, the deployment region could be made selectable by the user.
This could be achieved by integrating a Python script that is called within the Shell deployment script, allowing deployments to any region.


## 6. Troubleshooting
If the deployment fails due to incorrect input (e.g., wrong database credentials or DB username), run the following command inside the Terraform directory:
"terraform destroy"
If your SSH session has expired, log in again before executing the command.
After destroying the infrastructure, make sure to manually delete any remaining S3 bucket contents via the AWS Console to avoid leftover resources.

