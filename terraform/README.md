# AWS VPC Endpoint Service (PrivateLink) - Production-Grade Terraform

This repository provides an enterprise-ready, production-grade Terraform implementation for publishing services privately across AWS accounts and VPCs using **AWS VPC Endpoint Service (AWS PrivateLink)**.

---

## Architecture Overview

AWS PrivateLink allows service providers to securely expose services hosted in their VPCs to consumers across different VPCs, accounts, or organizations via AWS's private network backbone—without internet gateways, NAT devices, public IPs, or complex VPC peering/transit gateway route management.

```
┌─────────────────────────────────────────────────────────┐
│                     Consumer VPC                        │
│                                                         │
│   ┌──────────────────┐         ┌────────────────────┐   │
│   │ Client App / EC2 │ ──────> │ Interface Endpoint │   │
│   └──────────────────┘         │ (VPCE ENIs)        │   │
│                                └─────────┬──────────┘   │
└──────────────────────────────────────────┼──────────────┘
                                           │ AWS PrivateLink
                                           │ Encrypted Backbone
┌──────────────────────────────────────────┼──────────────┐
│                     Provider VPC         │              │
│                                          ▼              │
│                           ┌─────────────────────────┐   │
│                           │  VPC Endpoint Service   │   │
│                           │  (vpce-svc-xxxxxxxx)    │   │
│                           └────────────┬────────────┘   │
│                                        │                │
│                           ┌────────────▼────────────┐   │
│                           │  Network Load Balancer  │   │
│                           │  (Internal across AZs)  │   │
│                           └────────────┬────────────┘   │
│                                        │                │
│                 ┌──────────────────────┴──────────────────────┐
│                 ▼                                             ▼
│    ┌─────────────────────────┐                   ┌─────────────────────────┐
│    │ Backend Target (AZ-a)   │                   │ Backend Target (AZ-b)   │
│    │ Target Group (Port 443) │                   │ Target Group (Port 443) │
│    └─────────────────────────┘                   └─────────────────────────┘
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Features

- **Production-Grade Reliability**:
  - Internal Network Load Balancer (NLB) deployed across 3 Availability Zones with cross-zone load balancing enabled.
  - Configurable deletion protection to prevent accidental service disruption.
  - S3 Access Logging capability for compliance and auditing.
- **Enterprise Security & Governance**:
  - Enforced IMDSv2 and encrypted EBS root volumes for backend instances.
  - Default VPC security groups locked down adhering to CIS AWS Foundations Benchmark.
  - Strictly scoped security groups on both the NLB and backend workloads.
  - Access control via explicit IAM / Account Principal ARNs (`allowed_principals`).
  - Connection approval enforcement (`acceptance_required = true`).
- **Observability & Alerting**:
  - SNS topic with PrivateLink publishing permissions for connection events (`Connect`, `Accept`, `Reject`, `Delete`).
  - CloudWatch alarms for Unhealthy Host Count, NLB TCP target resets, and NLB TCP ELB resets.
- **Dual Consumption Models**:
  - **Turnkey Root Deployment**: Complete standalone deployment with dedicated VPC, NLB, backend targets, and endpoint service.
  - **Reusable Submodule (`modules/vpc_endpoint_service`)**: Self-contained module ready to be imported into existing VPCs and CI/CD pipelines.
- **End-to-End Consumer Reference**: Includes an example configuration under `examples/consumer/` demonstrating how consumer VPCs provision interface endpoints.

---

## Directory Structure

```text
terraform/
├── versions.tf                     # Minimum Terraform (>= 1.5.0) and AWS Provider (~> 5.0) constraints
├── providers.tf                    # AWS provider definition with default tags
├── variables.tf                    # Input variable definitions with validation rules
├── locals.tf                       # Local computations, AZ discovery, and naming logic
├── network.tf                      # Dedicated VPC, multi-AZ subnets, and security groups
├── nlb.tf                          # Network Load Balancer, listeners, and target groups
├── endpoint_service.tf             # aws_vpc_endpoint_service & allowed principal bindings
├── notifications.tf                # Encrypted SNS topic and PrivateLink access policies
├── monitoring.tf                   # CloudWatch metric alarms for NLB & Target Group
├── backend_targets.tf              # Turnkey sample EC2 instances (SSM enabled, IMDSv2)
├── outputs.tf                      # Service name, Service ID, NLB DNS, and consumer snippets
├── terraform.tfvars.example        # Production variable template
├── modules/
│   └── vpc_endpoint_service/       # Reusable standalone module for existing VPCs
│       ├── versions.tf
│       ├── variables.tf
│       ├── main.tf
│       └── outputs.tf
├── examples/
│   └── consumer/                   # Sample Consumer Interface Endpoint configuration
│       ├── versions.tf
│       ├── variables.tf
│       ├── main.tf
│       └── outputs.tf
└── README.md                       # Comprehensive guide and operational documentation
```

---

## Quickstart

### 1. Initialize Terraform
```bash
cd terraform
terraform init
```

### 2. Configure Variables
Copy the example variables file:
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your environment values:
```hcl
aws_region   = "us-east-1"
environment  = "prod"
project_name = "payment-gateway"
service_port = 443

