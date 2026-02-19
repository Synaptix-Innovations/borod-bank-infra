# IRSA for Loki
# Allows Loki pod to read/write log chunks to S3

resource "aws_iam_role" "loki" {
  name = "${var.project_name}-loki-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:monitoring:loki"
          }
        }
      }
    ]
  })

  tags = {
    Name      = "${var.project_name}-loki-role"
    ManagedBy = "terraform"
    Project   = var.project_name
  }
}

resource "aws_iam_role_policy" "loki_s3" {
  name = "${var.project_name}-loki-s3-policy"
  role = aws_iam_role.loki.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.loki_logs.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.loki_logs.arn}/*"
      }
    ]
  })
}
