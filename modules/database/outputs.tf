output "db_address" {
  value = aws_db_instance.petclinic.address
}

output "secret_arn" {
  value = aws_secretsmanager_secret.rds.arn
}

output "db_instance_identifier" {
  value = aws_db_instance.petclinic.identifier
}
