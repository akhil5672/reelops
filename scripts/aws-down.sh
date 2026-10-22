#!/usr/bin/env bash
# Tears down everything that costs money, in the right order.
# Keeps: bootstrap stack (state bucket, lock table, ECR, OIDC roles, budget) which costs cents.
set -euo pipefail
TF=infra/terraform/envs/dev

if kubectl cluster-info >/dev/null 2>&1; then
  echo "1/4 Stop Argo CD so it does not recreate what we delete"
  kubectl -n argocd scale statefulset argocd-application-controller --replicas=0 || true

  echo "2/4 Delete Ingresses so the AWS Load Balancer Controller removes the ALBs"
  # ALBs are created by Kubernetes, not Terraform. If they survive, 'terraform destroy'
  # of the VPC hangs on their ENIs and security groups.
  kubectl delete ingress --all -A --wait=true --timeout=300s || true
  sleep 30
fi

echo "3/4 Destroy platform (EKS) then data"
terraform -chdir="$TF/platform" destroy -auto-approve
terraform -chdir="$TF/data" destroy -auto-approve

echo "4/4 Destroy network (VPC, NAT gateway)"
terraform -chdir="$TF/network" destroy -auto-approve

echo "Done. Check for leftovers: aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'"
