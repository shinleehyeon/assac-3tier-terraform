variable "aws_region" {
  description = "주 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "domain_name" {
  description = "서비스 도메인 (Route 53 호스티드 존)"
  type        = string
  default     = "assac.cloud"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "key_name" {
  description = "EC2 키 페어 이름"
  type        = string
  default     = "assac-keypair"
}

variable "web_ami_id" {
  description = "Apache(WEB) 서버 AMI. 운영 중 직접 구운 AMI 를 사용했다."
  type        = string
}

variable "was_ami_id" {
  description = "WAS(Docker 로 PetClinic 컨테이너 기동) 서버 AMI"
  type        = string
}

variable "bastion_ami_id" {
  description = "Bastion 호스트 AMI"
  type        = string
}

variable "admin_ssh_cidrs" {
  description = "Bastion SSH 를 허용할 관리자 IP 대역"
  type        = list(string)
  default     = []
}

variable "db_master_username" {
  type    = string
  default = "assac"
}

variable "db_master_password" {
  description = "RDS 최초 마스터 비밀번호. 이후 Secrets Manager 로테이션이 값을 교체한다."
  type        = string
  sensitive   = true
}

variable "alert_emails" {
  description = "SNS 이메일 알림 수신자"
  type        = list(string)
  default     = []
}

variable "budget_limit_usd" {
  type    = number
  default = 350
}

variable "load_test_header_value" {
  description = "부하 테스트 트래픽(x-load-test 헤더)을 WAF rate limit 에서 제외하기 위한 값"
  type        = string
  sensitive   = true
}

variable "github_repo" {
  description = "ECR 푸시를 허용할 GitHub 저장소 (org/repo)"
  type        = string
}

variable "terraform_plan_principals" {
  description = "assac-terraform-plan 롤을 AssumeRole 할 수 있는 IAM 사용자 ARN"
  type        = list(string)
  default     = []
}

variable "grafana_external_id" {
  description = "Grafana Cloud 가 CloudWatch 를 읽을 때 사용하는 External ID"
  type        = string
  sensitive   = true
  default     = ""
}

variable "grafana_cloud_account_id" {
  description = "Grafana Cloud 의 AWS 계정 ID"
  type        = string
  default     = ""
}
