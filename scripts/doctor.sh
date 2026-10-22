#!/usr/bin/env bash
# Verifies the toolchain and AWS access. Exits non-zero if anything required is missing.
set -uo pipefail
fail=0
check() {
  if command -v "$1" >/dev/null 2>&1; then
    printf "  %-11s %s\n" "$1" "$($2 2>&1 | head -1)"
  else
    printf "  %-11s MISSING\n" "$1"; fail=1
  fi
}
echo "Tools:"
check docker     "docker --version"
check kubectl    "kubectl version --client"
check helm       "helm version --short"
check terraform  "terraform version"
check aws        "aws --version"
check jq         "jq --version"
check yq         "yq --version"
check pre-commit "pre-commit --version"

echo "Docker without sudo:"
if docker ps >/dev/null 2>&1; then echo "  ok"; else echo "  FAILED (add yourself to the docker group, then log out and in)"; fail=1; fi

echo "AWS identity (profile: ${AWS_PROFILE:-default}):"
if aws sts get-caller-identity --query Arn --output text 2>/dev/null; then :; else
  echo "  not logged in. Run: aws configure sso   then   aws sso login"
fi
exit $fail
