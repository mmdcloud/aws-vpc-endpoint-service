# ==============================================================================
# VPC Endpoint Service Outputs
# ==============================================================================

output "endpoint_service_id" {
  description = "The ID of the VPC Endpoint Service."
  value       = aws_vpc_endpoint_service.endpoint_service.id
}

output "endpoint_service_name" {
  description = "The service name of the VPC Endpoint Service. Share this with consumers to create Interface VPC Endpoints."
  value       = aws_vpc_endpoint_service.endpoint_service.service_name
}

output "endpoint_service_type" {
  description = "The type of service (Interface)."
  value       = aws_vpc_endpoint_service.endpoint_service.service_type
}

output "endpoint_service_state" {
  description = "The state of the VPC Endpoint Service (e.g. Available)."
  value       = aws_vpc_endpoint_service.endpoint_service.state
}

output "acceptance_required" {
  description = "Whether manual connection acceptance is required for incoming consumer connections."
  value       = aws_vpc_endpoint_service.endpoint_service.acceptance_required
}

output "allowed_principals" {
  description = "List of IAM principals authorized to connect to this VPC Endpoint Service."
  value       = var.allowed_principals
}

output "private_dns_name_configuration" {
  description = "Configuration details for verifying private DNS name ownership (if private_dns_name is set)."
  value       = aws_vpc_endpoint_service.endpoint_service.private_dns_name_configuration
}

# ==============================================================================
# NLB and Target Group Outputs
# ==============================================================================

output "nlb_arn" {
  description = "The ARN of the Network Load Balancer."
  value       = aws_lb.nlb.arn
}

output "nlb_dns_name" {
  description = "The internal DNS name of the Network Load Balancer."
  value       = aws_lb.nlb.dns_name
}

output "target_group_arn" {
  description = "The ARN of the Target Group."
  value       = aws_lb_target_group.service_tg.arn
}

# ==============================================================================
# Network & Notification Outputs
# ==============================================================================

output "vpc_id" {
  description = "The ID of the VPC housing the service."
  value       = locals.vpc_id
}

output "subnet_ids" {
  description = "The IDs of the subnets hosting the NLB and backend."
  value       = locals.subnet_ids
}

output "sns_topic_arn" {
  description = "The ARN of the SNS topic receiving PrivateLink connection notifications."
  value       = var.enable_connection_notifications ? aws_sns_topic.endpoint_notifications[0].arn : null
}

# ==============================================================================
# Consumer Integration Helper Snippet
# ==============================================================================

output "consumer_terraform_example" {
  description = "Ready-to-use Terraform snippet for consumer VPCs connecting to this Endpoint Service."
  value       = <<-EOT
    resource "aws_vpc_endpoint" "consumer_endpoint" {
      vpc_id              = "vpc-xxxxxxxxxxxxxxxxx"
      service_name        = "${aws_vpc_endpoint_service.endpoint_service.service_name}"
      vpc_endpoint_type   = "Interface"
      subnet_ids          = ["subnet-aaaaaaaaa", "subnet-bbbbbbbbb"]
      security_group_ids  = ["sg-xxxxxxxxxxxxxxxxx"]
      private_dns_enabled = ${var.private_dns_name != null ? "true" : "false"}

      tags = {
        Name = "vpce-to-${var.project_name}"
      }
    }
  EOT
}

