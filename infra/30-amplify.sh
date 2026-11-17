#!/usr/bin/env bash
# Amplify Hosting (WEB_COMPUTE). Connect the GitHub repository in the console first
# (Amplify uses its own GitHub App, not AWS CodeConnections), then run:
#   APP_ID=d123abc infra/30-amplify.sh
cd "$(dirname "$0")/.." && source infra/env.sh
: "${APP_ID:?set APP_ID to the Amplify app ID}"
BRANCH="${BRANCH:-main}"; ROLE="$NAME-amplify-compute"

log "Compute role $ROLE (what the server-side code runs as)"
if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE" --tags "$TAGS" --assume-role-policy-document \
    "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"amplify.amazonaws.com\"},\"Action\":\"sts:AssumeRole\",\"Condition\":{\"StringEquals\":{\"aws:SourceAccount\":\"$ACCOUNT\"}}}]}" >/dev/null
  sleep 10
fi
aws iam put-role-policy --role-name "$ROLE" --policy-name dynamodb-read --policy-document \
  "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"dynamodb:GetItem\",\"Resource\":\"arn:aws:dynamodb:$AWS_REGION:$ACCOUNT:table/$TABLE\"}]}"

log "App settings: platform, compute role, environment variables"
aws amplify update-app --app-id "$APP_ID" --platform WEB_COMPUTE \
  --compute-role-arn "arn:aws:iam::$ACCOUNT:role/$ROLE" \
  --environment-variables "RUNTIME_NAME=amplify,TABLE_NAME=$TABLE,APP_REGION=$AWS_REGION" >/dev/null
aws amplify tag-resource --resource-arn "arn:aws:amplify:$AWS_REGION:$ACCOUNT:apps/$APP_ID" --tags "$TAGS_KV"

log "Deploy branch $BRANCH"
JOB=$(aws amplify start-job --app-id "$APP_ID" --branch-name "$BRANCH" --job-type RELEASE --query 'jobSummary.jobId' --output text)
while :; do
  S=$(aws amplify get-job --app-id "$APP_ID" --branch-name "$BRANCH" --job-id "$JOB" --query 'job.summary.status' --output text)
  case "$S" in SUCCEED) break;; FAILED|CANCELLED) echo "job $JOB: $S"; exit 1;; esac
  sleep 15
done
DOMAIN=$(aws amplify get-app --app-id "$APP_ID" --query 'app.defaultDomain' --output text)
echo "AMPLIFY_URL=https://$BRANCH.$DOMAIN"
