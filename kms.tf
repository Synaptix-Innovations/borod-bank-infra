# KMS key for EKS node EBS volumes
resource "aws_kms_key" "ebs" {
  description             = "${var.project_name} EKS EBS volumes"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-ebs-key"
  }
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.project_name}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

# KMS key for RDS storage
resource "aws_kms_key" "rds" {
  description             = "${var.project_name} RDS storage"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-rds-key"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# KMS key for EFS (Maven cache)
resource "aws_kms_key" "efs" {
  description             = "${var.project_name} EFS Maven cache"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-efs-key"
  }
}

resource "aws_kms_alias" "efs" {
  name          = "alias/${var.project_name}-efs"
  target_key_id = aws_kms_key.efs.key_id
}
