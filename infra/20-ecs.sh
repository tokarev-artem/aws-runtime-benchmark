#!/usr/bin/env bash
# ECS Fargate service behind an Application Load Balancer, in the default VPC.
# Tasks get public IPs, so no NAT gateway is needed to pull the image.
cd "$(dirname "$0")/.." && source infra/env.sh
CPU="${CPU:-512}"; MEM="${MEM:-1024}"; COUNT="${COUNT:-1}"
EXEC_ROLE="$NAME-ecs-exec"; TASK_ROLE="$NAME-ecs-task"; LOGS="/ecs/$NAME"

VPC=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC" Name=default-for-az,Values=true \
  --query 'Subnets[].SubnetId' --output text)
echo "VPC=$VPC SUBNETS=$SUBNETS"

trust() { echo "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"$1\"},\"Action\":\"sts:AssumeRole\"}]}"; }
log "IAM roles"
aws iam get-role --role-name "$EXEC_ROLE" >/dev/null 2>&1 || {
  aws iam create-role --role-name "$EXEC_ROLE" --tags "$TAGS" --assume-role-policy-document "$(trust ecs-tasks.amazonaws.com)" >/dev/null
  aws iam attach-role-policy --role-name "$EXEC_ROLE" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy; }
aws iam get-role --role-name "$TASK_ROLE" >/dev/null 2>&1 ||
  aws iam create-role --role-name "$TASK_ROLE" --tags "$TAGS" --assume-role-policy-document "$(trust ecs-tasks.amazonaws.com)" >/dev/null
aws iam put-role-policy --role-name "$TASK_ROLE" --policy-name dynamodb-read --policy-document \
  "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"dynamodb:GetItem\",\"Resource\":\"arn:aws:dynamodb:$AWS_REGION:$ACCOUNT:table/$TABLE\"}]}"

log "Log group $LOGS (7 days)"
aws logs create-log-group --log-group-name "$LOGS" --tags "$TAGS_KV" 2>/dev/null || true
aws logs put-retention-policy --log-group-name "$LOGS" --retention-in-days 7

log "Security groups"
sg() { # name description
  local id; id=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC" Name=group-name,Values="$1" \
    --query 'SecurityGroups[0].GroupId' --output text)
  if [ "$id" = "None" ]; then
    id=$(aws ec2 create-security-group --vpc-id "$VPC" --group-name "$1" --description "$2" \
      --tag-specifications "ResourceType=security-group,Tags=[{$TAGS}]" --query GroupId --output text)
  fi
  echo "$id"; }
ALB_SG=$(sg "$NAME-alb" "HTTP from the internet to the ALB")
TASK_SG=$(sg "$NAME-task" "Port 3000 from the ALB only")
aws ec2 authorize-security-group-ingress --group-id "$ALB_SG" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null 2>&1 || true
aws ec2 authorize-security-group-ingress --group-id "$TASK_SG" --protocol tcp --port 3000 --source-group "$ALB_SG" >/dev/null 2>&1 || true

log "Load balancer, target group, listener"
ALB_ARN=$(aws elbv2 describe-load-balancers --names "$NAME" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null ||
  aws elbv2 create-load-balancer --name "$NAME" --type application --scheme internet-facing \
    --subnets $SUBNETS --security-groups "$ALB_SG" --tags "$TAGS" --query 'LoadBalancers[0].LoadBalancerArn' --output text)
TG_ARN=$(aws elbv2 describe-target-groups --names "$NAME" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null ||
  aws elbv2 create-target-group --name "$NAME" --protocol HTTP --port 3000 --vpc-id "$VPC" --target-type ip \
    --health-check-path /api/health --health-check-interval-seconds 10 --healthy-threshold-count 2 \
    --tags "$TAGS" --query 'TargetGroups[0].TargetGroupArn' --output text)
# Fast deploys: don't wait the default 300 s for connections to drain.
aws elbv2 modify-target-group-attributes --target-group-arn "$TG_ARN" \
  --attributes Key=deregistration_delay.timeout_seconds,Value=10 >/dev/null
[ "$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --query 'length(Listeners)')" != "0" ] ||
  aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --protocol HTTP --port 80 \
    --default-actions Type=forward,TargetGroupArn="$TG_ARN" >/dev/null

log "Cluster and task definition ($CPU CPU units, $MEM MB, arm64)"
aws ecs describe-clusters --clusters "$NAME" --query 'clusters[?status==`ACTIVE`]' --output text | grep -q . ||
  aws ecs create-cluster --cluster-name "$NAME" --tags key=project,value="$NAME" >/dev/null
TD=$(aws ecs register-task-definition --family "$NAME" --requires-compatibilities FARGATE --network-mode awsvpc \
  --cpu "$CPU" --memory "$MEM" --runtime-platform cpuArchitecture=ARM64,operatingSystemFamily=LINUX \
  --execution-role-arn "arn:aws:iam::$ACCOUNT:role/$EXEC_ROLE" --task-role-arn "arn:aws:iam::$ACCOUNT:role/$TASK_ROLE" \
  --container-definitions "[{\"name\":\"app\",\"image\":\"$REPO_URI:$IMAGE_TAG\",\"essential\":true,
    \"portMappings\":[{\"containerPort\":3000}],
    \"environment\":[{\"name\":\"RUNTIME_NAME\",\"value\":\"ecs-fargate\"},{\"name\":\"TABLE_NAME\",\"value\":\"$TABLE\"},{\"name\":\"APP_REGION\",\"value\":\"$AWS_REGION\"}],
    \"logConfiguration\":{\"logDriver\":\"awslogs\",\"options\":{\"awslogs-group\":\"$LOGS\",\"awslogs-region\":\"$AWS_REGION\",\"awslogs-stream-prefix\":\"app\"}}}]" \
  --tags key=project,value="$NAME" --query 'taskDefinition.taskDefinitionArn' --output text)
echo "TASK_DEFINITION=$TD"

log "Service ($COUNT task)"
NET="awsvpcConfiguration={subnets=[${SUBNETS// /,}],securityGroups=[$TASK_SG],assignPublicIp=ENABLED}"
if aws ecs describe-services --cluster "$NAME" --services "$NAME" --query 'services[?status==`ACTIVE`]' --output text | grep -q .; then
  aws ecs update-service --cluster "$NAME" --service "$NAME" --task-definition "$TD" --desired-count "$COUNT" >/dev/null
else
  aws ecs create-service --cluster "$NAME" --service-name "$NAME" --task-definition "$TD" \
    --desired-count "$COUNT" --launch-type FARGATE --network-configuration "$NET" \
    --load-balancers targetGroupArn="$TG_ARN",containerName=app,containerPort=3000 \
    --health-check-grace-period-seconds 30 --propagate-tags SERVICE --tags key=project,value="$NAME" >/dev/null
fi
echo "waiting for the service to become stable..."
aws ecs wait services-stable --cluster "$NAME" --services "$NAME"
DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0].DNSName' --output text)
echo "ECS_URL=http://$DNS"
