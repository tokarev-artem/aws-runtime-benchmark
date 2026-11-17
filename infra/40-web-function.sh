#!/usr/bin/env bash
# Lambda Web Function from the same Next.js standalone build that is in the container image.
# Needs AWS CLI v2 with the "aws lambda-web" commands (2.40 or later).
cd "$(dirname "$0")/.." && source infra/env.sh
FN="$NAME-web"; ROLE="$NAME-web"; OUT="build/web-function"

log "Copy the standalone app out of image $IMAGE_TAG (linux/arm64, identical files)"
rm -rf "$OUT" && mkdir -p "$OUT"
docker image inspect "$REPO_URI:$IMAGE_TAG" >/dev/null 2>&1 || docker pull -q --platform linux/arm64 "$REPO_URI:$IMAGE_TAG"
cid=$(docker create --platform linux/arm64 "$REPO_URI:$IMAGE_TAG")
docker cp "$cid:/app/." "$OUT/" && docker rm "$cid" >/dev/null
rm -f "$OUT/.next/cache"            # symlink to /tmp used by the container image
cp web-function/index.js "$OUT/index.js"

log "IAM execution role $ROLE"
if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE" --tags "$TAGS" --assume-role-policy-document \
    '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "$ROLE" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  sleep 10
fi
aws iam put-role-policy --role-name "$ROLE" --policy-name dynamodb-read --policy-document \
  "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"dynamodb:GetItem\",\"Resource\":\"arn:aws:dynamodb:$AWS_REGION:$ACCOUNT:table/$TABLE\"}]}"

log "Deploy Web Function $FN"
aws lambda-web deploy --name "$FN" --code "$OUT" --create --include-hidden-files \
  --execution-role-arn "arn:aws:iam::$ACCOUNT:role/$ROLE" \
  --env RUNTIME_NAME=lambda-web --env TABLE_NAME="$TABLE" --env APP_REGION="$AWS_REGION" \
  --env NODE_ENV=production --env NEXT_TELEMETRY_DISABLED=1 \
  --timeout-seconds 30 --endpoint-name main --auth-type ApplicationManaged \
  --tags "project=$NAME"
DOMAIN=$(aws lambda-web get-web-function-endpoint --function-name "$FN" --endpoint-name main --query domainName --output text)
echo "WEB_URL=https://$DOMAIN"
