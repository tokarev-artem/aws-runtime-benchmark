#!/usr/bin/env bash
# DynamoDB table with one item, ECR repository, and the container image.
cd "$(dirname "$0")/.." && source infra/env.sh

log "DynamoDB table $TABLE (on-demand)"
if ! aws dynamodb describe-table --table-name "$TABLE" >/dev/null 2>&1; then
  aws dynamodb create-table --table-name "$TABLE" \
    --attribute-definitions AttributeName=pk,AttributeType=S \
    --key-schema AttributeName=pk,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST --tags "$TAGS" >/dev/null
  aws dynamodb wait table-exists --table-name "$TABLE"
fi
aws dynamodb put-item --table-name "$TABLE" \
  --item '{"pk":{"S":"greeting"},"message":{"S":"Hello from DynamoDB"}}'

log "ECR repository $NAME (immutable tags, scan on push)"
aws ecr describe-repositories --repository-names "$NAME" >/dev/null 2>&1 ||
  aws ecr create-repository --repository-name "$NAME" \
    --image-tag-mutability IMMUTABLE \
    --image-scanning-configuration scanOnPush=true --tags "$TAGS" >/dev/null

log "Build and push $REPO_URI:$IMAGE_TAG (linux/arm64)"
if aws ecr describe-images --repository-name "$NAME" --image-ids imageTag="$IMAGE_TAG" >/dev/null 2>&1; then
  echo "tag $IMAGE_TAG already exists, skipping build"
else
  aws ecr get-login-password | docker login --username AWS --password-stdin "${REPO_URI%%/*}"
  # --provenance=false: Lambda rejects the multi-manifest image index that buildx creates by default.
  docker buildx build --platform linux/arm64 --provenance=false -t "$REPO_URI:$IMAGE_TAG" --push .
fi
echo "IMAGE=$REPO_URI:$IMAGE_TAG"
