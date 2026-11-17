# Shared settings. Source this file; override with environment variables.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-default}"
export AWS_REGION="${AWS_REGION:-eu-central-1}"
export AWS_PAGER=""
NAME="${NAME:-runtime-benchmark}"
TABLE="$NAME"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REPO_URI="$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/$NAME"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo latest)}"
TAGS="Key=project,Value=$NAME"
TAGS_KV="project=$NAME"
log() { printf '\n== %s\n' "$*"; }
