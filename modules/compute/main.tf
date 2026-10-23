# 외부 ALB(internet-facing) → Web(Apache) ASG → 내부 ALB → WAS(Spring) ASG

data "aws_caller_identity" "current" {}
data "aws_elb_service_account" "this" {}

# ── ALB 액세스 로그 버킷 ────────────────────────────────────────
resource "aws_s3_bucket" "logs" {
  bucket = "assac-logs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAlbAccessLogs"
      Effect    = "Allow"
      Principal = { AWS = data.aws_elb_service_account.this.arn }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.logs.arn}/*"
    }]
  })
}

# ── 외부 ALB (CloudFront 의 오리진) ──────────────────────────────
resource "aws_lb" "web" {
  name               = "assac-alb-web"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.sg["alb_web"]]

  access_logs {
    bucket  = aws_s3_bucket.logs.id
    prefix  = "assac-logs-web-alb-access"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.logs]
}

resource "aws_lb_target_group" "web" {
  name        = "assac-tg-web"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "web_https" {
  load_balancer_arn = aws_lb.web.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
  certificate_arn   = var.origin_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_listener" "web_http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ── 내부 ALB (Apache → Spring) ──────────────────────────────────
resource "aws_lb" "internal" {
  name               = "assac-alb-internal"
  load_balancer_type = "application"
  internal           = true
  subnets            = var.public_subnet_ids
  security_groups    = [var.sg["alb"]]

  access_logs {
    bucket  = aws_s3_bucket.logs.id
    prefix  = "assac-logs-alb-access"
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.logs]
}

resource "aws_lb_target_group" "was" {
  name                 = "assac-tg-was"
  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "instance"
  deregistration_delay = 60

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  tags = {
    Owner = "network-admin"
  }
}

resource "aws_lb_listener" "internal_http" {
  load_balancer_arn = aws_lb.internal.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.was.arn
  }
}

# ── Bastion ─────────────────────────────────────────────────────
resource "aws_instance" "bastion" {
  ami                         = var.bastion_ami_id
  instance_type               = "t3.micro"
  subnet_id                   = var.public_subnet_ids[0]
  vpc_security_group_ids      = [var.sg["bastion"]]
  key_name                    = var.key_name
  associate_public_ip_address = true

  tags = { Name = "assac-bastion" }
}

# ── Web(Apache) Auto Scaling ────────────────────────────────────
resource "aws_launch_template" "web" {
  name          = "assac-template-web"
  image_id      = var.web_ami_id
  instance_type = "t3.small"
  key_name      = var.key_name

  iam_instance_profile {
    name = var.instance_profile_name
  }

  network_interfaces {
    device_index    = 0
    security_groups = [var.sg["web"]]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name  = "assac-asg-web"
      Owner = "network-admin"
    }
  }
}

resource "aws_autoscaling_group" "web" {
  name                      = "assac-asg-web"
  min_size                  = 2
  max_size                  = 6
  desired_capacity          = 2
  vpc_zone_identifier       = var.web_subnet_ids
  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  # 새 AMI/이미지 배포 = Instance Refresh (절반은 항상 살려 두고 교체)
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 60
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

resource "aws_autoscaling_policy" "web_cpu" {
  name                      = "assac-asg-web-scaling-policy"
  autoscaling_group_name    = aws_autoscaling_group.web.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 300

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70
  }
}

# ── WAS(Spring PetClinic in Docker) Auto Scaling ────────────────
resource "aws_launch_template" "was" {
  name          = "assac-template"
  image_id      = var.was_ami_id
  instance_type = "t3.medium"
  key_name      = var.key_name

  iam_instance_profile {
    name = var.instance_profile_name
  }

  monitoring {
    enabled = true
  }

  network_interfaces {
    device_index    = 0
    security_groups = [var.sg["was"]]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name  = "assac-asg-was"
      Owner = "app-admin"
    }
  }
}

resource "aws_autoscaling_group" "was" {
  name                      = "assac-asg-was"
  min_size                  = 2
  max_size                  = 6
  desired_capacity          = 2
  vpc_zone_identifier       = var.was_subnet_ids
  target_group_arns         = [aws_lb_target_group.was.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.was.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 60
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

resource "aws_autoscaling_policy" "was_cpu" {
  name                      = "assac-asg-scaling-policy"
  autoscaling_group_name    = aws_autoscaling_group.was.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 300

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value     = 70
    disable_scale_in = false
  }
}
