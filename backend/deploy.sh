#!/bin/bash
set -e  # Exit on error

# ===== CONFIG =====
AWS_REGION="eu-central-1"
AWS_PROFILE="grocerymate-admin"
REPO_NAME="my-python-app"
IMAGE_TAG="latest"
SEED_REPO="gm-seed"
SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"    # …/backend
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"          # …/ (Repo-Root)
BACKEND_DIR="$SCRIPT_DIR"
SEED_DIR="$BACKEND_DIR/seed"
TERRAFORM_DIR="$ROOT_DIR/terraform"

echo "Welcome to the Deployment of the Grocery Store!"
sleep 3

# ===== AWS SSO Login =====
echo "Logging in to AWS SSO..."
aws sso login --profile "$AWS_PROFILE"

# # ===== Getting Account ID and Creating ECR url=====
ACCOUNT_ID=$(aws sts get-caller-identity \
  --query "Account" \
  --output text \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION")
ECR_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}"

# ===== ECR Login =====
echo "Authenticating Docker with ECR..."
aws ecr get-login-password --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# --- ECR Login ---
echo "🔑 Authenticating Docker with ECR ($AWS_REGION)…"
aws ecr get-login-password --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  | docker login --username AWS --password-stdin \
    "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "✅ ECR Login successful."
# ===== Docker Build & Push (App) =====
echo "Building and pushing app image..."
if ! aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
  echo "Creating ECR repository $REPO_NAME..."
  aws ecr create-repository --repository-name "$REPO_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE"
fi
docker buildx build --platform linux/amd64 -t "$REPO_NAME:$IMAGE_TAG" --load .
docker tag "$REPO_NAME:$IMAGE_TAG" "$ECR_URL:$IMAGE_TAG"
docker push "$ECR_URL:$IMAGE_TAG"

# ===== Terraform Deploy =====
#!/bin/bash

echo "Applying Terraform configuration..."
cd "$TERRAFORM_DIR"
export AWS_PROFILE="$AWS_PROFILE"
terraform init -input=false
terraform apply -auto-approve

DB_USER="$(terraform -chdir="$TERRAFORM_DIR" output -raw db_user)"
DB_NAME="$(terraform -chdir="$TERRAFORM_DIR" output -raw db_name)"
DB_HOST="$(terraform -chdir="$TERRAFORM_DIR" output -raw db_address)"
DB_PASSWORD="$(terraform -chdir="$TERRAFORM_DIR" output -raw db_password)"
S3_BUCKET="$(terraform -chdir="$TERRAFORM_DIR" output -raw seed_bucket)"
S3_KEY="$(terraform -chdir="$TERRAFORM_DIR" output -raw seed_key)"
JWT_SECRET_KEY="$(terraform -chdir="$TERRAFORM_DIR" output -raw jwt_secret_value)"

# ===== Building seeder image =====
echo "🚀 Building Seeder Docker image…"
docker build -t gm-seed:latest -f "$SEED_DIR/Dockerfile.seed" "$SEED_DIR"

echo "Running seeder container…"
docker run --rm \
  -e S3_BUCKET="$S3_BUCKET" \
  -e S3_KEY="$S3_KEY" \
  -e POSTGRES_HOST="$DB_HOST" \
  -e POSTGRES_DB="$DB_NAME" \
  -e POSTGRES_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e AWS_REGION="${AWS_REGION}" \
  -e AWS_PROFILE="${AWS_PROFILE}" \
  -v "$HOME/.aws:/root/.aws:ro" \
  gm-seed:latest

# ===== Output application url =====
echo ""
echo "Deployment complete."
echo "Application is available at:"
terraform output -raw alb_dns_name
echo ""

# ===== Pushing seeder image to ECR =====
aws ecr get-login-password --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

if ! aws ecr describe-repositories --repository-names "gm-seed" --region "$AWS_REGION" --profile "$AWS_PROFILE" >/dev/null 2>&1; then
  echo "📦 Creating ECR repository gm-seed..."
  aws ecr create-repository --repository-name "gm-seed" --region "$AWS_REGION" --profile "$AWS_PROFILE"
fi

docker tag gm-seed:latest "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/gm-seed:latest"
docker push "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/gm-seed:latest"


