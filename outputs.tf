output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "node_group_id" {
  description = "EKS node group ID"
  value       = aws_eks_node_group.main.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "subnet_ids" {
  description = "Subnet IDs"
  value       = aws_subnet.main[*].id
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.cluster.id
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "rds_endpoint" {
  description = "RDS MySQL endpoint (use in SPRING_DATASOURCE_URL)"
  value       = aws_db_instance.main.endpoint
}

output "rds_secret_arn" {
  description = "ARN of the Secrets Manager secret for RDS master password"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "lbc_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller (use in ServiceAccount annotation)"
  value       = aws_iam_role.lbc.arn
}

output "eso_role_arn" {
  description = "IAM role ARN for External Secrets Operator (use in ServiceAccount annotation)"
  value       = aws_iam_role.eso.arn
}

output "private_subnet_ids" {
  description = "Private subnet IDs (used by RDS)"
  value       = aws_subnet.private[*].id
}

output "eip_allocation_ids" {
  description = "EIP allocation IDs for NLB ingress-nginx annotation (comma-separated in post-deploy.sh)"
  value       = aws_eip.nlb[*].id
}

output "eip_public_ips" {
  description = "Static public IPs for NLB — set DNS A-records to these once, never change"
  value       = aws_eip.nlb[*].public_ip
}

output "loki_role_arn" {
  description = "IAM role ARN for Loki (use in ServiceAccount annotation)"
  value       = aws_iam_role.loki.arn
}

output "loki_s3_bucket" {
  description = "S3 bucket name for Loki logs storage"
  value       = aws_s3_bucket.loki_logs.id
}

output "efs_filesystem_id" {
  description = "EFS filesystem ID for Maven cache (inject into efs/storageclass.yml)"
  value       = aws_efs_file_system.maven_cache.id
}

output "efs_csi_role_arn" {
  description = "IAM role ARN for EFS CSI Driver"
  value       = aws_iam_role.efs_csi.arn
}
