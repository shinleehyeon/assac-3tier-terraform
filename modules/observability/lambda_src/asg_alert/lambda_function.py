"""ASG 이벤트(EventBridge) 및 SNS 메시지 → Discord 알림."""
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
    if "Records" in event:  # SNS
        for rec in event["Records"]:
            _post(f"📈 **ASG 알림**\n{rec['Sns']['Subject'] or ''}\n{rec['Sns']['Message']}")
        return {"statusCode": 200}

    detail = event.get("detail", {})  # EventBridge
    _post(
        f"📈 **{event.get('detail-type')}**\n"
        f"- ASG: {detail.get('AutoScalingGroupName')}\n"
        f"- 인스턴스: {detail.get('EC2InstanceId')}\n"
        f"- 원인: {detail.get('Cause', '-')}"
    )
    return {"statusCode": 200}
