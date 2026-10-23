# Generated from CloudTrail IAM events (final design state before the 10/15 teardown).
# Group -> policy attachments and role -> policy attachments.

locals {
  group_policies = {
    "assac-db-security-admins" = [
      "arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess",
      "arn:aws:iam::aws:policy/AWSBudgetsActionsWithAWSResourceControlAccess",
      "arn:aws:iam::aws:policy/AmazonGuardDutyFullAccess_v2",
      "arn:aws:iam::aws:policy/AmazonRDSFullAccess",
      "arn:aws:iam::aws:policy/AmazonSNSFullAccess",
      "arn:aws:iam::aws:policy/IAMFullAccess",
      "arn:aws:iam::aws:policy/SecretsManagerReadWrite",
      local.custom_policy_arn["assac-policy-rds-console-extras"],
      local.custom_policy_arn["assac-policy-self-mfa"],
    ]
    "assac-edge-security-admins" = [
      "arn:aws:iam::aws:policy/AWSLambda_FullAccess",
      "arn:aws:iam::aws:policy/AWSWAFFullAccess",
      "arn:aws:iam::aws:policy/AmazonRoute53FullAccess",
      "arn:aws:iam::aws:policy/AmazonS3FullAccess",
      "arn:aws:iam::aws:policy/CloudFrontFullAccess",
      "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess",
      "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
      local.custom_policy_arn["assac-policy-edge-extras"],
      local.custom_policy_arn["assac-policy-self-mfa"],
    ]
    "assac-network-admins" = [
      "arn:aws:iam::aws:policy/AmazonEC2FullAccess",
      "arn:aws:iam::aws:policy/AmazonSNSFullAccess",
      "arn:aws:iam::aws:policy/AutoScalingFullAccess",
      "arn:aws:iam::aws:policy/CloudFrontFullAccess",
      "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess",
      local.custom_policy_arn["assac-policy-alb-logs-s3"],
      local.custom_policy_arn["assac-policy-cloudfront-slr"],
      local.custom_policy_arn["assac-policy-ec2-instance-profile-pass"],
      local.custom_policy_arn["assac-policy-self-mfa"],
    ]
    "assac-ops-pm" = [
      "arn:aws:iam::aws:policy/AWSCloudTrail_FullAccess",
      "arn:aws:iam::aws:policy/AWSGrafanaAccountAdministrator",
      "arn:aws:iam::aws:policy/AmazonPrometheusFullAccess",
      "arn:aws:iam::aws:policy/AmazonSNSFullAccess",
      "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
      "arn:aws:iam::aws:policy/CloudWatchFullAccessV2",
      "arn:aws:iam::aws:policy/SecurityAudit",
      local.custom_policy_arn["assac-policy-self-mfa"],
    ]
  }

  role_policies = {
    "assac-grafana-cloud-read-role" = [
      "arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess",
      "arn:aws:iam::aws:policy/CloudWatchLogsReadOnlyAccess",
      "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess",
    ]
    "assac-grafana-role" = [
      local.custom_policy_arn["assac-grafana-amp-query"],
    ]
    "assac-lambda-asg-alert-role" = [
      "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    ]
    "assac-lambda-guardduty-alert-role" = [
      "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    ]
    "assac-lambda-waf-alert-role" = [
      "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    ]
    "assac-role-cloudwatch-agent" = [
      "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
      "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
      "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess",
    ]
    "assac-role-lambda-cloudwatch-alert" = [
      "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    ]
    "assac-terraform-plan" = [
      "arn:aws:iam::aws:policy/ReadOnlyAccess",
    ]
    "rds-monitoring-role" = [
      "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole",
    ]
  }
}
