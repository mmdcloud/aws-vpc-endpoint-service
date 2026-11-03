locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Determine target availability zones (select up to 3 AZs)
  azs = var.availability_zones != null ? var.availability_zones : slice(
    data.aws_availability_zones.available.names,
    0,
    min(3, length(data.aws_availability_zones.available.names))
  )

  # Resolve VPC and Subnets
  vpc_id     = var.create_vpc ? aws_vpc.service_vpc[0].id : var.existing_vpc_id
  subnet_ids = var.create_vpc ? aws_subnet.private[*].id : var.existing_subnet_ids

  # Normalized health check path
  health_check_path = contains(["HTTP", "HTTPS"], var.health_check_protocol) ? (
    var.health_check_path != null ? var.health_check_path : "/"
  ) : null

  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ==============================================================================
# Dedicated VPC and Subnet Resources (Provisioned when var.create_vpc is true)
# ==============================================================================

resource "aws_vpc" "service_vpc" {
  count = var.create_vpc ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${locals.name_prefix}-vpc"
  }
}

# Lockdown default security group of VPC (CIS AWS Foundations Benchmark)
resource "aws_default_security_group" "default" {
  count = var.create_vpc ? 1 : 0

  vpc_id = aws_vpc.service_vpc[0].id

  tags = {
    Name = "${locals.name_prefix}-default-sg-locked"
  }
}

resource "aws_subnet" "private" {
  count = var.create_vpc ? length(locals.azs) : 0

  vpc_id                  = aws_vpc.service_vpc[0].id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = locals.azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${locals.name_prefix}-private-subnet-${locals.azs[count.index]}"
    Type = "Private"
  }
}

