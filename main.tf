# ASSAC PetClinic — 3-Tier on AWS
#
# 사용자 → Route 53 → CloudFront(+WAF) → 외부 ALB → Web(Apache, ASG)
#        → 내부 ALB(+WAF) → WAS(Spring PetClinic in Docker, ASG) → RDS MySQL Multi-AZ

data "aws_caller_identity" "current" {}

module "network" {
  source   = "./modules/network"
  vpc_cidr = var.vpc_cidr
}

module "security" {
  source          = "./modules/security"
  vpc_id          = module.network.vpc_id
  admin_ssh_cidrs = var.admin_ssh_cidrs
}

module "iam" {
  source = "./modules/iam"

  github_repo               = var.github_repo
  terraform_plan_principals = var.terraform_plan_principals
  grafana_cloud_account_id  = var.grafana_cloud_account_id
  grafana_external_id       = var.grafana_external_id
}

module "dns" {
  source      = "./modules/dns"
  domain_name = var.domain_name
}

module "database" {
  source = "./modules/database"

  region                   = var.aws_region
  vpc_id                   = module.network.vpc_id
  db_subnet_ids            = module.network.db_subnet_ids
  db_security_group_id     = module.security.ids["db"]
  lambda_security_group_id = module.security.ids["lambda"]
  vpce_security_group_id   = module.security.ids["vpce"]
  master_username          = var.db_master_username
  master_password          = var.db_master_password
}

module "compute" {
  source = "./modules/compute"

  vpc_id                 = module.network.vpc_id
  public_subnet_ids      = module.network.public_subnet_ids
  web_subnet_ids         = module.network.web_subnet_ids
  was_subnet_ids         = module.network.was_subnet_ids
  sg                     = module.security.ids
  origin_certificate_arn = module.dns.origin_certificate_arn
  instance_profile_name  = module.iam.instance_profile_name
  key_name               = var.key_name
  web_ami_id             = var.web_ami_id
  was_ami_id             = var.was_ami_id
  bastion_ami_id         = var.bastion_ami_id
}

module "edge" {
  source = "./modules/edge"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  domain_name            = var.domain_name
  zone_id                = module.dns.zone_id
  web_alb_dns_name       = module.compute.web_alb_dns_name
  web_alb_zone_id        = module.compute.web_alb_zone_id
  load_test_header_value = var.load_test_header_value
}

module "observability" {
  source = "./modules/observability"

  region                  = var.aws_region
  alert_emails            = var.alert_emails
  budget_limit_usd        = var.budget_limit_usd
  internal_alb_arn        = module.compute.internal_alb_arn
  internal_alb_arn_suffix = module.compute.internal_alb_arn_suffix
  was_asg_name            = module.compute.was_asg_name
  db_instance_identifier  = module.database.db_instance_identifier
  lambda_role_arns        = module.iam.lambda_role_arns
  lambda_role_names       = module.iam.lambda_role_names
}

module "cicd" {
  source = "./modules/cicd"
}
