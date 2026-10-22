# Game days

Run against `reelops-staging` with traffic flowing:
`while true; do make -s smoke BASE=http://$ALB >/dev/null; sleep 1; done`

For each drill, write down:
- when you broke it
- when the alert fired
- when you knew the cause
- when it recovered

| # | Break | How | What you should see | Fix |
|---|---|---|---|---|
| 1 | Lose a node | `aws ec2 terminate-instances --instance-ids <system-node-id>` | Pods reschedule, the PDB keeps 1 api pod up, the managed node group replaces the node | Nothing. Confirm there was no 5xx spike |
| 2 | Spot interruption | `kubectl drain <transcode-node> --ignore-daemonsets --delete-emptydir-data` | Worker logs "shutdown requested", finishes its job, unfinished messages reappear after the visibility timeout. No lost jobs | `kubectl uncordon`. Explain why visibility timeout must be longer than job time |
| 3 | Redis outage | `aws elasticache reboot-cache-cluster --cache-cluster-id reelops-dev --cache-node-ids-to-reboot 0001` | `/readyz` fails, pods leave the Service, 5xx, fast-burn alert | Wait for `available`. Discuss a replication group with automatic failover |
| 4 | Broken IAM | Delete the staging ingest-api Pod Identity association in the console, then restart the pod | `AccessDenied` in logs, error ratio spikes | `terraform apply` in `platform` restores it. Note that `plan` showed the drift |
| 5 | Bad deploy | Push a commit where `app.py` raises at import | Staging pods CrashLoopBackOff, rollout stalls (maxUnavailable 0 keeps old pods serving) | `git revert` in reelops-gitops |
| 6 | Poison messages | `aws sqs send-message --queue-url <staging-url> --message-body 'not-json'` x5 | Worker logs poison, DLQ alert after about 5 minutes | Follow runbook#dlq |

After the worst one, write `docs/postmortems/001-<name>.md` from the template.
