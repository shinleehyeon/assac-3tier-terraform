provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "petclinic"
      Team      = "ASSAC"
      ManagedBy = "terraform"
    }
  }
}

# CloudFront 용 ACM 인증서와 WAF(CLOUDFRONT scope)는 us-east-1 에만 만들 수 있다.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "petclinic"
      Team      = "ASSAC"
      ManagedBy = "terraform"
    }
  }
}
