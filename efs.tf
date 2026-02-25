# Security group for EFS mount targets — allows NFS from EKS managed cluster SG
resource "aws_security_group" "efs" {
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "NFS from EKS nodes"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-efs-sg"
  }

  depends_on = [aws_eks_cluster.main]
}

# EFS FileSystem — encrypted with dedicated KMS key
resource "aws_efs_file_system" "maven_cache" {
  encrypted        = true
  kms_key_id       = aws_kms_key.efs.arn
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name    = "${var.project_name}-maven-cache"
    Project = var.project_name
  }
}

# EFS Mount Targets — one per node subnet (same subnets where EKS nodes run)
resource "aws_efs_mount_target" "maven_cache" {
  count           = var.subnet_count
  file_system_id  = aws_efs_file_system.maven_cache.id
  subnet_id       = aws_subnet.main[count.index].id
  security_groups = [aws_security_group.efs.id]

  depends_on = [aws_efs_file_system.maven_cache]
}

# EFS CSI Driver — managed EKS addon (consistent with EBS CSI addon pattern)
resource "aws_eks_addon" "efs_csi_driver" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-efs-csi-driver"
  service_account_role_arn = aws_iam_role.efs_csi.arn

  depends_on = [
    aws_iam_role_policy.efs_csi,
    aws_efs_mount_target.maven_cache,
    aws_eks_node_group.main
  ]
}
