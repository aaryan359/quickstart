#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <api_public_ip>"
  exit 1
fi

api_public_ip="$1"

curl -fsS -X POST "http://${api_public_ip}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Say hello in one short sentence."}]}'

echo
