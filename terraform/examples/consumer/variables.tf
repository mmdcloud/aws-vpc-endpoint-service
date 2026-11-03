variable "aws_region" {
  description = "AWS region for consumer resources."
  type        = string
  default     = "us-east-1"
}

variable "consumer_vpc_id" {
  description = "VPC ID of the consumer environment."
  type        = string
}

variable "consumer_subnet_ids" {
  description = "List of private subnet IDs in the consumer VPC where Interface Endpoint network interfaces will be provisioned."
  type        = list(string)
}

variable "endpoint_service_name" {
  description = "The Service Name provided by the VPC Endpoint Service provider (e.g. com.amazonaws.vpce.us-east-1.vpce-svc-xxx)."
  type        = string
}

variable "service_port" {
  description = "Port to allow communication with the endpoint service."
  type        = number
  default     = 443
}

variable "private_dns_enabled" {
  description = "Whether to associate a private hosted zone with the specified VPC to resolve service endpoint DNS names."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to consumer endpoint resources."
  type        = map(string)
  default = {
    Environment = "prod"
    Role        = "PrivateLinkConsumer"
  }
}

