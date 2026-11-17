#!/usr/bin/env bash
# Lambda function from the container image, exposed with a Function URL.
cd "$(dirname "$0")/.." && source infra/env.sh
FN="$NAME"; ROLE="$NAME-lambda"; MEMORY="${MEMORY:-1024}"

log "IAM role $ROLE"
if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE" --tags "$TAGS" --assume-role-policy-document \
    '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "$ROLE" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  sleep 10 # new roles take a few seconds before Lambda can assume them
fi
aws iam put-role-policy --role-name "$ROLE" --policy-name dynamodb-read --policy-document \
  "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"dynamodb:GetItem\",\"Resource\":\"arn:aws:dynamodb:$AWS_REGION:$ACCOUNT:table/$TABLE\"}]}"

ENV="Variables={RUNTIME_NAME=lambda,TABLE_NAME=$TABLE,APP_REGION=$AWS_REGION}"
log "Function $FN ($MEMORY MB, arm64)"
if aws lambda get-function --function-name "$FN" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FN" --image-uri "$REPO_URI:$IMAGE_TAG" >/dev/null
  aws lambda wait function-updated-v2 --function-name "$FN"
  aws lambda update-function-configuration --function-name "$FN" --memory-size "$MEMORY" --environment "$ENV" >/dev/null
else
  aws lambda create-function --function-name "$FN" --package-type Image \
    --code ImageUri="$REPO_URI:$IMAGE_TAG" --architectures arm64 \
    --role "arn:aws:iam::$ACCOUNT:role/$ROLE" --memory-size "$MEMORY" --timeout 30 \
    --environment "$ENV" --tags "$TAGS_KV" >/dev/null
fi
aws lambda wait function-active-v2 --function-name "$FN"
aws lambda wait function-updated-v2 --function-name "$FN"

log "Function URL (public, auth NONE)"
if ! aws lambda get-function-url-config --function-name "$FN" >/dev/null 2>&1; then
  aws lambda create-function-url-config --function-name "$FN" --auth-type NONE >/dev/null
  # A public Function URL needs both permissions.
  aws lambda add-permission --function-name "$FN" --statement-id public-url \
    --action lambda:InvokeFunctionUrl --principal '*' --function-url-auth-type NONE >/dev/null
  aws lambda add-permission --function-name "$FN" --statement-id public-invoke \
    --action lambda:InvokeFunction --principal '*' --invoked-via-function-url >/dev/null
fi
URL=$(aws lambda get-function-url-config --function-name "$FN" --query FunctionUrl --output text)
echo "LAMBDA_URL=${URL%/}"
