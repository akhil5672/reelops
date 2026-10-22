# ReelOps SLOs

Window: rolling 28 days. Measured per namespace (`reelops-staging`, `reelops-prod`).

| SLI | Good event | SLO | Error budget (28d) | Recording rule |
|---|---|---|---|---|
| Ingest availability | `/ingest` response is not 5xx | 99.5% | 0.5% of requests (~3.4h of full outage) | `reelops:ingest_error_ratio:*` |
| Ingest latency | `/ingest` completes in under 500 ms | 95% | 5% of requests | `reelops:ingest_fast_ratio:rate1h` |
| Freshness | job reaches DONE within 2 min of QUEUED | 99% | 1% of jobs | `reelops:job_fresh_ratio:rate1h` |

## Alerting (multi-window burn rate)
| Alert | Burn rate | Windows | Budget used when it fires | Severity |
|---|---|---|---|---|
| IngestErrorBudgetFastBurn | 14.4x | 1h and 5m | 2% in 1 hour | page |
| IngestErrorBudgetSlowBurn | 6x | 6h and 30m | 5% in 6 hours | ticket |

The short window stops the alert from firing long after the problem is fixed. The long window stops it firing on a brief blip.

## Error budget policy
- Budget left above 50%: ship freely.
- Between 0 and 50%: deploys need a rollback plan written in the PR.
- Exhausted: feature deploys stop. Only reliability fixes ship until the budget recovers.

## Why these numbers
Vendors retry uploads, so 99.5% availability is enough. A tighter SLO costs more than the users would notice. Freshness matters because the material status page is what operations staff watch.
