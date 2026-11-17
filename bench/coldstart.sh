#!/usr/bin/env bash
# Cold start measurements.
#   bench/coldstart.sh lambda 10          force N new Lambda execution environments
#   bench/coldstart.sh idle <url> 20      one request after <minutes> idle (Amplify, ECS)
set -euo pipefail
cd "$(dirname "$0")/.."; mkdir -p results
export AWS_PAGER=""
mode=${1:?lambda|idle}

req() { # url -> "seconds cold-flag"
  local out; out=$(curl -s -w ' %{time_total}' "$1/api/ping")
  echo "${out##* } $(echo "${out% *}" | grep -o '"cold":[a-z]*' | cut -d: -f2)"; }

if [ "$mode" = lambda ]; then
  n=${2:-10}; fn=${FN:-runtime-benchmark}
  url=$(aws lambda get-function-url-config --function-name "$fn" --query FunctionUrl --output text); url=${url%/}
  vars=$(aws lambda get-function-configuration --function-name "$fn" --query 'Environment.Variables' --output json)
  for i in $(seq 1 "$n"); do
    # Changing the configuration retires every warm environment, so the next request is cold.
    nv=$(echo "$vars" | python3 -c "import json,sys;v=json.load(sys.stdin);v['NONCE']='$i-$RANDOM';print(json.dumps({'Variables':v}))")
    aws lambda update-function-configuration --function-name "$fn" --environment "$nv" >/dev/null
    aws lambda wait function-updated-v2 --function-name "$fn"
    read -r cold flag <<<"$(req "$url")"; read -r warm _ <<<"$(req "$url")"
    echo "lambda,$i,$cold,$flag,$warm" | tee -a results/coldstart-lambda.csv
  done
else
  url=${2:?url}; mins=${3:-20}
  read -r t flag <<<"$(req "$url")"; echo "warm-up request: ${t}s"
  sleep $((mins * 60))
  read -r t flag <<<"$(req "$url")"
  echo "idle,$url,$mins,$t,$flag" | tee -a results/coldstart-idle.csv
fi
