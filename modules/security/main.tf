# 계층별 보안 그룹. 모든 허용은 "이전 계층의 보안 그룹" 을 소스로 지정한다.
#
#   CloudFront ─443→ alb_web ─80→ web(Apache) ─80→ alb(internal) ─8080→ was ─3306→ db

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

locals {
  groups = {
    bastion = "Security group for Bastion host"
    alb_web = "Security group for WEB ALB"
    web     = "Security group for WEB Apache server"
    alb     = "Security group for internal ALB"
    was     = "Security group for WAS servers"
    db      = "Security group for RDS database"
    lambda  = "Security group for VPC Lambda functions"
    vpce    = "vpc endpoint"
  }

  names = {
    bastion = "assac-sg-bastion"
    alb_web = "assac-sg-alb-web"
    web     = "assac-sg-web"
    alb     = "assac-sg-alb"
    was     = "assac-sg-was"
    db      = "assac-sg-db"
    lambda  = "assac-lambda-sg"
    vpce    = "assac-sg-vpce"
  }
}

resource "aws_security_group" "this" {
  for_each = local.groups

  name        = local.names[each.key]
  description = each.value
  vpc_id      = var.vpc_id

  tags = { Name = local.names[each.key] }
}

# ── 모든 그룹: 아웃바운드 전체 허용 ───────────────────────────────
resource "aws_vpc_security_group_egress_rule" "all" {
  for_each = aws_security_group.this

  security_group_id = each.value.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ── Bastion: 관리자 IP 에서만 SSH ────────────────────────────────
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.admin_ssh_cidrs)

  security_group_id = aws_security_group.this["bastion"].id
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}

# ── 외부 ALB: CloudFront 오리진 전용 프리픽스 리스트의 443 만 허용 ────
resource "aws_vpc_security_group_ingress_rule" "alb_web_https" {
  security_group_id = aws_security_group.this["alb_web"].id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  description       = "CloudFront origin-facing only"
}

# ── Web(Apache) ────────────────────────────────────────────────
resource "aws_vpc_security_group_ingress_rule" "web_http_from_alb_web" {
  security_group_id            = aws_security_group.this["web"].id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.this["alb_web"].id
}

resource "aws_vpc_security_group_ingress_rule" "web_ssh_from_bastion" {
  security_group_id            = aws_security_group.this["web"].id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.this["bastion"].id
}

# ── 내부 ALB: Apache 에서만 80 ───────────────────────────────────
resource "aws_vpc_security_group_ingress_rule" "alb_from_web" {
  security_group_id            = aws_security_group.this["alb"].id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.this["web"].id
  description                  = "Apache to Internal ALB"
}

# ── WAS: 내부 ALB 에서 8080, Bastion 에서 SSH ────────────────────
resource "aws_vpc_security_group_ingress_rule" "was_from_alb" {
  security_group_id            = aws_security_group.this["was"].id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.this["alb"].id
}

resource "aws_vpc_security_group_ingress_rule" "was_ssh_from_bastion" {
  security_group_id            = aws_security_group.this["was"].id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.this["bastion"].id
}

# ── DB: WAS 와 로테이션 Lambda 에서만 3306 ───────────────────────
resource "aws_vpc_security_group_ingress_rule" "db_from_was" {
  security_group_id            = aws_security_group.this["db"].id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.this["was"].id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_lambda" {
  security_group_id            = aws_security_group.this["db"].id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.this["lambda"].id
}

# ── Secrets Manager VPC 엔드포인트: WAS / Lambda 에서 443 ─────────
resource "aws_vpc_security_group_ingress_rule" "vpce_from_was" {
  security_group_id            = aws_security_group.this["vpce"].id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.this["was"].id
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_lambda" {
  security_group_id            = aws_security_group.this["vpce"].id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.this["lambda"].id
}
