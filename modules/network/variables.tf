variable "vpc_cidr" {
  type = string
}

variable "azs" {
  description = "사용할 AZ (a, c)"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}
