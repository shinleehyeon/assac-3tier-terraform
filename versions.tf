terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # 문서화 목적의 저장소이므로 원격 백엔드를 두지 않는다.
  # 실제 운영 시에는 S3 백엔드(use_lockfile = true)를 사용했다.
}
