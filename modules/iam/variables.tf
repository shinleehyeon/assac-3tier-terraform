variable "github_repo" {
  type = string
}

variable "terraform_plan_principals" {
  type    = list(string)
  default = []
}

variable "grafana_cloud_account_id" {
  type    = string
  default = ""
}

variable "grafana_external_id" {
  type      = string
  sensitive = true
  default   = ""
}
