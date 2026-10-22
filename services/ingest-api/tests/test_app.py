import os

import boto3
import fakeredis
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws

os.environ.update(
    AWS_REGION="us-east-1",
    AWS_ACCESS_KEY_ID="test",
    AWS_SECRET_ACCESS_KEY="test",
    RAW_BUCKET="test-raw",
)


@pytest.fixture
def client(monkeypatch):
    with mock_aws():
        boto3.client("s3", region_name="us-east-1").create_bucket(Bucket="test-raw")
        url = boto3.client("sqs", region_name="us-east-1").create_queue(QueueName="q")["QueueUrl"]
        import app as app_module

        monkeypatch.setattr(app_module, "QUEUE_URL", url)
        app_module.s3.cache_clear()
        app_module.sqs.cache_clear()
        fake = fakeredis.FakeRedis(decode_responses=True)
        monkeypatch.setattr(app_module, "store", lambda: fake)
        yield TestClient(app_module.app), url


def test_healthz(client):
    c, _ = client
    assert c.get("/healthz").status_code == 200


def test_ingest_queues_job_and_tracks_status(client):
    c, url = client
    r = c.post("/ingest", files={"file": ("clip.mp4", b"fake-bytes", "video/mp4")})
    assert r.status_code == 202
    asset_id = r.json()["asset_id"]

    msgs = boto3.client("sqs", region_name="us-east-1").receive_message(QueueUrl=url)["Messages"]
    assert asset_id in msgs[0]["Body"]

    s = c.get(f"/status/{asset_id}")
    assert s.json()["status"] == "QUEUED"


def test_unknown_status_is_404(client):
    c, _ = client
    assert c.get("/status/nope").status_code == 404


def test_metrics_exposed(client):
    c, _ = client
    assert "ingest_requests_total" in c.get("/metrics").text
