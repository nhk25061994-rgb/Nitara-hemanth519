#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  promote.sh — promote image tag from one environment to next
#
#  Usage:
#    ./promote.sh dev  test    # copy dev  tag → test
#    ./promote.sh test uat     # copy test tag → uat
#    ./promote.sh uat  stg     # copy uat  tag → stg
# ─────────────────────────────────────────────────────────────
set -euo pipefail

FROM_ENV=${1:-}
TO_ENV=${2:-}

if [[ -z "$FROM_ENV" || -z "$TO_ENV" ]]; then
  echo "Usage: $0 <from-env> <to-env>"
  echo "  e.g: $0 dev test"
  exit 1
fi

FROM_FILE="values/${FROM_ENV}-values.yaml"
TO_FILE="values/${TO_ENV}-values.yaml"

if [[ ! -f "$FROM_FILE" ]]; then
  echo "ERROR: $FROM_FILE not found"
  exit 1
fi

# Extract current image tag from source env
CURRENT_TAG=$(grep '^\s*tag:' "$FROM_FILE" | awk '{print $2}' | tr -d '"')

echo "Promoting: ${FROM_ENV} → ${TO_ENV}"
echo "Image tag: ${CURRENT_TAG}"
echo ""

# Update destination values file
sed -i "s|^  tag:.*|  tag: \"${CURRENT_TAG}\"|" "$TO_FILE"

# Commit and push
git add "$TO_FILE"
git commit -m "promote(${TO_ENV}): nitara-app → ${CURRENT_TAG}"
git push origin main

echo ""
echo "Done! ArgoCD will now sync ${TO_ENV} with tag ${CURRENT_TAG}"
echo "Check:  argocd app get nitara-app-${TO_ENV}"
