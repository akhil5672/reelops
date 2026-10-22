"""ingest-api: accepts uploads, stores them in S3, queues a transcode job, tracks status in Redis."""

import json
import logging
import os
import random
import sys
import time
import uuid
from functools import lru_cache

import boto3
import redis
from fastapi import FastAPI, File, HTTPException, Response, UploadFile
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

REGION = os.getenv("AWS_REGION", "us-east-1")
RAW_BUCKET = os.getenv("RAW_BUCKET", "")
QUEUE_URL = os.getenv("QUEUE_URL", "")
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_DB = int(os.getenv("REDIS_DB", "0"))
# Drill knob: fraction of /ingest calls that fail on purpose (phase 09).
CHAOS_FAIL_RATE = float(os.getenv("CHAOS_FAIL_RATE", "0"))

logging.basicConfig(stream=sys.stdout, level=logging.INFO, format="%(message)s")
log = logging.getLogger("ingest-api")


def jlog(level: int, msg: str, **fields) -> None:
    log.log(level, json.dumps({"ts": time.time(), "svc": "ingest-api", "msg": msg, **fields}))


REQS = Counter("ingest_requests_total", "Ingest requests by HTTP status", ["status"])
LAT = Histogram(
    "ingest_request_seconds",
    "Ingest request latency",
    buckets=(0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)


@lru_cache
def s3():
    return boto3.client("s3", region_name=REGION)


@lru_cache
def sqs():
    return boto3.client("sqs", region_name=REGION)


@lru_cache
def store():
    return redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB, decode_responses=True)


app = FastAPI(title="reelops ingest-api")


@app.get("/healthz")
def healthz():
    return {"ok": True}


@app.get("/readyz")
def readyz():
    try:
        store().ping()
        sqs().get_queue_attributes(QueueUrl=QUEUE_URL, AttributeNames=["QueueArn"])
    except Exception as exc:  # noqa: BLE001
        jlog(logging.WARNING, "not ready", error=str(exc))
        raise HTTPException(status_code=503, detail="dependencies unavailable") from exc
    return {"ready": True}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/ingest", status_code=202)
def ingest(file: UploadFile = File(...)):
    start = time.perf_counter()
    asset_id = str(uuid.uuid4())
    key = f"raw/{asset_id}/{file.filename}"
    try:
        if CHAOS_FAIL_RATE and random.random() < CHAOS_FAIL_RATE:
            raise RuntimeError("chaos: injected failure")
        s3().upload_fileobj(file.file, RAW_BUCKET, key)
        sqs().send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=json.dumps({"asset_id": asset_id, "key": key, "queued_at": time.time()}),
        )
        store().hset(
            f"asset:{asset_id}",
            mapping={"status": "QUEUED", "key": key, "queued_at": str(time.time())},
        )
    except Exception as exc:  # noqa: BLE001
        REQS.labels(status="500").inc()
        jlog(logging.ERROR, "ingest failed", asset_id=asset_id, error=str(exc))
        raise HTTPException(status_code=500, detail="ingest failed") from exc
    finally:
        LAT.observe(time.perf_counter() - start)
    REQS.labels(status="202").inc()
    jlog(logging.INFO, "queued", asset_id=asset_id, key=key)
    return {"asset_id": asset_id, "status": "QUEUED"}


@app.get("/status/{asset_id}")
def status(asset_id: str):
    data = store().hgetall(f"asset:{asset_id}")
    if not data:
        raise HTTPException(status_code=404, detail="unknown asset")
    return {"asset_id": asset_id, **data}
