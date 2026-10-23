# IAM — 팀(역할)별 그룹, 서비스 롤, GitHub Actions OIDC 롤
#
# 그룹 4개는 담당 영역별 권한을 가진다.
#   assac-network-admins        VPC / ALB / ASG / CloudFront
#   assac-db-security-admins    RDS / Secrets Manager / GuardDuty / 비용
#   assac-edge-security-admins  Route 53 / CloudFront / WAF / Lambda / S3
#   assac-ops-pm                CloudWatch / SNS / CloudTrail / Prometheus / Grafana
# 그룹에 붙는 관리형·사용자 정의 정책 목록은 generated.tf 에 있다.

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # policies/*.json 을 사용자 정의 정책으로 만든다. (ACCOUNT_ID 는 현재 계정으로 치환)
  custom_policy_files = fileset("${path.module}/policies", "*.json")
  custom_policy_names = [for f in local.custom_policy_files : trimsuffix(f, ".json")]

  custom_policy_arn = {
    for n in local.custom_policy_names : n => aws_iam_policy.custom[n].arn
  }
}

resource "aws_iam_policy" "custom" {
  for_each = toset(local.custom_policy_names)

  name   = each.value
  policy = replace(file("${path.module}/policies/${each.value}.json"), "ACCOUNT_ID", local.account_id)
}

# ── 그룹 ──────────────────────────────────────────────────────
resource "aws_iam_group" "this" {
  for_each = local.group_policies

  name = each.key
}

resource "aws_iam_group_policy_attachment" "this" {
  for_each = merge([
    for g, pols in local.group_policies : {
      for i, p in pols : "${g}:${i}" => { group = g, policy = p }
    }
  ]...)

  group      = aws_iam_group.this[each.value.group].name
  policy_arn = each.value.policy
}

# ── 서비스 롤 ─────────────────────────────────────────────────
locals {
  service_roles = {
    "assac-role-cloudwatch-agent"        = { service = "ec2.amazonaws.com", path = "/" }
    "assac-grafana-role"                 = { service = "ec2.amazonaws.com", path = "/" }
    "assac-lambda-waf-alert-role"        = { service = "lambda.amazonaws.com", path = "/" }
    "assac-lambda-asg-alert-role"        = { service = "lambda.amazonaws.com", path = "/" }
    "assac-role-lambda-cloudwatch-alert" = { service = "lambda.amazonaws.com", path = "/" }
    "assac-lambda-guardduty-alert-role"  = { service = "lambda.amazonaws.com", path = "/" }
    "assac-clawops-call-role-e5cl1yy8"   = { service = "lambda.amazonaws.com", path = "/service-role/" }
  }
}

resource "aws_iam_role" "service" {
  for_each = local.service_roles

  name = each.key
  path = each.value.path

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = each.value.service }
      Action    = "sts:AssumeRole"
    }]
  })
}

# EC2 인스턴스(Web/WAS)가 쓰는 인스턴스 프로파일: CloudWatch Agent + SSM + ECR 읽기
resource "aws_iam_instance_profile" "ec2" {
  name = "assac-role-cloudwatch-agent"
  role = aws_iam_role.service["assac-role-cloudwatch-agent"].name
}

# ── GitHub Actions → ECR 푸시 (OIDC, 장기 액세스 키 없음) ─────────
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_actions" {
  name = "assac-role-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*" }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "github_ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.custom["assac-policy-ci-ecr-push"].arn
}

# ── 팀원용 terraform plan 전용(ReadOnly) 롤 ──────────────────────
resource "aws_iam_role" "terraform_plan" {
  count = length(var.terraform_plan_principals) > 0 ? 1 : 0

  name        = "assac-terraform-plan"
  description = "Read-only role for team terraform plan (no apply)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.terraform_plan_principals }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_plan" {
  count = length(var.terraform_plan_principals) > 0 ? 1 : 0

  role       = aws_iam_role.terraform_plan[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ── Grafana Cloud 가 CloudWatch/Prometheus 를 읽는 크로스 계정 롤 ───
resource "aws_iam_role" "grafana_cloud_read" {
  count = var.grafana_cloud_account_id != "" ? 1 : 0

  name        = "assac-grafana-cloud-read-role"
  description = "Grafana Cloud read access to CloudWatch/Prometheus via cross-account role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${var.grafana_cloud_account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "sts:ExternalId" = var.grafana_external_id }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "grafana_cloud_read" {
  for_each = var.grafana_cloud_account_id != "" ? toset(local.role_policies["assac-grafana-cloud-read-role"]) : toset([])

  role       = aws_iam_role.grafana_cloud_read[0].name
  policy_arn = each.value
}

# ── 서비스 롤에 붙는 정책 ─────────────────────────────────────
resource "aws_iam_role_policy_attachment" "service" {
  for_each = merge([
    for r, pols in local.role_policies : {
      for i, p in pols : "${r}:${i}" => { role = r, policy = p }
    } if contains(keys(local.service_roles), r)
  ]...)

  role       = aws_iam_role.service[each.value.role].name
  policy_arn = each.value.policy
}
