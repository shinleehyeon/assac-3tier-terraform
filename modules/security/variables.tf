variable "vpc_id" {
  type = string
}

variable "admin_ssh_cidrs" {
  type    = list(string)
  default = []
}
