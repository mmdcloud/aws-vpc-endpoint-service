provider "aws" {
  region = var.aws_region
}

# Dedicated security group for the Interface VPC Endpoint ENIs
resource "aws_security_group" "endpoint_client_sg" {
  name_prefix = "privatelink-consumer-ep-sg-"
  description = "Security group for PrivateLink Interface VPC Endpoint ENIs"
  vpc_id      = var.consumer_vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

# Ingress: Allow consumer workloads to talk to the endpoint on the service port
resource "aws_vpc_security_group_ingress_rule" "allow_consumer_workloads" {
  security_group_id = aws_security_group.endpoint_client_sg.id
  description       = "Allow inbound traffic from consumer VPC to PrivateLink interface"
  cidr_ipv4         = "0.0.0.0/0" # Scope to consumer VPC CIDR or specific client security group in production
  from_port         = var.service_port
  to_port           = var.service_port
  ip_protocol       = "tcp"
}

# Interface VPC Endpoint
resource "aws_vpc_endpoint" "service_endpoint" {
  vpc_id              = var.consumer_vpc_id
  service_name        = var.endpoint_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.consumer_subnet_ids
  security_group_ids  = [aws_security_group.endpoint_client_sg.id]
  private_dns_enabled = var.private_dns_enabled

  tags = merge(
    {
      Name = "privatelink-consumer-endpoint"
    },
    var.tags
  )
}

