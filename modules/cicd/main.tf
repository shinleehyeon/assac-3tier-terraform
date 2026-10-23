# CI/CD: GitHub Actions 가 이미지를 빌드해 ECR 에 푸시하고,
# ASG Instance Refresh 로 새 이미지를 기동한다.
#   assac-ecr      WAS(Spring PetClinic) 이미지
#   assac-ecr-web  Web(Apache) 이미지

resource "aws_ecr_repository" "this" {
  for_each = toset(["assac-ecr", "assac-ecr-web"])

  name                 = each.key
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}
