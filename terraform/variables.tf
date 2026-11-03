variable "aws_region" {
  description = "AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "uat", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, uat, prod."
  }
}

variable "project_name" {
  description = "Project name prefix used to namespace and tag resources."
  type        = string
  default     = "privatelink-service"
}

# --- Network Configuration ---

variable "create_vpc" {
  description = "Set to true to provision a dedicated VPC with private subnets across AZs; false to use existing."
  type        = bool
  default     = true
}

variable "existing_vpc_id" {
  description = "Existing VPC ID to use when create_vpc is false."
  type        = string
  default     = null
}

variable "existing_subnet_ids" {
  description = "List of existing private subnet IDs to use for the NLB when create_vpc is false (minimum 2 recommended)."
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "CIDR block for the dedicated VPC when create_vpc is true."
  type        = string
  default     = "10.100.0.0/16"
}

variable "availability_zones" {
  description = "Specific availability zones to deploy subnets in. Defaults to the first 3 available AZs in the region if null."
  type        = list(string)
  default     = null
}

# --- NLB & Target Group Configuration ---

variable "service_port" {
  description = "Network port exposed by the NLB listener and backend service (e.g., 443, 8443, 80)."
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
  description = "Enable cross-zone load balancing for the Network Load Balancer."
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on the NLB to prevent accidental termination in production."
  type        = bool
  default     = true
}

variable "deregistration_delay" {
  description = "Time in seconds for NLB target group deregistration delay."
  type        = number
  default     = 30
}

variable "enable_proxy_protocol_v2" {
  description = "Whether to enable Proxy Protocol v2 on the target group to pass client connection info (IP/port) to backends."
  type        = bool
  default     = false
}

variable "preserve_client_ip" {
  description = "Whether client IP addresses are preserved to the targets. Note: for PrivateLink NLBs, traffic can also be identified via proxy protocol v2."
  type        = bool
  default     = false
}

# --- Health Check Configuration ---

variable "health_check_protocol" {
  description = "Protocol for the NLB target group health check (TCP, HTTP, HTTPS)."
  type        = string
  default     = "TCP"

  validation {
    condition     = contains(["TCP", "HTTP", "HTTPS"], var.health_check_protocol)
    error_message = "health_check_protocol must be TCP, HTTP, or HTTPS."
  }
}

variable "health_check_port" {
  description = "Port to use for health checks (defaults to traffic-port)."
  type        = string
  default     = "traffic-port"
}

variable "health_check_path" {
  description = "Destination path for HTTP/HTTPS health checks (e.g. /healthz). Required when health_check_protocol is HTTP or HTTPS."
  type        = string
  default     = null
}

variable "health_check_interval" {
  description = "Approximate amount of time, in seconds, between health checks of an individual target (10-300)."
  type        = number
  default     = 10
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive health check successes required before considering an unhealthy target healthy (2-10)."
  type        = number
  default     = 3
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive health check failures required before considering a target unhealthy (2-10)."
  type        = number
  default     = 3
}

# --- VPC Endpoint Service (PrivateLink) Configuration ---

variable "acceptance_required" {
  description = "Whether connection requests to the VPC Endpoint Service must be manually accepted by the service owner. Recommended true in production."
  type        = bool
  default     = true
}

variable "allowed_principals" {
  description = "List of AWS IAM principals (ARNs) permitted to discover and connect to this VPC Endpoint Service. E.g. ['arn:aws:iam::123456789012:root']."
  type        = list(string)
  default     = []
}

variable "supported_ip_address_types" {
  description = "The supported IP address types for the endpoint service (ipv4, ipv6)."
  type        = list(string)
  default     = ["ipv4"]
}

variable "private_dns_name" {
  description = "Optional private DNS name for the VPC Endpoint Service (e.g. api.internal.example.com). Requires domain verification."
  type        = string
  default     = null
}

# --- Notifications & Observability ---

variable "enable_connection_notifications" {
  description = "Create an SNS topic and notification mapping for VPC endpoint connection events (Connect, Accept, Reject, Delete)."
  type        = bool
  default     = true
}

variable "notification_email_endpoints" {
  description = "Optional email addresses to subscribe to PrivateLink connection event notifications."
  type        = list(string)
  default     = []
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring target group healthy host count and NLB TCP resets."
  type        = bool
  default     = true
}

variable "enable_access_logs" {
  description = "Enable S3 access logging for the Network Load Balancer."
  type        = bool
  default     = false
}

variable "access_logs_s3_bucket" {
  description = "S3 bucket name where NLB access logs will be delivered. Required if enable_access_logs is true."
  type        = string
  default     = null
}

variable "access_logs_s3_prefix" {
  description = "S3 prefix within the bucket for NLB access logs."
  type        = string
  default     = "nlb-access-logs"
}

# --- Sample Backend Configuration ---

variable "enable_sample_backend" {
  description = "Deploy sample backend EC2 instances in private subnets with a mock TCP/HTTP service to verify end-to-end connectivity."
  type        = bool
  default     = true
}

variable "sample_backend_instance_count" {
  description = "Number of sample backend EC2 instances to launch when enable_sample_backend is true."
  type        = number
  default     = 2
}

variable "sample_backend_instance_type" {
  description = "EC2 instance type for sample backend instances."
  type        = string
  default     = "t3.micro"
}

# --- General Tags ---

variable "tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}

