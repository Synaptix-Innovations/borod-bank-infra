# S3 bucket for Loki logs storage
# Loki stores log chunks here instead of local PVC (cost-effective, scalable)

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "loki_logs" {
  bucket = "borod-bank-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name      = "Loki Logs Storage"
    ManagedBy = "terraform"
    Project   = var.project_name
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  rule {
    id     = "delete-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90 # Delete logs older than 90 days (Loki retention is 30 days)
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    filter {}

    transition {
      days          = 60 # Move logs older than 60 days to Glacier (cheaper)
      storage_class = "GLACIER"
    }
  }
}

resource "aws_s3_bucket_versioning" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  versioning_configuration {
    status = "Disabled" # No need for versioning on log chunks
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # S3-managed encryption (free)
    }
  }
}

resource "aws_s3_bucket_public_access_block" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
