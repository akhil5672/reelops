# ReelOps runbook

First steps for any alert:
```bash
NS=reelops-staging   # or reelops-prod
kubectl -n $NS get pods -o wide
kubectl -n $NS get events --sort-by=.lastTimestamp | tail -20
kubectl -n argocd get applications
```

## ingest-5xx
**Alerts:** IngestErrorBudgetFastBurn, IngestErrorBudgetSlowBurn
**Means:** `/ingest` is returning 500s. Users can't upload.
1. Look at the errors: `kubectl -n $NS logs deploy/ingest-api --since=10m | jq -r 'select(.msg=="ingest failed") | .error' | sort | uniq -c`
2. `AccessDenied`: check the Pod Identity association and role policy (`aws eks list-pod-identity-associations --cluster-name reelops-dev`), then run `terraform plan` in `platform` to see drift.
3. Redis connection errors: `aws elasticache describe-cache-clusters --cache-cluster-id reelops-dev --show-cache-node-info`. Is it `available`?
4. `chaos: injected failure`: someone left `CHAOS_FAIL_RATE` on. Set it to `"0"` in gitops.
5. Started right after a deploy: `git revert` the tag bump in reelops-gitops.
**Escalate** if not mitigated in 30 minutes.

## dlq
**Alert:** IngestDLQNotEmpty
**Means:** messages failed 3 times and were parked. Those assets are stuck.
1. Peek without deleting: `aws sqs receive-message --queue-url <dlq-url> --visibility-timeout 0 --max-number-of-messages 5`
2. Malformed body: a producer bug. Find the sender and fix it, then purge.
3. Valid body: the worker failed for some other reason. Fix it, then redrive: `aws sqs start-message-move-task --source-arn <dlq-arn>`

## slow-jobs
**Alerts:** TranscodeFreshnessSLOAtRisk, IngestQueueBacklog
**Means:** jobs are waiting too long.
1. Are workers running? `kubectl -n $NS get pods -l app.kubernetes.io/name=transcode-worker`
2. Pending pods: is the Spot node group at 0 or interrupted? `kubectl get nodes -l workload=transcode`. Raise `desired_size` or the replica count.
3. Is the queue growing faster than the workers can drain it? Add workers in gitops values.

## crashloop
**Alert:** ReelopsPodCrashLooping
1. `kubectl -n $NS logs <pod> --previous`
2. `kubectl -n $NS describe pod <pod>`. Look for OOMKilled, image pull errors or probe failures.
3. Bad image: revert the tag in gitops. OOM: raise the memory limit in values.
