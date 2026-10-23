"""WAF 로그(BLOCK) → Discord 알림.

CloudWatch Logs 구독 필터가 `{ $.action = "BLOCK" }` 로 거른 로그를 gzip+base64 로 전달한다.
"""
import base64
import gzip
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


def _post(content):
    req = urllib.request.Request(
        _webhook(),
        data=json.dumps({"content": content[:1900]}).encode(),
        headers={"Content-Type": "application/json", "User-Agent": "assac-alert"},
    )
    urllib.request.urlopen(req, timeout=5)


def lambda_handler(event, context):
    payload = json.loads(gzip.decompress(base64.b64decode(event["awslogs"]["data"])))
    for log in payload["logEvents"]:
        rec = json.loads(log["message"])
        req = rec.get("httpRequest", {})
        headers = {h["name"].lower(): h["value"] for h in req.get("headers", [])}
        _post(
            "🛡️ **WAF 차단**\n"
            f"- 규칙: {rec.get('terminatingRuleId')}\n"
            f"- IP: {req.get('clientIp')} ({req.get('country')})\n"
            f"- 요청: {req.get('httpMethod')} {req.get('uri')}\n"
            f"- UA: {headers.get('user-agent', '-')}"
        )
    return {"statusCode": 200}
