"""CloudWatch 알람(SNS) → Discord 알림 (critical 채널)."""
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
    for rec in event["Records"]:
        alarm = json.loads(rec["Sns"]["Message"])
        icon = "🚨" if alarm.get("NewStateValue") == "ALARM" else "✅"
        content = (
            f"{icon} **{alarm.get('AlarmName')}** → {alarm.get('NewStateValue')}\n"
            f"{alarm.get('AlarmDescription') or ''}\n"
            f"사유: {alarm.get('NewStateReason')}"
        )
        req = urllib.request.Request(
            _webhook(),
            data=json.dumps({"content": content[:1900]}).encode(),
            headers={"Content-Type": "application/json", "User-Agent": "assac-alert"},
        )
        urllib.request.urlopen(req, timeout=5)
    return {"statusCode": 200}