resource "aws_route_table" "private" {
  count = var.create_vpc ? 1 : 0

  vpc_id = aws_vpc.service_vpc[0].id

  tags = {
    Name = "${locals.name_prefix}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = var.create_vpc ? length(locals.azs) : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}

# ==============================================================================
# Security Groups (NLB and Backend Targets)
# ==============================================================================

# Security Group attached to the Network Load Balancer
resource "aws_security_group" "nlb_sg" {
  name_prefix = "${locals.name_prefix}-nlb-sg-"
  description = "Security group for PrivateLink Network Load Balancer"
  vpc_id      = locals.vpc_id

  tags = {
    Name = "${locals.name_prefix}-nlb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Ingress: Allow service port traffic to the NLB from VPC & PrivateLink Interface Endpoints
resource "aws_vpc_security_group_ingress_rule" "nlb_ingress" {
  security_group_id = aws_security_group.nlb_sg.id
  description       = "Allow inbound traffic to NLB on service port"
  cidr_ipv4         = "0.0.0.0/0" # PrivateLink endpoints proxy connections via AWS internal backbone
  from_port         = var.service_port
  to_port           = var.service_port
  ip_protocol       = "tcp"
}

# Egress: Forward traffic from NLB to backend targets
resource "aws_vpc_security_group_egress_rule" "nlb_egress_backend" {
  security_group_id = aws_security_group.nlb_sg.id
  description       = "Forward traffic from NLB to backend target instances"
  from_port         = var.service_port
  to_port           = var.service_port
  ip_protocol       = "tcp"
  cidr_ipv4         = var.create_vpc ? aws_vpc.service_vpc[0].cidr_block : "0.0.0.0/0"
}

# Security Group attached to backend target instances
resource "aws_security_group" "backend_sg" {
  name_prefix = "${locals.name_prefix}-backend-sg-"
  description = "Security group for backend target instances receiving PrivateLink traffic"
  vpc_id      = locals.vpc_id

  tags = {
    Name = "${locals.name_prefix}-backend-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Ingress: Allow traffic on service port strictly from the NLB security group and NLB subnets
resource "aws_vpc_security_group_ingress_rule" "backend_from_nlb" {
  security_group_id            = aws_security_group.backend_sg.id
  description                  = "Allow inbound traffic from NLB security group on service port"
  referenced_security_group_id = aws_security_group.nlb_sg.id
  from_port                    = var.service_port
  to_port                      = var.service_port
  ip_protocol                  = "tcp"
}

# Ingress for NLB health check probes (if health check port differs from service port)
resource "aws_vpc_security_group_ingress_rule" "backend_health_check" {
  count = var.health_check_port != "traffic-port" && var.health_check_port != tostring(var.service_port) ? 1 : 0

  security_group_id            = aws_security_group.backend_sg.id
  description                  = "Allow health checks from NLB security group"
  referenced_security_group_id = aws_security_group.nlb_sg.id
  from_port                    = tonumber(var.health_check_port)
  to_port                      = tonumber(var.health_check_port)
  ip_protocol                  = "tcp"
}

# Egress: Outbound for package updates / AWS SSM agent communication
resource "aws_vpc_security_group_egress_rule" "backend_egress_all" {
  security_group_id = aws_security_group.backend_sg.id
  description       = "Allow outbound HTTPS for Systems Manager Session Manager & updates"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# ==============================================================================
# Sample Backend EC2 Targets (Provisioned when var.enable_sample_backend is true)
# ==============================================================================

# Fetch latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  count       = var.enable_sample_backend ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# IAM Role for Backend Instances (Enables AWS Systems Manager Session Manager)
resource "aws_iam_role" "backend_role" {
  count = var.enable_sample_backend ? 1 : 0

  name_prefix = "${locals.name_prefix}-backend-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${locals.name_prefix}-backend-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  count = var.enable_sample_backend ? 1 : 0

  role       = aws_iam_role.backend_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "backend_profile" {
  count = var.enable_sample_backend ? 1 : 0

  name_prefix = "${locals.name_prefix}-backend-profile-"
  role        = aws_iam_role.backend_role[0].name

  tags = {
    Name = "${locals.name_prefix}-backend-profile"
  }
}

# Launch sample backend instances across private subnets
resource "aws_instance" "sample_backend" {
  count = var.enable_sample_backend ? var.sample_backend_instance_count : 0

  ami                    = data.aws_ami.amazon_linux_2023[0].id
  instance_type          = var.sample_backend_instance_type
  subnet_id              = locals.subnet_ids[count.index % length(locals.subnet_ids)]
  vpc_security_group_ids = [aws_security_group.backend_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.backend_profile[0].name

  # Enforce IMDSv2 for CIS / AWS Security Best Practice
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 20
  }

  # Embedded lightweight server listening on var.service_port
  user_data = <<-EOF
              #!/bin/bash
              set -e
              yum update -y
              yum install -y python3

              cat << 'SERVER' > /opt/mock_service.py
              import http.server
              import socketserver
              import socket
              import json
              from datetime import datetime

              PORT = ${var.service_port}

              class HealthHandler(http.server.SimpleHTTPRequestHandler):
                  def do_GET(self):
                      self.send_response(200)
                      self.send_header('Content-type', 'application/json')
                      self.end_headers()
                      response = {
                          "status": "healthy",
                          "service": "${var.project_name}",
                          "hostname": socket.gethostname(),
                          "client_address": self.client_address[0],
                          "timestamp": datetime.utcnow().isoformat() + "Z"
                      }
                      self.wfile.write(json.dumps(response).encode())

                  def do_HEAD(self):
                      self.send_response(200)
                      self.end_headers()

              with socketserver.TCPServer(("", PORT), HealthHandler) as httpd:
                  httpd.serve_forever()
              SERVER

              cat << 'UNIT' > /etc/systemd/system/mock-service.service
              [Unit]
              Description=Mock PrivateLink Backend Service
              After=network.target

              [Service]
              Type=simple
              User=root
              ExecStart=/usr/bin/python3 /opt/mock_service.py
              Restart=always

              [Install]
              WantedBy=multi-user.target
              UNIT

              systemctl daemon-reload
              systemctl enable mock-service
              systemctl start mock-service
              EOF

  tags = {
    Name = "${locals.name_prefix}-backend-${count.index + 1}"
    Role = "PrivateLinkBackend"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

# Attach sample instances to the Target Group
resource "aws_lb_target_group_attachment" "sample_attachment" {
  count = var.enable_sample_backend && var.target_type == "instance" ? var.sample_backend_instance_count : 0

  target_group_arn = aws_lb_target_group.service_tg.arn
  target_id        = aws_instance.sample_backend[count.index].id
  port             = var.service_port
}


# ==============================================================================
# Network Load Balancer (NLB) for AWS PrivateLink
# ==============================================================================

resource "aws_lb" "nlb" {
  name                             = substr("${locals.name_prefix}-nlb", 0, 32)
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = locals.subnet_ids
  security_groups                  = [aws_security_group.nlb_sg.id]
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing
  enable_deletion_protection       = var.enable_deletion_protection

  dynamic "access_logs" {
    for_each = var.enable_access_logs && var.access_logs_s3_bucket != null ? [1] : []
    content {
      bucket  = var.access_logs_s3_bucket
      prefix  = var.access_logs_s3_prefix
      enabled = true
    }
  }

  tags = {
    Name = "${locals.name_prefix}-nlb"
    Role = "PrivateLinkServiceLB"
  }
}

# ==============================================================================
# Target Group
# ==============================================================================

resource "aws_lb_target_group" "service_tg" {
  name                 = substr("${locals.name_prefix}-tg", 0, 32)
  port                 = var.service_port
  protocol             = var.target_protocol
  vpc_id               = locals.vpc_id
  target_type          = var.target_type
  deregistration_delay = var.deregistration_delay
  preserve_client_ip   = var.preserve_client_ip
  proxy_protocol_v2    = var.enable_proxy_protocol_v2

  health_check {
    enabled             = true
    protocol            = var.health_check_protocol
    port                = var.health_check_port
    path                = locals.health_check_path
    interval            = var.health_check_interval
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
  }

  tags = {
    Name = "${locals.name_prefix}-tg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ==============================================================================
# NLB Listener
# ==============================================================================

resource "aws_lb_listener" "service_listener" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = var.service_port
  protocol          = var.target_protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_tg.arn
  }

  tags = {
    Name = "${locals.name_prefix}-listener-${var.service_port}"
  }
}

# ==============================================================================
# AWS VPC Endpoint Service (PrivateLink Service Provider)
# ==============================================================================
resource "aws_vpc_endpoint_service" "endpoint_service" {
  acceptance_required        = var.acceptance_required
  network_load_balancer_arns = [aws_lb.nlb.arn]
  supported_ip_address_types = var.supported_ip_address_types
  private_dns_name           = var.private_dns_name

  tags = {
    Name        = "${locals.name_prefix}-endpoint-service"
    Environment = var.environment
  }
}

# ==============================================================================
# Whitelisted Consumer Principals (IAM Users, IAM Roles, or AWS Account ARNs)
# ==============================================================================
resource "aws_vpc_endpoint_service_allowed_principal" "allowed_principals" {
  for_each = toset(var.allowed_principals)

  vpc_endpoint_service_id = aws_vpc_endpoint_service.endpoint_service.id
  principal_arn           = each.value
}

# ==============================================================================
# Connection Lifecycle Notifications (Connect, Accept, Reject, Delete)
# ==============================================================================
resource "aws_vpc_endpoint_connection_notification" "service_notifications" {
  count = var.enable_connection_notifications ? 1 : 0

  vpc_endpoint_service_id     = aws_vpc_endpoint_service.endpoint_service.id
  connection_notification_arn = aws_sns_topic.endpoint_notifications[0].arn
  connection_events           = ["Connect", "Accept", "Reject", "Delete"]
}

# ==============================================================================
# SNS Topic for PrivateLink Connection Lifecycle Events
# ==============================================================================

resource "aws_sns_topic" "endpoint_notifications" {
  count = var.enable_connection_notifications ? 1 : 0

  name              = "${locals.name_prefix}-vpce-notifications"
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name = "${locals.name_prefix}-vpce-notifications"
  }
}

# Allow AWS VPC Endpoint Service Principal (vpce.amazonaws.com) to publish events
resource "aws_sns_topic_policy" "endpoint_notifications_policy" {
  count = var.enable_connection_notifications ? 1 : 0

  arn = aws_sns_topic.endpoint_notifications[0].arn

  policy = data.aws_iam_policy_document.sns_topic_policy[0].json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  count = var.enable_connection_notifications ? 1 : 0

  statement {
    sid    = "AllowVPCEServiceToPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["vpce.amazonaws.com"]
    }

    actions = [
      "sns:Publish"
    ]

    resources = [
      aws_sns_topic.endpoint_notifications[0].arn
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# Optional Email Subscriptions for Alerts
resource "aws_sns_topic_subscription" "email_subscribers" {
  for_each = var.enable_connection_notifications ? toset(var.notification_email_endpoints) : []

  topic_arn = aws_sns_topic.endpoint_notifications[0].arn
  protocol  = "email"
  endpoint  = each.value
}

# ==============================================================================
# CloudWatch Alarms for PrivateLink NLB & Target Group Health
# ==============================================================================

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${locals.name_prefix}-nlb-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/NetworkELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "Alarm when any target in the PrivateLink service target group is marked unhealthy"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.service_tg.arn_suffix
    LoadBalancer = aws_lb.nlb.arn_suffix
  }

  alarm_actions = var.enable_connection_notifications ? [aws_sns_topic.endpoint_notifications[0].arn] : []
  ok_actions    = var.enable_connection_notifications ? [aws_sns_topic.endpoint_notifications[0].arn] : []

  tags = {
    Name = "${locals.name_prefix}-alarm-unhealthy-hosts"
  }
}

resource "aws_cloudwatch_metric_alarm" "tcp_target_resets" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${locals.name_prefix}-nlb-tcp-target-resets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TCP_Target_Reset_Count"
  namespace           = "AWS/NetworkELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 25
  alarm_description   = "High rate of TCP resets generated by backend targets in PrivateLink service"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.nlb.arn_suffix
  }

  alarm_actions = var.enable_connection_notifications ? [aws_sns_topic.endpoint_notifications[0].arn] : []

  tags = {
    Name = "${locals.name_prefix}-alarm-target-resets"
  }
}

resource "aws_cloudwatch_metric_alarm" "tcp_elb_resets" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${locals.name_prefix}-nlb-tcp-elb-resets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TCP_ELB_Reset_Count"
  namespace           = "AWS/NetworkELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 25
  alarm_description   = "High rate of TCP resets generated by the NLB in PrivateLink service"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.nlb.arn_suffix
  }

  alarm_actions = var.enable_connection_notifications ? [aws_sns_topic.endpoint_notifications[0].arn] : []

  tags = {
    Name = "${locals.name_prefix}-alarm-elb-resets"
  }
}

