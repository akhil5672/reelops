# ReelOps

A media ingest platform built and run like production on AWS. A vendor uploads a clip, `ingest-api` stores it in S3 and queues a job on SQS, `transcode-worker` processes it and records status in ElastiCache Redis. Everything runs on EKS, ships through GitHub Actions and Argo CD, and is watched by Prometheus with SLO burn-rate alerts.

```
vendor ──POST /ingest──> ALB ──> ingest-api ──> S3 (raw)
                                     │
                                     └──> SQS ingest queue ──> transcode-worker (Spot nodes) ──> Redis status
                                              └─ DLQ after 3 failed receives
GET /status/{id} ──> ingest-api ──> Redis
```

| Layer | Tools |
|---|---|
| Code | Python, FastAPI, boto3, prometheus_client, pytest + moto |
| Containers | Docker multi-stage, non-root, Docker Compose + LocalStack for local dev |
| Infra | Terraform (S3 + DynamoDB backend, modules, `for_each`, remote state), AWS VPC, EKS, ECR, S3, SQS, ElastiCache, Secrets Manager, IAM, Budgets |
| Kubernetes | EKS managed node groups (on-demand + Spot), Pod Identity, AWS Load Balancer Controller, HPA, PDB, topology spread |
| Delivery | Helm, GitHub Actions with OIDC to AWS, ECR image scanning, Argo CD app-of-apps, External Secrets |
| Operations | kube-prometheus-stack, CloudWatch exporter (YACE), Grafana, Alertmanager to Slack, SLOs, runbooks, game days |

Two repos:
- **reelops** (this one): app code, Terraform, Helm chart, CI.
- **reelops-gitops**: what Argo CD deploys. CI writes image tags there.

---

## Cost

EKS is not free. Build in sessions and tear down after each one.

| Running resource | Approx. USD/hour (us-east-1) |
|---|---|
| EKS control plane | 0.10 |
| 2 x t3.large system nodes (on-demand) | 0.17 |
| 1 x t3.medium transcode node (Spot) | ~0.015 |
| NAT gateway (single) | 0.045 + data |
| 2 x ALB (staging + prod) | ~0.05 |
| ElastiCache cache.t4g.micro | ~0.016 |
| **Total while up** | **~$0.40/hour, so about $1.60 per 4-hour session** |

Left on 24/7 this is roughly **$290/month**. Always-on pieces from `bootstrap` (state bucket, lock table, ECR, 2 secrets) cost under $1/month. Terraform creates an AWS Budget that emails you at 50%, 80% and 100% of $40. Prices change, so check the AWS pricing pages and run `make cost-check`.

**End every session with `make aws-down`.**

---

## Before you start

1. An AWS account where you can create IAM roles. Use IAM Identity Center (SSO), not root.
2. A GitHub account, and two **empty** repos: `reelops` and `reelops-gitops`.
3. A Slack workspace with an incoming webhook (for alerts). Optional until phase 08.

## First-time setup

```bash
# 1. Unzip next to each other so the scripts can find both
#    ~/code/reelops   and   ~/code/reelops-gitops

# 2. Fill in your account, GitHub user and email everywhere (both repos)
cd ~/code/reelops
ACCOUNT_ID=123456789012 GITHUB_OWNER=your-gh-user ALERT_EMAIL=you@example.com ./scripts/init-placeholders.sh

# 3. Push both repos
git init -b main && git add . && git commit -m "reelops: initial scaffold" \
  && git remote add origin git@github.com:your-gh-user/reelops.git && git push -u origin main
cd ../reelops-gitops
git init -b main && git add . && git commit -m "gitops: initial" \
  && git remote add origin git@github.com:your-gh-user/reelops-gitops.git && git push -u origin main
```

The first CI run on `reelops` will pass `test` and `validate`. `build` fails until phase 03 creates the ECR repos and the OIDC role. That's expected.

---

## Phases

Each phase ends with a checkpoint. Don't move on until it passes.

