# Route 53 호스티드 존과 ALB(ap-northeast-2)용 ACM 인증서.
# 인증서는 origin.<domain> 이름으로 발급해 CloudFront → 외부 ALB 구간을 HTTPS 로 암호화한다.

resource "aws_route53_zone" "this" {
  name    = var.domain_name
  comment = "assac project domain"
}

resource "aws_acm_certificate" "origin" {
  domain_name       = "origin.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "origin_validation" {
  for_each = {
    for o in aws_acm_certificate.origin.domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      record = o.resource_record_value
      type   = o.resource_record_type
    }
  }

  zone_id         = aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "origin" {
  certificate_arn         = aws_acm_certificate.origin.arn
  validation_record_fqdns = [for r in aws_route53_record.origin_validation : r.fqdn]
}
