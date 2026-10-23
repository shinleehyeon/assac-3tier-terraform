variable "region" {
  type = string
}

variable "alert_emails" {
  type    = list(string)
  default = []
}

variable "budget_limit_usd" {
  type = number
}

variable "internal_alb_arn" {
  type = string
}

variable "internal_alb_arn_suffix" {
  type = string
}

variable "was_asg_name" {
  type = string
}

variable "db_instance_identifier" {
  type = string
}

variable "lambda_role_arns" {
  description = "waf_alert, asg_alert, cloudwatch_alarm, guardduty_alert, clawops_call 롤 ARN"
  type        = map(string)
}

variable "lambda_role_names" {
  description = "위 롤의 이름 (SSM 읽기 권한 부여용)"
  type        = map(string)
}
