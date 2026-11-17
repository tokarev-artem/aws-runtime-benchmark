#!/usr/bin/env bash
# Delete everything the deploy scripts created. Usage: [APP_ID=d123abc] infra/cleanup.sh
cd "$(dirname "$0")/.." && source infra/env.sh
set +e  # keep going if something is already gone

if [ -n "${APP_ID:-}" ]; then
  log "Amplify app $APP_ID"; aws amplify delete-app --app-id "$APP_ID" >/dev/null
fi

log "ECS service, cluster, task definitions"
aws ecs update-service --cluster "$NAME" --service "$NAME" --desired-count 0 >/dev/null 2>&1
aws ecs delete-service --cluster "$NAME" --service "$NAME" --force >/dev/null 2>&1
aws ecs wait services-inactive --cluster "$NAME" --services "$NAME" 2>/dev/null
for td in $(aws ecs list-task-definitions --family-prefix "$NAME" --query 'taskDefinitionArns[]' --output text); do
  aws ecs deregister-task-definition --task-definition "$td" >/dev/null
  aws ecs delete-task-definitions --task-definitions "$td" >/dev/null 2>&1
done
aws ecs delete-cluster --cluster "$NAME" >/dev/null 2>&1

log "Load balancer and target group"
ALB_ARN=$(aws elbv2 describe-load-balancers --names "$NAME" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
  aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN"
fi
TG_ARN=$(aws elbv2 describe-target-groups --names "$NAME" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
[ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ] && aws elbv2 delete-target-group --target-group-arn "$TG_ARN"

log "Security groups (retry while ENIs are released)"
VPC=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
for g in "$NAME-task" "$NAME-alb"; do
  id=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC" Name=group-name,Values="$g" --query 'SecurityGroups[0].GroupId' --output text)
  [ "$id" = "None" ] && continue
  for i in $(seq 1 12); do aws ec2 delete-security-group --group-id "$id" 2>/dev/null && break; sleep 10; done
done

log "Lambda function"
aws lambda delete-function --function-name "$NAME" 2>/dev/null

log "ECR repository, DynamoDB table, log groups"
aws ecr delete-repository --repository-name "$NAME" --force >/dev/null 2>&1
aws dynamodb delete-table --table-name "$TABLE" >/dev/null 2>&1
for lg in "/ecs/$NAME" "/aws/lambda/$NAME"; do aws logs delete-log-group --log-group-name "$lg" 2>/dev/null; done

log "IAM roles"
for r in "$NAME-lambda" "$NAME-ecs-exec" "$NAME-ecs-task" "$NAME-amplify-compute"; do
  aws iam get-role --role-name "$r" >/dev/null 2>&1 || continue
  for p in $(aws iam list-role-policies --role-name "$r" --query 'PolicyNames[]' --output text); do
    aws iam delete-role-policy --role-name "$r" --policy-name "$p"; done
  for p in $(aws iam list-attached-role-policies --role-name "$r" --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "$r" --policy-arn "$p"; done
  aws iam delete-role --role-name "$r" && echo "deleted $r"
done

log "Anything still tagged project=$NAME"
aws resourcegroupstaggingapi get-resources --tag-filters Key=project,Values="$NAME" \
  --query 'ResourceTagMappingList[].ResourceARN' --output text
