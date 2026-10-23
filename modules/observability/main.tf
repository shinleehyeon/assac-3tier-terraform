# 관측·알림 계층
#   WAF 로그(BLOCK) ─구독필터→ Lambda ─→ Discord
#   CloudWatch 알람 ─→ SNS ─→ Lambda ─→ Discord
#   EventBridge(ASG, GuardDuty) ─→ Lambda ─→ Discord
#   Budgets / CloudTrail / GuardDuty

data "aws_caller_identity" "current" {}

# ── Discord 웹훅 (Parameter Store SecureString) ──────────────────
# 값은 저장소에 두지 않는다. 배포 후 콘솔/CLI 로 한 번만 입력한다.
resource "aws_ssm_parameter" "webhook" {
  for_each = {
    "assac-ssm-webhook-critical" = "Discord webhook for AWS alerts"
    "assac-ssm-webhook-general"  = "Discord webhook for AWS alerts"
  }

  name        = each.key
  description = each.value
  type        = "SecureString"
  value       = "placeholder"

  lifecycle {
    ignore_changes = [value]
  }
}

# ── Lambda 함수 ─────────────────────────────────────────────────
locals {
  functions = {
    waf_alert = {
      name      = "assac-lambda-waf-alert"
      parameter = "assac-ssm-webhook-general"
      runtime   = "python3.13"
    }
    asg_alert = {
      name      = "assac-lambda-asg-alert"
      parameter = "assac-ssm-webhook-general"
      runtime   = "python3.13"
    }
    cloudwatch_alarm = {
      name      = "assac-lambda-cloudwatch-alarm"
      parameter = "assac-ssm-webhook-critical"
      runtime   = "python3.13"
    }
    guardduty_alert = {
      name      = "assac-lambda-guardduty-alert"
      parameter = "assac-ssm-webhook-critical"
      runtime   = "python3.13"
    }
    clawops_call = {
      name      = "assac-clawops-call"
      parameter = "assac-ssm-webhook-critical"
      runtime   = "python3.12"
    }
  }
}

data "archive_file" "lambda" {
  for_each = local.functions

  type        = "zip"
  source_dir  = "${path.module}/lambda_src/${each.key}"
  output_path = "${path.module}/.build/${each.key}.zip"
}

resource "aws_lambda_function" "this" {
  for_each = local.functions

  function_name    = each.value.name
  role             = var.lambda_role_arns[each.key]
  runtime          = each.value.runtime
  handler          = "lambda_function.lambda_handler"
  timeout          = 3
  memory_size      = 128
  filename         = data.archive_file.lambda[each.key].output_path
  source_code_hash = data.archive_file.lambda[each.key].output_base64sha256

  environment {
    variables = {
      WEBHOOK_PARAMETER_NAME = each.value.parameter
    }
  }
}

# Lambda 롤이 웹훅 파라미터를 읽도록 허용
resource "aws_iam_role_policy" "read_webhook" {
  for_each = local.functions

  name = "read-webhook-parameter"
  role = var.lambda_role_names[each.key]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = aws_ssm_parameter.webhook[each.value.parameter].arn
    }]
  })
}

# ── SNS ────────────────────────────────────────────────────────
resource "aws_sns_topic" "alarm" {
  name = "assac-alarm-topic"
}

resource "aws_sns_topic" "asg" {
  name = "assac-sns-asg-alert"
}

resource "aws_sns_topic" "critical" {
  name = "assac-sns-critical-alert"
}

resource "aws_sns_topic" "alb_5xx" {
  name = "assac-sns-alb-5xx-alert"
}

resource "aws_sns_topic_subscription" "asg_email" {
  for_each = toset(var.alert_emails)

  topic_arn = aws_sns_topic.asg.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_sns_topic_subscription" "asg_lambda" {
  topic_arn = aws_sns_topic.asg.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.this["asg_alert"].arn
}

resource "aws_sns_topic_subscription" "critical_lambda" {
  topic_arn = aws_sns_topic.critical.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.this["cloudwatch_alarm"].arn
}

resource "aws_lambda_permission" "sns_asg" {
  statement_id  = "AllowSnsAsg"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this["asg_alert"].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.asg.arn
}

resource "aws_lambda_permission" "sns_critical" {
  statement_id  = "AllowSnsCritical"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this["cloudwatch_alarm"].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.critical.arn
}

# ── CloudWatch 알람 ─────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "assac-alarm-alb-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.internal_alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.critical.arn]
}

resource "aws_cloudwatch_metric_alarm" "asg_cpu" {
  alarm_name          = "assac-alarm-asg-cpu"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 80
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = var.was_asg_name
  }

  alarm_actions = [aws_sns_topic.critical.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "assac-alarm-rds-cpu"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 90
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  alarm_actions = [aws_sns_topic.critical.arn]
}

