"""WAS 정상 인스턴스 이상 알람 시 호출되는 운영 호출용 Lambda.

CloudTrail 에는 함수의 설정(런타임·롤·태그)만 남아 있고 코드는 남지 않아,
원본 동작은 복원하지 못했다. 알람 이벤트를 받아 로그만 남기는 자리 표시 구현이다.
"""
import json


def lambda_handler(event, context):
    print(json.dumps(event))
    return {"statusCode": 200}
