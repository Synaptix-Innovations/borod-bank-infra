# Borod Bank — Infrastructure Repository

[![Terraform](https://img.shields.io/badge/Terraform-1.5+-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?logo=amazonaws&logoColor=white)](https://aws.amazon.com/eks/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.32-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Terraform configuration for provisioning the complete AWS infrastructure for Borod Bank: **EKS cluster, RDS MySQL, VPC with 3 AZs, KMS encryption, EFS storage, IRSA roles, and VPC flow logs**. Over 1,300 lines of production-grade IaC.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          AWS (us-east-1)                                 │
│                                                                          │
│  ┌──────────────────────── VPC (10.0.0.0/16) ────────────────────────    │
│  │                                                                    │  │
│  │  Public Subnets (3 AZs)                                            │  │ 
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │  │
│  │  │  10.0.0.0/24 │  │  10.0.1.0/24 │  │  10.0.2.0/24 │              │  │
│  │  │    AZ-a      │  │    AZ-b      │  │    AZ-c      │              │  │
│  │  │  EIP + NLB   │  │  EIP + NLB   │  │  EIP + NLB   │              │  │
│  │  │  EFS Mount   │  │  EFS Mount   │  │  EFS Mount   │              │  │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │  │
│  │         └─────────────────┼─────────────────┘                      │  │
│  │                           │                                        │  │
│  │                    ┌──────┴──────┐                                 │  │
│  │                    │ EKS Cluster │                                 │  │
│  │                    │  (K8s 1.32) │                                 │  │
│  │                    │  OIDC/IRSA  │                                 │  │
│  │                    └──────┬──────┘                                 │  │
│  │                           │                                        │  │
│  │              ┌────────────┼────────────┐                           │  │
│  │              │            │            │                           │  │
│  │       ┌──────┴──────┐  ┌─┴──────┐  ┌─┴──────────┐                  │  │
│  │       │ Node Group  │  │  EBS   │  │ GPU Nodes   │                 │  │
│  │       │ 2-4 t3.large│  │ (KMS)  │  │ SPOT g4dn  │                  │  │
│  │       │  IMDSv2     │  │        │  │ (AIOps)     │                 │  │
│  │       └─────────────┘  └────────┘  └─────────────┘                 │  │
│  │                                                                    │  │
│  │  Private Subnets (3 AZs)                                           │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │  │
│  │  │ 10.0.10.0/24 │  │ 10.0.11.0/24 │  │ 10.0.12.0/24 │              │  │
│  │  │  ┌────────┐  │  │              │  │              │              │  │
│  │  │  │  RDS   │  │  │              │  │              │              │  │
│  │  │  │ MySQL  │  │  │              │  │              │              │  │
│  │  │  │  8.4   │  │  │              │  │              │              │  │
│  │  │  │ (KMS)  │  │  │              │  │              │              │  │
│  │  │  └────────┘  │  │              │  │              │              │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘              │  │
│  │                                                                    │  │
│  └─────────────────────────┬──────────────────────────────────────────┘  │
│                             │                                            │
│  ┌──────────┐  ┌───────────┤  ┌─────────┐  ┌──────────┐                  │
│  │   IGW    │  │ VPC Flow  │  │   EFS   │  │   S3     │                  │
│  │          │  │   Logs    │  │ (Maven  │  │ (Loki +  │                  │
│  │          │  │ CloudWatch│  │  cache) │  │ TF state)│                 │
│  └──────────┘  └───────────┘  └─────────┘  └──────────┘                  │
│                                                                          │
│  KMS: 3 keys (EBS, RDS, EFS)  │  IRSA: 6 roles  │  EIPs: 3 (static)      │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Resources

### Compute & Orchestration

| Resource | Configuration |
|---|---|
| **EKS Cluster** | Kubernetes 1.32, all 5 control plane log types enabled |
| **Node Group** | 2–4 x t3.large, IMDSv2 enforced, launch template |
| **GPU Node Group** | 0–1 x g4dn.xlarge/g5.xlarge SPOT, AIOps workloads, tainted |
| **Cluster Autoscaler** | IRSA-enabled, scales 0→4 nodes |

### Networking

| Resource | Configuration |
|---|---|
| **VPC** | 10.0.0.0/16, DNS support enabled |
| **Public Subnets** | 3 (one per AZ), EKS nodes + NLB |
| **Private Subnets** | 3 (one per AZ), RDS only |
| **Internet Gateway** | Public internet access |
| **Elastic IPs** | 3 static IPs for NLB ingress-nginx |
| **VPC Flow Logs** | CloudWatch, 30-day retention |
| **Security Groups** | Cluster SG, Node SG (inter-node), RDS SG (3306 from EKS only) |

### Database

| Resource | Configuration |
|---|---|
| **RDS MySQL 8.4** | db.t3.micro, 20GB gp3 (auto-scale to 100GB) |
| **Encryption** | KMS-encrypted storage |
| **Backups** | 7-day retention, 03:00–04:00 UTC, final snapshot enabled |
| **Deletion Protection** | Enabled |
| **Credentials** | AWS Secrets Manager (auto-managed) |

### Storage & Encryption

| Resource | Configuration |
|---|---|
| **EFS** | Maven cache, general purpose, KMS encrypted, 3 mount targets |
| **EBS CSI Driver** | Managed addon, KMS encrypted volumes |
| **KMS Keys** | 3 keys: EBS, RDS, EFS (auto-rotation enabled) |
| **S3 (Loki)** | Log storage, 90-day lifecycle, Glacier after 60 days |
| **S3 (TF State)** | Versioned, encrypted, public access blocked |
| **DynamoDB** | Terraform state locking (pay-per-request) |

### IAM / IRSA Roles

| Role | Service Account | Purpose |
|---|---|---|
| AWS Load Balancer Controller | `kube-system:aws-load-balancer-controller` | NLB/ALB management |
| External Secrets Operator | `external-secrets:external-secrets` | Read Secrets Manager |
| Cluster Autoscaler | `kube-system:cluster-autoscaler` | ASG scaling |
| EFS CSI Driver | `kube-system:efs-csi-controller-sa` | EFS access |
| EBS CSI Driver | `kube-system:ebs-csi-controller-sa` | EBS management |
| Loki | `monitoring:loki` | S3 log storage |

---

## Terraform Files

| File | Lines | Purpose |
|---|---|---|
| `main.tf` | 387 | VPC, EKS, node groups, security groups, IAM, OIDC, addons |
| `rds.tf` | 57 | MySQL 8.4 RDS with encryption and backups |
| `aiops.tf` | 79 | GPU SPOT node group for AIOps |
| `eip.tf` | 19 | 3 Elastic IPs for NLB |
| `efs.tf` | 62 | EFS filesystem + CSI driver addon |
| `kms.tf` | 48 | 3 KMS encryption keys |
| `vpc-flow-logs.tf` | 54 | VPC flow logs to CloudWatch |
| `s3-loki.tf` | 73 | S3 bucket for Loki with lifecycle rules |
| `iam-lbc.tf` | 37 | Load Balancer Controller IRSA |
| `iam-eso.tf` | 46 | External Secrets Operator IRSA |
| `iam-ca.tf` | 68 | Cluster Autoscaler IRSA |
| `iam-efs.tf` | 70 | EFS CSI Driver IRSA |
| `iam-loki.tf` | 60 | Loki S3 access IRSA |
| `variables.tf` | 84 | 9 input variables |
| `outputs.tf` | 95 | 19 output values |
| `providers.tf` | 37 | Terraform + AWS provider config |
| `bootstrap/main.tf` | 83 | S3 backend + DynamoDB lock table |
| **Total** | **1,343** | |

---

## Security

- **IMDSv2 enforced** on all nodes (hop_limit=1, prevents SSRF)
- **KMS encryption** for EBS volumes, RDS storage, and EFS filesystem
- **VPC flow logs** to CloudWatch for network audit trail
- **Private subnets** for RDS (no public access)
- **IRSA** for all pod-to-AWS authentication (no node-level IAM)
- **Security groups** with least-privilege rules
- **RDS deletion protection** + 7-day automated backups + final snapshot

---

## Quick Start

```bash
# 1. Bootstrap remote state (one-time)
cd bootstrap && terraform init && terraform apply && cd ..

# 2. Configure variables
cp terraform.tfvars.example terraform.tfvars

# 3. Deploy infrastructure
terraform init
terraform plan
terraform apply

# 4. Configure kubectl
aws eks update-kubeconfig --name borod-bank-cluster --region us-east-1

# 5. Post-deploy configuration
./scripts/post-deploy.sh
```

---

## Outputs (19 values)

| Output | Description |
|---|---|
| `cluster_id`, `cluster_endpoint`, `cluster_name` | EKS cluster identifiers |
| `vpc_id`, `subnet_ids`, `private_subnet_ids` | Network identifiers |
| `cluster_security_group_id` | Cluster security group |
| `oidc_provider_arn` | OIDC provider for IRSA |
| `rds_endpoint`, `rds_secret_arn` | RDS connection details |
| `lbc_role_arn`, `eso_role_arn` | IRSA role ARNs |
| `eip_allocation_ids`, `eip_public_ips` | Static IP addresses |
| `loki_role_arn`, `loki_s3_bucket` | Loki storage config |
| `efs_filesystem_id`, `efs_csi_role_arn` | EFS identifiers |

---

## Related Repositories

| Repository | Description |
|---|---|
| [borod-bank-ci](https://github.com/Synaptix-Innovations/borod-bank-ci) | Spring Boot app + Jenkins CI pipeline |
| [borod-bank-cd](https://github.com/Synaptix-Innovations/borod-bank-cd) | Kubernetes manifests + ArgoCD App of Apps |
| [jenkins-setup](https://github.com/Synaptix-Innovations/jenkins-setup) | Custom Jenkins controller image |
| [borod-bank-docs](https://github.com/Synaptix-Innovations/borod-bank-docs) | Project documentation and screenshots |

## Author

**Vlad Vesninsky** — [GitHub](https://github.com/Vlad774)
