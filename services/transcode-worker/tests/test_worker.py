import json
import os

import boto3
import fakeredis
import pytest
from moto import mock_aws

os.environ.update(AWS_REGION="us-east-1", AWS_ACCESS_KEY_ID="test", AWS_SECRET_ACCESS_KEY="test")

import worker  # noqa: E402


@pytest.fixture
def env(monkeypatch):
    with mock_aws():
        sqs = boto3.client("sqs", region_name="us-east-1")
        url = sqs.create_queue(QueueName="q")["QueueUrl"]
        monkeypatch.setattr(worker, "QUEUE_URL", url)
        yield sqs, url, fakeredis.FakeRedis(decode_responses=True)


def _receive(sqs, url, body):
    sqs.send_message(QueueUrl=url, MessageBody=body)
    return sqs.receive_message(QueueUrl=url)["Messages"][0]


def test_success_marks_done_and_deletes(env):
    sqs, url, store = env
    msg = _receive(sqs, url, json.dumps({"asset_id": "a1", "queued_at": 0}))
    result = worker.process(msg, sqs, store, sleep=lambda _: None, rand=lambda: 0.99)
    assert result == "done"
    assert store.hget("asset:a1", "status") == "DONE"
    attrs = sqs.get_queue_attributes(QueueUrl=url, AttributeNames=["All"])["Attributes"]
    assert attrs["ApproximateNumberOfMessages"] == "0"
    assert attrs["ApproximateNumberOfMessagesNotVisible"] == "0"


def test_failure_marks_failed(env):
    sqs, url, store = env
    msg = _receive(sqs, url, json.dumps({"asset_id": "a2"}))
    assert worker.process(msg, sqs, store, sleep=lambda _: None, rand=lambda: 0.0) == "failed"
    assert store.hget("asset:a2", "status") == "FAILED"


def test_poison_message_is_left_for_dlq(env):
    sqs, url, store = env
    msg = _receive(sqs, url, "not-json")
    assert worker.process(msg, sqs, store) == "poison"
    attrs = sqs.get_queue_attributes(QueueUrl=url, AttributeNames=["All"])["Attributes"]
    assert attrs["ApproximateNumberOfMessagesNotVisible"] == "1"
