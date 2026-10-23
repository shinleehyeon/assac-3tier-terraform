# 엣지 계층: CloudFront + WAF(CLOUDFRONT scope) + ACM + Route 53 + 정적/오류 페이지 S3
# CloudFront 용 인증서·WAF 는 us-east-1 provider 로 만든다.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

data "aws_caller_identity" "current" {}

# ── ACM (us-east-1, CloudFront 전용) ─────────────────────────────
resource "aws_acm_certificate" "cloudfront" {
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cloudfront_validation" {
  for_each = {
    for o in aws_acm_certificate.cloudfront.domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      record = o.resource_record_value
      type   = o.resource_record_type
    }
  }

  zone_id         = var.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for r in aws_route53_record.cloudfront_validation : r.fqdn]
}

# ── 오류 페이지 / 정적 파일 S3 (OAC 로만 접근) ───────────────────
resource "aws_s3_bucket" "error_pages" {
  bucket = "assac-error-pages-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "static" {
  bucket = "assac-static-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "error_pages" {
  bucket                  = aws_s3_bucket.error_pages.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.static.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "static" {
  name                              = "assac-static-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "error_pages" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.error_pages.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "error_pages" {
  bucket = aws_s3_bucket.error_pages.id
  policy = data.aws_iam_policy_document.error_pages.json
}

# ── WAF (CLOUDFRONT scope) ──────────────────────────────────────
resource "aws_wafv2_web_acl" "cloudfront" {
  provider    = aws.us_east_1
  name        = "assac-waf-cloudfront"
  description = "Global WAF Web ACL for protecting the ASSAC PetClinic service behind CloudFront using AWS Managed Rules and rate-based protection"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  custom_response_body {
    key          = "ratelimit-page"
    content_type = "TEXT_HTML"
    content      = file("${path.module}/files/ratelimit.html")
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

  # IP 당 5분 1000회 초과 시 429 + 커스텀 페이지.
  # 부하 테스트 헤더가 있는 요청과 /error-assets/ 요청은 집계에서 제외한다.
  rule {
    name     = "RateLimit"
    priority = 2

    action {
      block {
        custom_response {
          response_code            = 429
          custom_response_body_key = "ratelimit-page"
        }
      }
    }

    statement {
      rate_based_statement {
        limit                 = 1000
        evaluation_window_sec = 300
        aggregate_key_type    = "IP"

        scope_down_statement {
          and_statement {
            statement {
              not_statement {
                statement {
                  byte_match_statement {
                    search_string         = var.load_test_header_value
                    positional_constraint = "EXACTLY"

                    field_to_match {
                      single_header {
                        name = "x-load-test"
                      }
                    }

                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
              }
            }

            statement {
              not_statement {
                statement {
                  byte_match_statement {
                    search_string         = "/error-assets/"
                    positional_constraint = "STARTS_WITH"

                    field_to_match {
                      uri_path {}
                    }

                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      sampled_requests_enabled   = true
      metric_name                = "RateLimit"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    sampled_requests_enabled   = true
    metric_name                = "assac-waf-cloudfront"
  }
}

# ── CloudFront ──────────────────────────────────────────────────
data "aws_cloudfront_cache_policy" "use_origin_headers" {
  name = "UseOriginCacheControlHeaders"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# 정적 자원(Apache/WebJars): 기본 1시간, 최대 1일, 쿠키·헤더·쿼리스트링을 캐시 키에서 제외
resource "aws_cloudfront_cache_policy" "static_1h" {
  name        = "assac-static-1h"
  comment     = "Static assets served by Apache/WebJars: 1h default, no cookies/headers/query in cache key"
  min_ttl     = 0
  default_ttl = 3600
  max_ttl     = 86400

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

locals {
  app_origin_id   = "origin-assac-alb-web"
  error_origin_id = "assac-error-pages-s3"
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2"
  price_class     = "PriceClass_All"
  aliases         = [var.domain_name]
  web_acl_id      = aws_wafv2_web_acl.cloudfront.arn

  # 오리진 1: 외부 ALB (origin.<domain>, HTTPS 전용)
  origin {
    origin_id   = local.app_origin_id
    domain_name = "origin.${var.domain_name}"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }
  }

  # 오리진 2: 오류 페이지 S3 (OAC)
  origin {
    origin_id                = local.error_origin_id
    domain_name              = aws_s3_bucket.error_pages.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id
  }

  default_cache_behavior {
    target_origin_id       = local.app_origin_id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.use_origin_headers.id
  }

  dynamic "ordered_cache_behavior" {
    for_each = ["/resources/*", "/stylesheets/*", "/javascripts/*"]

    content {
      path_pattern           = ordered_cache_behavior.value
      target_origin_id       = local.app_origin_id
      viewer_protocol_policy = "redirect-to-https"
      compress               = true
      allowed_methods        = ["GET", "HEAD"]
      cached_methods         = ["GET", "HEAD"]
      cache_policy_id        = aws_cloudfront_cache_policy.static_1h.id
    }
  }

  ordered_cache_behavior {
    path_pattern           = "/webjars/*"
    target_origin_id       = local.app_origin_id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  ordered_cache_behavior {
    path_pattern           = "/error-assets/*"
    target_origin_id       = local.error_origin_id
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cloudfront.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name  = "assac-cdn"
    Owner = "assac-edge-security-admins"
  }
}

# ── Route 53 레코드 ─────────────────────────────────────────────
resource "aws_route53_record" "apex" {
  zone_id = var.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "origin" {
  zone_id = var.zone_id
  name    = "origin.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.web_alb_dns_name
    zone_id                = var.web_alb_zone_id
    evaluate_target_health = true
  }
}
