output "zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "origin_certificate_arn" {
  value = aws_acm_certificate_validation.origin.certificate_arn
}