# WAS 인스턴스 수가 최대치(6대)에 도달하면 운영 호출 Lambda 를 직접 호출한다.
resource "aws_cloudwatch_metric_alarm" "was_capacity_call" {
  alarm_name          = "assac-was-zero-healthy-call"
  namespace           = "AWS/AutoScaling"
  metric_name         = "GroupInServiceInstances"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 6
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    AutoScalingGroupName = var.was_asg_name
  }

  alarm_actions = [aws_lambda_function.this["clawops_call"].arn]
}

resource "aws_lambda_permission" "alarm_clawops" {
  statement_id  = "AllowCloudWatchAlarm"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this["clawops_call"].function_name
  principal     = "lambda.alarms.cloudwatch.amazonaws.com"
  source_arn    = aws_cloudwatch_metric_alarm.was_capacity_call.arn
}

# ── EventBridge ────────────────────────────────────────────────
resource "aws_cloudwatch_event_rule" "asg" {
  name        = "assac-eventbridge-asg-scale-out-alert"
  description = "Triggers assac-lambda-asg-alert when assac-asg-was successfully launches a new EC2 instance."

  event_pattern = jsonencode({
    source = ["aws.autoscaling"]
    detail-type = [
      "EC2 Instance Launch Successful",
      "EC2 Instance Terminate Successful",
      "EC2 Instance Launch Unsuccessful",
      "EC2 Instance Terminate Unsuccessful",
      "EC2 Instance-launch Lifecycle Action",
      "EC2 Instance-terminate Lifecycle Action",
      "EC2 Instance Root Volume Replacement Successful",
      "EC2 Instance Root Volume Replacement Unsuccessful",
    ]
  })
}

resource "aws_cloudwatch_event_target" "asg" {
  rule = aws_cloudwatch_event_rule.asg.name
  arn  = aws_lambda_function.this["asg_alert"].arn
}

resource "aws_lambda_permission" "events_asg" {
  statement_id  = "AllowEventBridgeAsg"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this["asg_alert"].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.asg.arn
}

resource "aws_guardduty_detector" "this" {
  enable = true
}

resource "aws_cloudwatch_event_rule" "guardduty" {
  name        = "assac-eventbridge-guardduty-alert"
  description = "Routes Amazon GuardDuty findings to the Discord alert Lambda function."

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "guardduty" {
  rule = aws_cloudwatch_event_rule.guardduty.name
  arn  = aws_lambda_function.this["guardduty_alert"].arn
}

resource "aws_lambda_permission" "events_guardduty" {
  statement_id  = "AllowEventBridgeGuardDuty"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this["guardduty_alert"].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty.arn
}

# ── 내부 ALB 용 리전 WAF + 차단 로그 → Lambda ────────────────────
resource "aws_wafv2_web_acl" "alb" {
  name  = "assac-waf-alb"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "AWS-AWSManagedRulesCommonRuleSet"
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "AWS-AWSManagedRulesSQLiRuleSet"
    }
  }

  rule {
    name     = "assac-rate-limit"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "assac-rate-limit"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    sampled_requests_enabled   = true
    metric_name                = "assac-waf-alb"
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.internal_alb_arn
  web_acl_arn  = aws_wafv2_web_acl.alb.arn
}

resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-assac"
  retention_in_days = 30
}

resource "aws_wafv2_web_acl_logging_configuration" "alb" {
  resource_arn            = aws_wafv2_web_acl.alb.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  # BLOCK 된 요청만 남긴다.
  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior    = "KEEP"
      requirement = "MEETS_ALL"

      condition {
        action_condition {
          action = "BLOCK"
        }
      }
    }
  }
}

resource "aws_lambda_permission" "logs_waf" {
  statement_id  = "AllowCloudWatchLogs"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this["waf_alert"].function_name
  principal     = "logs.amazonaws.com"
  source_arn    = "${aws_cloudwatch_log_group.waf.arn}:*"
}

resource "aws_cloudwatch_log_subscription_filter" "waf" {
  name            = "assac-lambda-waf-logs"
  log_group_name  = aws_cloudwatch_log_group.waf.name
  filter_pattern  = "{ $.action = \"BLOCK\" }"
  destination_arn = aws_lambda_function.this["waf_alert"].arn

  depends_on = [aws_lambda_permission.logs_waf]
}

# ── CloudTrail (관리 이벤트, 멀티 리전) ──────────────────────────
resource "aws_s3_bucket" "trail" {
  bucket = "assac-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
}

data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid       = "AWSCloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail_bucket.json
}

resource "aws_cloudtrail" "management" {
  name                          = "assac-management-trail"
  s3_bucket_name                = aws_s3_bucket.trail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  advanced_event_selector {
    name = "Management events selector"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  tags = {
    Owner = "assac-ops-pm"
  }

  depends_on = [aws_s3_bucket_policy.trail]
}

# ── 예산 ───────────────────────────────────────────────────────
resource "aws_budgets_budget" "project" {
  name         = "assac-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = length(var.alert_emails) > 0 ? [80, 100] : []

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.alert_emails
    }
  }
}

# ── Amazon Managed Service for Prometheus ─────────────────────
resource "aws_prometheus_workspace" "this" {
  alias = "assac-petclinic-amp"

  tags = {
    Owner = "assac-ops-pm"
  }
}
