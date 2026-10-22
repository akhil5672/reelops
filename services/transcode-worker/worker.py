"""transcode-worker: long-polls SQS, fakes a transcode, writes final status to Redis."""

import json
import logging
import os
import random
import signal
import sys
import time

import boto3
import redis
from prometheus_client import Counter, Gauge, Histogram, start_http_server

REGION = os.getenv("AWS_REGION", "us-east-1")
QUEUE_URL = os.getenv("QUEUE_URL", "")
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_DB = int(os.getenv("REDIS_DB", "0"))
FAIL_RATE = float(os.getenv("FAIL_RATE", "0.05"))
MIN_SECONDS = float(os.getenv("MIN_SECONDS", "2"))
MAX_SECONDS = float(os.getenv("MAX_SECONDS", "8"))
METRICS_PORT = int(os.getenv("METRICS_PORT", "9100"))

logging.basicConfig(stream=sys.stdout, level=logging.INFO, format="%(message)s")
log = logging.getLogger("transcode-worker")


def jlog(level: int, msg: str, **fields) -> None:
    log.log(level, json.dumps({"ts": time.time(), "svc": "transcode-worker", "msg": msg, **fields}))


JOBS = Counter("jobs_processed_total", "Jobs processed by result", ["result"])
IN_PROGRESS = Gauge("jobs_in_progress", "Jobs currently being transcoded")
E2E = Histogram(
    "job_end_to_end_seconds",
    "Time from QUEUED to DONE (freshness SLI)",
    buckets=(5, 10, 30, 60, 120, 300, 600),
)

_running = True


def _stop(signum, _frame):
    # Spot interruption / rollout sends SIGTERM: finish the current job, then exit.
    global _running
    jlog(logging.INFO, "shutdown requested", signal=signum)
    _running = False


def process(message: dict, sqs, store, sleep=time.sleep, rand=random.random) -> str:
    """Handle one SQS message. Returns the result label. Poison messages are NOT deleted,
    so SQS moves them to the DLQ after maxReceiveCount."""
    try:
        body = json.loads(message["Body"])
        asset_id = body["asset_id"]
    except (ValueError, KeyError):
        JOBS.labels(result="poison").inc()
        jlog(logging.ERROR, "poison message", message_id=message.get("MessageId"))
        return "poison"

    key = f"asset:{asset_id}"
    store.hset(key, mapping={"status": "PROCESSING"})
    IN_PROGRESS.inc()
    try:
        sleep(MIN_SECONDS + (MAX_SECONDS - MIN_SECONDS) * rand())
        if rand() < FAIL_RATE:
            store.hset(key, mapping={"status": "FAILED", "finished_at": str(time.time())})
            result = "failed"
        else:
            now = time.time()
            store.hset(key, mapping={"status": "DONE", "finished_at": str(now)})
            if "queued_at" in body:
                E2E.observe(now - float(body["queued_at"]))
            result = "done"
    finally:
        IN_PROGRESS.dec()

    sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=message["ReceiptHandle"])
    JOBS.labels(result=result).inc()
    jlog(logging.INFO, "processed", asset_id=asset_id, result=result)
    return result


def main() -> None:
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    start_http_server(METRICS_PORT)
    sqs = boto3.client("sqs", region_name=REGION)
    store = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB, decode_responses=True)
    jlog(logging.INFO, "worker started", queue=QUEUE_URL)
    while _running:
        try:
            resp = sqs.receive_message(QueueUrl=QUEUE_URL, MaxNumberOfMessages=1, WaitTimeSeconds=10)
        except Exception as exc:  # noqa: BLE001
            jlog(logging.ERROR, "receive failed", error=str(exc))
            time.sleep(5)
            continue
        for msg in resp.get("Messages", []):
            process(msg, sqs, store)
    jlog(logging.INFO, "worker stopped")


if __name__ == "__main__":
    main()
