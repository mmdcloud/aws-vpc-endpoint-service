output "endpoint_service_id" {
  description = "The ID of the VPC Endpoint Service."
  value       = aws_vpc_endpoint_service.this.id
}

output "endpoint_service_name" {
  description = "The service name of the VPC Endpoint Service (share this with consumers)."
  value       = aws_vpc_endpoint_service.this.service_name
}

output "endpoint_service_type" {
  description = "The type of service."
  value       = aws_vpc_endpoint_service.this.service_type
}

output "endpoint_service_state" {
  description = "The current state of the VPC Endpoint Service."
  value       = aws_vpc_endpoint_service.this.state
}

output "acceptance_required" {
  description = "Whether incoming connection requests require approval."
  value       = aws_vpc_endpoint_service.this.acceptance_required
}

output "nlb_arn" {
  description = "The ARN of the Network Load Balancer."
  value       = aws_lb.this.arn
}

output "nlb_dns_name" {
  description = "The DNS name of the Network Load Balancer."
  value       = aws_lb.this.dns_name
}

output "nlb_security_group_id" {
  description = "The ID of the security group attached to the NLB."
  value       = aws_security_group.nlb.id
}

output "target_group_arn" {
  description = "The ARN of the Target Group to attach your application instances or IP targets."
  value       = aws_lb_target_group.this.arn
}

output "target_group_name" {
  description = "The name of the Target Group."
  value       = aws_lb_target_group.this.name
}

output "sns_topic_arn" {
  description = "The ARN of the SNS topic receiving PrivateLink notifications."
  value       = var.enable_connection_notifications ? aws_sns_topic.notifications[0].arn : null
}

