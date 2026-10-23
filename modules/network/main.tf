# VPC 10.0.0.0/16 — AZ 두 개(a, c)에 5개 계층 서브넷을 둔다.
#   public(ALB/Bastion)  10.0.0.0/24, 10.0.1.0/24
#   web(Apache)          10.0.5.0/24, 10.0.6.0/24
#   was(Spring)          10.0.10.0/24, 10.0.11.0/24
#   db(RDS/Lambda/VPCE)  10.0.20.0/24, 10.0.21.0/24

locals {
  subnets = {
    public = { cidrs = ["10.0.0.0/24", "10.0.1.0/24"], public = true }
    web    = { cidrs = ["10.0.5.0/24", "10.0.6.0/24"], public = false }
    was    = { cidrs = ["10.0.10.0/24", "10.0.11.0/24"], public = false }
    db     = { cidrs = ["10.0.20.0/24", "10.0.21.0/24"], public = false }
  }

  subnet_list = flatten([
    for tier, cfg in local.subnets : [
      for i, cidr in cfg.cidrs : {
        key    = "${tier}-${substr(var.azs[i], -1, 1)}"
        tier   = tier
        cidr   = cidr
        az     = var.azs[i]
        public = cfg.public
      }
    ]
  ])
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "assac-vpc" }
}

resource "aws_subnet" "this" {
  for_each = { for s in local.subnet_list : s.key => s }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.public

  tags = { Name = "assac-subnet-${each.key}" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "assac-igw" }
}

# Regional NAT Gateway: AZ 별로 NAT 를 두지 않고 하나의 NAT 가 두 AZ 를 담당한다.
resource "aws_nat_gateway" "regional" {
  vpc_id            = aws_vpc.this.id
  availability_mode = "regional"

  tags = { Name = "assac-nat" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "assac-rt-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# web / was 는 NAT 를 통해서만 외부로 나간다.
resource "aws_route_table" "web" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "assac-rt-web" }
}

resource "aws_route" "web_nat" {
  route_table_id         = aws_route_table.web.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.regional.id
}

resource "aws_route_table" "was" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "assac-rt-was" }
}

resource "aws_route" "was_nat" {
  route_table_id         = aws_route_table.was.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.regional.id
}

# db 서브넷은 인터넷 경로가 없다.
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "assac-rt-db" }
}

resource "aws_route_table_association" "this" {
  for_each = aws_subnet.this

  subnet_id = each.value.id
  route_table_id = {
    public = aws_route_table.public.id
    web    = aws_route_table.web.id
    was    = aws_route_table.was.id
    db     = aws_route_table.db.id
  }[split("-", each.key)[0]]
}

# VPC 플로우 로그 → CloudWatch Logs
resource "aws_cloudwatch_log_group" "flow" {
  name              = "/assac/vpc-flowlogs"
  retention_in_days = 30
}

resource "aws_iam_role" "flow" {
  name = "assac-vpc-flowlogs-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow" {
  name = "write-flow-logs"
  role = aws_iam_role.flow.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "${aws_cloudwatch_log_group.flow.arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow.arn
  iam_role_arn             = aws_iam_role.flow.arn
  max_aggregation_interval = 600

  tags = { Name = "assac-vpc-flow-logs" }
}
