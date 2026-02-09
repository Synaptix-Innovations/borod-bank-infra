# Borod Bank - Infrastructure Repository

[![Terraform](https://img.shields.io/badge/terraform-1.5+-purple)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-EKS-orange)](https://aws.amazon.com/eks/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Terraform configuration for provisioning AWS EKS infrastructure for the Borod Bank application.

```
┌──────────────────────────────────────────────────────────┐
│                    AWS INFRASTRUCTURE                    │
│                                                          │
│  ┌────────────────── VPC (10.0.0.0/16) ───────────────┐  │
│  │                                                     │  │
│  │  ┌─────────────┐         ┌─────────────┐           │  │
│  │  │  Subnet AZ-a│         │  Subnet AZ-b│           │  │
│  │  │  10.0.0.0/24│         │  10.0.1.0/24│           │  │
│  │  └──────┬──────┘         └──────┬──────┘           │  │
│  │         │                       │                   │  │
│  │         └───────────┬───────────┘                   │  │
│  │                     │                               │  │
│  │              ┌──────┴──────┐                        │  │
│  │              │  EKS Cluster│                        │  │
│  │              │  (K8s 1.28) │                        │  │
│  │              └──────┬──────┘                        │  │
│  │                     │                               │  │
│  │              ┌──────┴──────┐                        │  │
│  │              │  Node Group │                        │  │
│  │              │ 2-4 x t3.m  │                        │  │
│  │              └─────────────┘                        │  │
│  │                                                     │  │
│  └──────────────────────┬──────────────────────────────┘  │
│                         │                                 │
│                  ┌──────┴──────┐                          │
│                  │     IGW     │                          │
│                  └─────────────┘                          │
└──────────────────────────────────────────────────────────┘
```

## Resources Created

| Resource | Name | Description |
|----------|------|-------------|
| VPC | `borod-bank-vpc` | Network with DNS support |
| Subnets | `borod-bank-subnet-*` | Public subnets across AZs |
| Internet Gateway | `borod-bank-igw` | Public internet access |
| EKS Cluster | `borod-bank-cluster` | Managed Kubernetes |
| Node Group | `borod-bank-node-group` | Worker nodes (t3.medium) |
| IAM Roles | cluster / node-group | Service roles with policies |
| Security Groups | cluster / node | Network access control |

## Quick Start

```bash
# 1. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 2. Initialize and apply
terraform init
terraform plan
terraform apply

# 3. Configure kubectl
aws eks update-kubeconfig --name borod-bank-cluster --region eu-central-1
```

## Inputs

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | `eu-central-1` |
| `project_name` | Resource naming prefix | `borod-bank` |
| `environment` | Environment tag | `dev` |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `ssh_key_name` | EC2 SSH key pair name | `borod-bank-key` |
| `node_instance_types` | Node instance types | `["t3.medium"]` |
| `node_desired_size` | Desired node count | `3` |
| `cluster_version` | K8s version | `1.28` |

## Outputs

| Output | Description |
|--------|-------------|
| `cluster_id` | EKS cluster ID |
| `cluster_endpoint` | EKS API endpoint |
| `cluster_name` | EKS cluster name |
| `vpc_id` | VPC ID |
| `subnet_ids` | List of subnet IDs |

## Related Repositories

| Repository | Description |
|------------|-------------|
| [borod-bank-ci](https://github.com/Vlad774/borod-bank-ci) | Spring Boot app + Jenkins pipeline |
| [borod-bank-cd](https://github.com/Vlad774/borod-bank-cd) | Kubernetes manifests + ArgoCD |

## Author

**Vlad Vesninsky** - [GitHub](https://github.com/Vlad774)