### 00 · Toolchain
```bash
make bootstrap        # kubectl, helm, terraform, aws cli v2, jq, yq, pre-commit (pinned)
make doctor           # verifies tools + docker without sudo + AWS login
aws configure sso     # create a profile, then: export AWS_PROFILE=<name>; aws sso login
make hooks            # pre-commit: ruff, shellcheck, terraform fmt, gitleaks
```
**Checkpoint:** `make doctor` exits 0 and shows your AWS identity. Commit a fake key like `AKIA...` and watch gitleaks block it.

### 01 · Services (local, $0)
Read `services/ingest-api/app.py` and `services/transcode-worker/worker.py`. Note:
- config only from env vars
- `/healthz` (am I alive) vs `/readyz` (can I reach Redis + SQS)
- JSON logs to stdout
- the worker leaves bad messages on the queue so SQS moves them to the DLQ
- the worker finishes its current job on SIGTERM (Spot interruptions, rollouts)

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r services/ingest-api/requirements.txt -r services/ingest-api/requirements-dev.txt
pip install -r services/transcode-worker/requirements.txt
make test
```
**Checkpoint:** 7 tests pass. Add one test of your own (for example: `/readyz` returns 503 when Redis is down).

### 02 · Containers (local, $0)
```bash
make up               # LocalStack (S3+SQS), Redis, api, worker
make smoke            # uploads a clip, polls until DONE
make logs
docker image ls | grep reelops     # both images should be small (python slim + deps)
make down
```
**Checkpoint:** smoke test reaches DONE. `docker history` shows no secrets. `docker exec` into the API container and confirm `id` is uid 10001.

### 03 · AWS foundation with Terraform
```bash
make tf-bootstrap     # local state: state bucket, lock table, ECR repos, GitHub OIDC roles, budget, 2 secrets

# Fill the two long-lived secrets (values never touch Terraform state)
aws secretsmanager put-secret-value --secret-id reelops/alertmanager-slack \
  --secret-string '{"url":"https://hooks.slack.com/services/XXX/YYY/ZZZ"}'
aws secretsmanager put-secret-value --secret-id reelops/grafana-admin \
  --secret-string '{"admin-user":"admin","admin-password":"choose-a-long-one"}'

