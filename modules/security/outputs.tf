output "ids" {
  description = "이름(bastion, alb_web, web, alb, was, db, lambda, vpce) → 보안 그룹 ID"
  value       = { for k, sg in aws_security_group.this : k => sg.id }
}