# Add consumer AWS account ARNs allowed to discover and connect
allowed_principals = [
  "arn:aws:iam::123456789012:root"
]
```

### 3. Deploy
```bash
terraform plan -out=tfplan
terraform apply tfplan
```

### 4. Review Outputs
After applying, note the `endpoint_service_name` (e.g., `com.amazonaws.vpce.us-east-1.vpce-svc-0123456789abcdef0`). Provide this service name to your consumer teams.

---

## Connecting a Consumer VPC

### Step 1: Whitelist Consumer Principal
In the provider configuration, ensure the consumer's AWS account or role is listed in `allowed_principals`:
```hcl
allowed_principals = [
  "arn:aws:iam::123456789012:root"
]
```
Run `terraform apply` to apply the permission.

### Step 2: Consumer Provisions Interface Endpoint
In the consumer's AWS account and VPC, deploy an Interface VPC Endpoint:
```hcl
resource "aws_security_group" "endpoint_sg" {
  name        = "payment-svc-ep-sg"
  description = "Security group for PrivateLink interface endpoint"
  vpc_id      = "vpc-consumer123"

  ingress {
    description = "Allow consumer app traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
}

resource "aws_vpc_endpoint" "payment_service" {
  vpc_id              = "vpc-consumer123"
  service_name        = "com.amazonaws.vpce.us-east-1.vpce-svc-0123456789abcdef0"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = ["subnet-consumer-az1", "subnet-consumer-az2"]
  security_group_ids  = [aws_security_group.endpoint_sg.id]
  private_dns_enabled = false
}
```

### Step 3: Provider Accepts Connection (if acceptance_required = true)
When `acceptance_required = true`, incoming connection requests are held in `PendingAcceptance` status:
```bash
# Accept connection using AWS CLI
aws ec2 accept-vpc-endpoint-connections \
  --service-id vpce-svc-0123456789abcdef0 \
  --vpc-endpoint-ids vpce-0987654321fedcba0
```
Or manage it directly from the AWS VPC Console under **Endpoint Services** > **Endpoint Connections**.

---

## Reusable Submodule Usage

If you already have an existing VPC and backend targets, you can use the nested submodule directly:

```hcl
module "privatelink_service" {
  source = "./modules/vpc_endpoint_service"

  name_prefix = "my-service-prod"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_ids  = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]

  service_port                     = 443
  target_protocol                  = "TCP"
  target_type                      = "ip" # or "instance"
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = true

  acceptance_required = true
  allowed_principals  = [
    "arn:aws:iam::123456789012:root"
  ]

  enable_connection_notifications = true
  notification_email_endpoints    = ["ops@company.com"]

  tags = {
    Environment = "prod"
    Owner       = "CorePlatform"
  }
}

# Attach your existing workloads to the module target group
resource "aws_lb_target_group_attachment" "workloads" {
  target_group_arn = module.privatelink_service.target_group_arn
  target_id        = "10.0.10.25"
  port             = 443
}
```

---

## Custom Private DNS Verification (Optional)

To allow consumers to access your service using a friendly domain name (e.g. `api.internal.company.com`):

1. Set `private_dns_name = "api.internal.company.com"` in `terraform.tfvars`.
2. Apply Terraform to create the service with the private DNS name.
3. Check the `private_dns_name_configuration` output for the required verification TXT record:
   - **Name**: e.g. `_vpce-svc-xxxxxxxx`
   - **Value**: e.g. `vpce-svc-verification-code`
4. Add the TXT record in your public or internal Route 53 hosted zone for `company.com`.
5. Once DNS propagates, verify domain ownership in the AWS VPC Console or with:
   ```bash
   aws ec2 start-vpc-endpoint-service-private-dns-verification \
     --service-id vpce-svc-0123456789abcdef0
   ```

---

## Production Security & Architecture Checklist

- [x] **Multi-AZ Availability**: Subnets and NLB configured across at least 2 (default 3) distinct Availability Zones.
- [x] **Least Privilege Access**: NLB & Backend security groups strictly allow only necessary traffic on the designated service port.
- [x] **Zero Public Exposure**: NLB is strictly `internal = true` and backends reside in private subnets with no public IPs.
- [x] **IMDSv2 Enforced**: Sample backend instances enforce IMDSv2 token authentication.
- [x] **Storage Encryption**: EBS root volumes configured with `encrypted = true`.
- [x] **Access Auditing**: SNS lifecycle notifications enabled for audit logs of connections, acceptances, and deletions.
- [x] **Health Check Monitoring**: CloudWatch alarms configured to notify administrators when targets are unhealthy.
- [x] **Preserve Client IP / Proxy Protocol**: Configurable via `enable_proxy_protocol_v2` and `preserve_client_ip` depending on backend application requirements.

---

## License

This infrastructure code is maintained under the Apache 2.0 License.

