"""GuardDuty Finding(EventBridge) → Discord 알림 (critical 채널)."""
import json
import os
import urllib.request

import boto3

_ssm = boto3.client("ssm")
_cache = {}


def _webhook():
    name = os.environ["WEBHOOK_PARAMETER_NAME"]
    if name not in _cache:
        _cache[name] = _ssm.get_parameter(Name=name, WithDecryption=True)["Parameter"]["Value"]
    return _cache[name]


def lambda_handler(event, context):
    d = event["detail"]
    content = (
        f"🕵️ **GuardDuty 탐지** (심각도 {d.get('severity')})\n"
        f"- 유형: {d.get('type')}\n"
        f"- 제목: {d.get('title')}\n"
        f"- 리전: {d.get('region')}"
    )
    req = urllib.request.Request(
        _webhook(),
        data=json.dumps({"content": content[:1900]}).encode(),
        headers={"Content-Type": "application/json", "User-Agent": "assac-alert"},
    )
    urllib.request.urlopen(req, timeout=5)
    return {"statusCode": 200}
