#!/usr/bin/env bash
# Probe request timeout and response size limits: bench/limits.sh <label> <base-url>
set -uo pipefail
label=$1 url=$2
for s in 10 29 31 60 61 120; do
  printf '%s sleep %4ss -> ' "$label" "$s"
  curl -s -o /dev/null -m 200 -w '%{http_code} after %{time_total}s\n' "$url/api/sleep?s=$s"
done
for mb in 1 5 6 7 10 20; do
  printf '%s size  %4sMB -> ' "$label" "$mb"
  curl -s -o /dev/null -m 60 -w '%{http_code} %{size_download} bytes\n' "$url/api/size?mb=$mb"
done
