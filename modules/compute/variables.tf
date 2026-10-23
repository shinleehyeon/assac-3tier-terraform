variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "web_subnet_ids" {
  type = list(string)
}

variable "was_subnet_ids" {
  type = list(string)
}

variable "sg" {
  description = "security 모듈의 ids 출력"
  type        = map(string)
}

variable "origin_certificate_arn" {
  type = string
}

variable "instance_profile_name" {
  description = "CloudWatch Agent / SSM / ECR 읽기 권한을 가진 인스턴스 프로파일"
  type        = string
}

variable "key_name" {
  type = string
}

variable "web_ami_id" {
  type = string
}

variable "was_ami_id" {
  type = string
}

variable "bastion_ami_id" {
  type = string
}
