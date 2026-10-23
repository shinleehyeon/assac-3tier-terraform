output "cloudfront_domain_name" {
  value = module.edge.distribution_domain_name
}

output "ecr_repository_urls" {
  value = module.cicd.repository_urls
}

output "github_actions_role_arn" {
  value = module.iam.github_actions_role_arn
}