terraform -chdir=infra/terraform/envs/dev/network init && terraform -chdir=infra/terraform/envs/dev/network apply
terraform -chdir=infra/terraform/envs/dev/data    init && terraform -chdir=infra/terraform/envs/dev/data    apply
```
Then in GitHub, add the secret `GITOPS_TOKEN` to the reelops repo: a fine-grained personal access token with **Contents: read and write** on `reelops-gitops` only.

**Checkpoint:**
- A second `apply` on each stack says "No changes".
- `terraform output lanes` in `data` shows staging and prod queues.
- Send a poison message to `reelops-ingest-staging` and receive it 3 times. It should land in `reelops-ingest-staging-dlq`.
- Change a queue's visibility timeout in the console, run `plan`, and see the drift. Apply to fix it.

### 04 · EKS
```bash
terraform -chdir=infra/terraform/envs/dev/platform init && terraform -chdir=infra/terraform/envs/dev/platform apply   # ~15 min
make kubeconfig
kubectl get nodes -L workload,eks.amazonaws.com/capacityType
aws eks list-pod-identity-associations --cluster-name reelops-dev --output table
```
Next time, `make aws-up` runs network → data → platform in one go.

**Checkpoint:** 2 on-demand system nodes and 1 Spot transcode node (tainted `spot=true:NoSchedule`). 7 Pod Identity associations: 4 app, plus LB controller, external-secrets and yace.

### 05 · Helm chart
Read `charts/reelops`. Each ServiceAccount name matches a Pod Identity association, so pods get AWS credentials with no keys stored anywhere. Config comes from Secrets Manager through an ExternalSecret that the data stack fills in.
```bash
helm lint charts/reelops --set image.tag=test
helm template t charts/reelops --set image.tag=test | less
```
**Checkpoint:** you can explain every field in `templates/deployment.yaml`: probes, `maxUnavailable: 0`, the topology spread, the toleration plus nodeSelector pair, the read-only root filesystem.

### 06 · CI to ECR
Push a commit to `main`. Watch Actions: test → validate → build (OIDC → ECR push → scan gate) → deploy-staging (bumps `envs/staging/values.yaml` in reelops-gitops).

**Checkpoint:**
- New images in ECR tagged with the commit SHA. Tags are immutable, so try pushing the same tag twice and watch it fail.
- A commit in reelops-gitops from `reelops-ci`.
- Open a PR that breaks a test and confirm it can't merge. Turn on branch protection: Settings → Branches → require the `test` and `validate` checks.
- Open a PR that changes Terraform and read the plan in the job summary.

### 07 · GitOps with Argo CD
```bash
make argocd                      # installs Argo CD, applies bootstrap/root.yaml from ../reelops-gitops
make argocd-password
kubectl -n argocd port-forward svc/argocd-server 8080:443   # https://localhost:8080  (admin / password)
```
Argo syncs in waves: LB controller, metrics-server, external-secrets → kube-prometheus-stack → platform-config → reelops-staging. Give it about 5 minutes.
```bash
kubectl -n reelops-staging get externalsecret,secret,pods,ingress
ALB=$(kubectl -n reelops-staging get ingress reelops -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
make smoke BASE=http://$ALB      # ALB DNS can take 2-3 minutes to resolve
```
**Checkpoint:**
- The smoke test passes against the ALB.
- `kubectl -n reelops-staging scale deploy ingest-api --replicas=0` gets reverted by Argo (self-heal).
- Promote to prod with a PR that copies the tag into `envs/prod/values.yaml`, then sync `reelops-prod`.
- Roll back with `git revert` in reelops-gitops.

### 08 · Observability
```bash
kubectl -n monitoring port-forward svc/kps-grafana 3000:80           # dashboard "ReelOps"
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090
```
In Prometheus, open Status → Targets. `ingest-api`, `transcode-worker` and `yace` should be UP. Try:
```promql
sum by (namespace) (rate(ingest_requests_total[5m]))
histogram_quantile(0.95, sum by (le) (rate(ingest_request_seconds_bucket[5m])))
aws_sqs_approximate_number_of_messages_visible_maximum
reelops:ingest_error_ratio:rate5m
```
**Checkpoint:** set `CHAOS_FAIL_RATE: "0.3"` for ingest-api in `envs/staging/values.yaml` (under `services.ingest-api.env`), push, run `for i in $(seq 200); do make -s smoke BASE=http://$ALB; done`, and get `IngestErrorBudgetFastBurn` in Slack. Revert.

### 09 · SRE layer
Work through `docs/game-days.md`. Time each one from break to recovery. Write `docs/postmortems/001-*.md` from `docs/postmortem-template.md` for the worst drill. Keep `docs/slo.md` and `docs/runbook.md` up to date with what you learn.

**Checkpoint:** five drills done, MTTR recorded, one postmortem merged, every alert links to a runbook section that exists.

### Teardown (every session)
```bash
make aws-down
```
This stops Argo, deletes Ingresses so the controller removes the ALBs, then destroys platform → data → network. ALBs are created by Kubernetes, not Terraform. If they're left behind, the VPC destroy hangs.

---

## Repo map
```
services/ingest-api        FastAPI app, tests, Dockerfile
services/transcode-worker  SQS consumer, tests, Dockerfile
infra/terraform/bootstrap  state backend, ECR, GitHub OIDC roles, budget, long-lived secrets
infra/terraform/modules    ingest-queue (S3+SQS+DLQ), workload-role (IAM + Pod Identity)
infra/terraform/envs/dev   network -> data -> platform (each its own state, linked by terraform_remote_state)
charts/reelops             Helm chart for both services
scripts/                   bootstrap, doctor, smoke test, teardown, placeholder setup
docs/                      SLOs, runbook, game days, postmortem template
.github/workflows          ci.yml, terraform-plan.yml
```

## Version pins to refresh
Pinned in Oct 2026 from known-good releases. Before you start, bump them if newer stable ones exist: Kubernetes version (`platform/variables.tf`; check `aws eks describe-cluster-versions`), Helm chart versions in `reelops-gitops/apps/*.yaml`, the YACE image, and the tool versions in `scripts/bootstrap.sh`. Pin third-party GitHub Actions to commit SHAs as a hardening step.
