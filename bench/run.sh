#!/usr/bin/env bash
# Run the load test for every runtime and endpoint at one rate.
#   LAMBDA_URL=... WEB_URL=... ECS_URL=... AMPLIFY_URL=... [SKIP="ecs:/api/cpu"] bench/run.sh 10 [2m]
set -euo pipefail
cd "$(dirname "$0")/.."; mkdir -p results
rate=${1:?rate}; duration=${2:-2m}
for target in lambda web ecs amplify; do
  var="$(echo "$target" | tr a-z A-Z)_URL"; url="${!var:-}"
  [ -n "$url" ] || { echo "skip $target: $var not set"; continue; }
  for ep in / /api/item /api/cpu; do
    case " ${SKIP:-} " in *" $target:$ep "*) echo "skip $target $ep"; continue;; esac
    k6 run -q -e LABEL="$target" -e BASE_URL="$url" -e ENDPOINT="$ep" \
      -e RATE="$rate" -e DURATION="$duration" bench/load.js | grep '^{' | sed "s/^{/{\"runtime\":\"$target\",/"
  done
done
