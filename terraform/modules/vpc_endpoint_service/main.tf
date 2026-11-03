data "aws_caller_identity" "current" {}

locals {
  health_check_path = contains(["HTTP", "HTTPS"], var.health_check_protocol) ? (
    var.health_check_path != null ? var.health_check_path : "/"
  ) : null
}

# ==============================================================================
# Security Group for NLB
# ==============================================================================

resource "aws_security_group" "nlb" {
  name_prefix = "${var.name_prefix}-nlb-sg-"
  description = "Security group for PrivateLink Network Load Balancer"
  vpc_id      = var.vpc_id

  tags = merge(
    {
      Name = "${var.name_prefix}-nlb-sg"
    },
    var.tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "nlb_service_ingress" {
  security_group_id = aws_security_group.nlb.id
  description       = "Allow inbound traffic on service port"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = var.service_port
  to_port           = var.service_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "nlb_egress_all" {
  security_group_id = aws_security_group.nlb.id
  description       = "Allow outbound traffic from NLB to targets"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ==============================================================================
# Network Load Balancer
# ==============================================================================

resource "aws_lb" "this" {
  name                             = substr("${var.name_prefix}-nlb", 0, 32)
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = var.subnet_ids
  security_groups                  = [aws_security_group.nlb.id]
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

  tags = merge(
    {
      Name = "${var.name_prefix}-nlb"
    },
    var.tags
  )
}

# ==============================================================================
# Target Group
# ==============================================================================

resource "aws_lb_target_group" "this" {
  name                 = substr("${var.name_prefix}-tg", 0, 32)
  port                 = var.service_port
  protocol             = var.target_protocol
  vpc_id               = var.vpc_id
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

  tags = merge(
    {
      Name = "${var.name_prefix}-tg"
    },
    var.tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ==============================================================================
# NLB Listener
# ==============================================================================

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.service_port
  protocol          = var.target_protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = merge(
    {
      Name = "${var.name_prefix}-listener-${var.service_port}"
    },
    var.tags
  )
}

# ==============================================================================
# AWS VPC Endpoint Service
# ==============================================================================

resource "aws_vpc_endpoint_service" "this" {
  acceptance_required        = var.acceptance_required
  network_load_balancer_arns = [aws_lb.this.arn]
  supported_ip_address_types = var.supported_ip_address_types
  private_dns_name           = var.private_dns_name

  tags = merge(
    {
      Name = "${var.name_prefix}-endpoint-service"
    },
    var.tags
  )
}

resource "aws_vpc_endpoint_service_allowed_principal" "this" {
  for_each = toset(var.allowed_principals)

  vpc_endpoint_service_id = aws_vpc_endpoint_service.this.id
  principal_arn           = each.value
}

# ==============================================================================
# Connection Notifications & SNS
# ==============================================================================

resource "aws_sns_topic" "notifications" {
  count = var.enable_connection_notifications ? 1 : 0

  name              = "${var.name_prefix}-vpce-events"
  kms_master_key_id = "alias/aws/sns"

  tags = merge(
    {
      Name = "${var.name_prefix}-vpce-events"
    },
    var.tags
  )
}

resource "aws_sns_topic_policy" "notifications" {
  count = var.enable_connection_notifications ? 1 : 0

  arn = aws_sns_topic.notifications[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowVPCEServiceToPublish"
        Effect = "Allow"
        Principal = {
          Service = "vpce.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.notifications[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "emails" {
  for_each = var.enable_connection_notifications ? toset(var.notification_email_endpoints) : []

  topic_arn = aws_sns_topic.notifications[0].arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_vpc_endpoint_connection_notification" "this" {
  count = var.enable_connection_notifications ? 1 : 0

  vpc_endpoint_service_id     = aws_vpc_endpoint_service.this.id
  connection_notification_arn = aws_sns_topic.notifications[0].arn
  connection_events           = ["Connect", "Accept", "Reject", "Delete"]
}

# ==============================================================================
# CloudWatch Alarms
# ==============================================================================

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-nlb-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/NetworkELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "Alarm when any target in target group is unhealthy"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.this.arn_suffix
    LoadBalancer = aws_lb.this.arn_suffix
  }

  alarm_actions = var.enable_connection_notifications ? [aws_sns_topic.notifications[0].arn] : []
  ok_actions    = var.enable_connection_notifications ? [aws_sns_topic.notifications[0].arn] : []

  tags = var.tags
}

