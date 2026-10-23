variable "domain_name" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "web_alb_dns_name" {
  type = string
}

variable "web_alb_zone_id" {
  type = string
}

variable "load_test_header_value" {
  type      = string
  sensitive = true
}
