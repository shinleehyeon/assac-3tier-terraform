output "web_alb_arn" {
  value = aws_lb.web.arn
}

output "web_alb_dns_name" {
  value = aws_lb.web.dns_name
}

output "web_alb_zone_id" {
  value = aws_lb.web.zone_id
}

output "internal_alb_arn" {
  value = aws_lb.internal.arn
}

output "internal_alb_arn_suffix" {
  value = aws_lb.internal.arn_suffix
}

output "was_asg_name" {
  value = aws_autoscaling_group.was.name
}

output "web_asg_name" {
  value = aws_autoscaling_group.web.name
}
