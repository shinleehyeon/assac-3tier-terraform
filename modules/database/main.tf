# RDS MySQL 8.4.9 Multi-AZ + Secrets Manager 자동 로테이션

resource "aws_db_subnet_group" "this" {
  name        = "assac-sng-petclinic"
  description = "assac-rds-petclinic-subnet"
  subnet_ids  = var.db_subnet_ids
}

resource "aws_db_parameter_group" "this" {
  name        = "assac-parameter-group-petclinic"
  family      = "mysql8.4"
  description = "assac-parameter-group-petclinic"
}

# 향상된 모니터링(15초) 용 롤
resource "aws_iam_role" "rds_monitoring" {
  name = "rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "petclinic" {
  identifier = "assac-rds-petclinic"

  engine         = "mysql"
  engine_version = "8.4.9"
  instance_class = "db.t3.small"
  multi_az       = true

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  username = var.master_username
  password = var.master_password
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false

  backup_retention_period    = 7
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true
  deletion_protection        = true

  monitoring_interval             = 15
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  ca_cert_identifier  = "rds-ca-rsa2048-g1"
  skip_final_snapshot = true

  tags = {
    Owner = "data-security-admin"
  }

  lifecycle {
    # 비밀번호는 Secrets Manager 로테이션이 교체한다.
    ignore_changes = [password]
  }
}

# ── Secrets Manager: 접속 정보 + 30일 자동 로테이션 ─────────────────
resource "aws_secretsmanager_secret" "rds" {
  name        = "assac/rds/petclinic"
  description = "PetClinic RDS 마스터 자격 증명 (RDS 자동 연동 + 로테이션 대상)"
}

resource "aws_secretsmanager_secret_version" "rds" {
  secret_id = aws_secretsmanager_secret.rds.id

  secret_string = jsonencode({
    engine   = "mysql"
    host     = aws_db_instance.petclinic.address
    port     = 3306
    dbname   = "petclinic"
    username = var.master_username
    password = var.master_password
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# 로테이션 Lambda: AWS 가 제공하는 "단일 사용자 MySQL" 로테이션 앱을 DB 서브넷에 배치
resource "aws_serverlessapplicationrepository_cloudformation_stack" "rotation" {
  name           = "SecretsManagerassac-lambda-SecretsManager"
  application_id = "arn:aws:serverlessrepo:us-east-1:297356786399:applications/SecretsManagerRDSMySQLRotationSingleUser"
  capabilities   = ["CAPABILITY_IAM", "CAPABILITY_RESOURCE_POLICY"]

  parameters = {
    endpoint            = "https://secretsmanager.${var.region}.amazonaws.com"
    functionName        = "SecretsManagerassac-lambda-SecretsManager"
    vpcSubnetIds        = join(",", var.db_subnet_ids)
    vpcSecurityGroupIds = var.lambda_security_group_id
  }
}

resource "aws_secretsmanager_secret_rotation" "rds" {
  secret_id           = aws_secretsmanager_secret.rds.id
  rotation_lambda_arn = aws_serverlessapplicationrepository_cloudformation_stack.rotation.outputs["RotationLambdaARN"]

  rotation_rules {
    schedule_expression = "rate(30 days)"
  }
}

# 인터넷 경로가 없는 DB 서브넷의 Lambda 와 WAS 가 Secrets Manager 에 닿도록 하는 인터페이스 엔드포인트
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.db_subnet_ids
  security_group_ids  = [var.vpce_security_group_id]
  private_dns_enabled = true

  tags = { Name = "assac-vpc-endpoint" }
}
