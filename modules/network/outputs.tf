output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = [aws_subnet.this["public-a"].id, aws_subnet.this["public-c"].id]
}

output "web_subnet_ids" {
  value = [aws_subnet.this["web-a"].id, aws_subnet.this["web-c"].id]
}

output "was_subnet_ids" {
  value = [aws_subnet.this["was-a"].id, aws_subnet.this["was-c"].id]
}

output "db_subnet_ids" {
  value = [aws_subnet.this["db-a"].id, aws_subnet.this["db-c"].id]
}
