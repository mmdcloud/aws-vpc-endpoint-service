output "endpoint_id" {
  description = "The ID of the Interface VPC Endpoint."
  value       = aws_vpc_endpoint.service_endpoint.id
}

output "endpoint_state" {
  description = "Connection state of the endpoint (e.g. pendingAcceptance, available)."
  value       = aws_vpc_endpoint.service_endpoint.state
}

output "dns_entries" {
  description = "DNS entries for accessing the service through the interface endpoint."
  value       = aws_vpc_endpoint.service_endpoint.dns_entry
}

output "network_interface_ids" {
  description = "IDs of the elastic network interfaces created for the VPC endpoint."
  value       = aws_vpc_endpoint.service_endpoint.network_interface_ids
}

output "security_group_id" {
  description = "Security group associated with the endpoint network interfaces."
  value       = aws_security_group.endpoint_client_sg.id
}

