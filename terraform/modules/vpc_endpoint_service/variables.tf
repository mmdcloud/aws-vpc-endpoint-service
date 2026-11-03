variable "name_prefix" {
  description = "Prefix for resource naming and identification."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the Network Load Balancer and targets reside."
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs across multiple AZs where the NLB ENIs will be deployed."
  type        = list(string)
}

variable "service_port" {
  description = "Port exposed by the NLB and serviced by backend targets."
  type        = number
  default     = 443
}

variable "target_protocol" {
  description = "Protocol for the NLB listener and target group (TCP, TLS, UDP, TCP_UDP)."
  type        = string
  default     = "TCP"

  validation {
    condition     = contains(["TCP", "TLS", "UDP", "TCP_UDP"], var.target_protocol)
    error_message = "target_protocol must be TCP, TLS, UDP, or TCP_UDP."
  }
}

variable "target_type" {
  description = "Target type for the target group (instance, ip, alb)."
  type        = string
  default     = "instance"

  validation {
    condition     = contains(["instance", "ip", "alb"], var.target_type)
    error_message = "target_type must be instance, ip, or alb."
  }
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing for the NLB."
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on the NLB."
  type        = bool
  default     = true
}

variable "deregistration_delay" {
  description = "Deregistration delay in seconds for draining connections."
  type        = number
  default     = 30
}

variable "preserve_client_ip" {
  description = "Preserve client IP on target instances."
  type        = bool
  default     = false
}

variable "enable_proxy_protocol_v2" {
  description = "Enable Proxy Protocol v2 to pass client header info to backend."
  type        = bool
  default     = false
}

variable "health_check_protocol" {
  description = "Protocol for NLB health check."
  type        = string
  default     = "TCP"
}

variable "health_check_port" {
  description = "Port for health checks (defaults to traffic-port)."
  type        = string
  default     = "traffic-port"
}

variable "health_check_path" {
  description = "Destination path for HTTP/HTTPS health checks."
  type        = string
  default     = null
}

variable "health_check_interval" {
  description = "Health check interval in seconds."
  type        = number
  default     = 10
}

variable "health_check_healthy_threshold" {
  description = "Successes before target is marked healthy."
  type        = number
  default     = 3
}

variable "health_check_unhealthy_threshold" {
  description = "Failures before target is marked unhealthy."
  type        = number
  default     = 3
}

variable "acceptance_required" {
  description = "Whether VPC endpoint connections require explicit acceptance."
  type        = bool
  default     = true
}

variable "allowed_principals" {
  description = "List of IAM principal ARNs allowed to connect to this VPC Endpoint Service."
  type        = list(string)
  default     = []
}

variable "supported_ip_address_types" {
  description = "Supported IP address types (ipv4, ipv6)."
  type        = list(string)
  default     = ["ipv4"]
}

variable "private_dns_name" {
  description = "Private DNS name for the endpoint service."
  type        = string
  default     = null
}

variable "enable_connection_notifications" {
  description = "Whether to configure SNS connection notifications for lifecycle events."
  type        = bool
  default     = true
}

variable "notification_email_endpoints" {
  description = "Email addresses for endpoint notifications."
  type        = list(string)
  default     = []
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch metric alarms for NLB & Target Group."
  type        = bool
  default     = true
}

variable "enable_access_logs" {
  description = "Enable NLB S3 access logging."
  type        = bool
  default     = false
}

variable "access_logs_s3_bucket" {
  description = "S3 bucket name for NLB access logs."
  type        = string
  default     = null
}

variable "access_logs_s3_prefix" {
  description = "S3 bucket prefix for NLB access logs."
  type        = string
  default     = "nlb-logs"
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}

