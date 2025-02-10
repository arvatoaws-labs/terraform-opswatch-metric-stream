variable "included_namespaces" {
  type    = list(string)
  default = []
}

variable "excluded_namespaces" {
  type    = list(string)
  default = []
}

resource "aws_cloudwatch_metric_stream" "opswatch" {
  depends_on    = [aws_iam_role_policy.firehose_delivery]
  name          = "OpswatchMetricStream"
  output_format = "json"
  firehose_arn  = aws_kinesis_firehose_delivery_stream.opswatch.arn
  role_arn      = aws_iam_role.cloudwatch.arn

  dynamic "include_filter" {
    for_each = var.included_namespaces
    content {
      namespace = include_filter.value
    }
  }
  dynamic "exclude_filter" {
    for_each = var.excluded_namespaces
    content {
      namespace = exclude_filter.value
    }
  }
}

resource "aws_iam_role" "cloudwatch" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "streams.metrics.cloudwatch.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "firehose_delivery" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "firehose:PutRecord",
        "firehose:PutRecordBatch"
      ]
      Resource = aws_kinesis_firehose_delivery_stream.opswatch.arn
    }]
  })
  role = aws_iam_role.cloudwatch.id
}

resource "aws_iam_role" "kinesis" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "firehose.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "http_delivery" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:AbortMultipartUpload",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:PutObject"
      ]
      Resource = [
        aws_s3_bucket.opswatch_error.arn,
        "${aws_s3_bucket.opswatch_error.arn}/*"
      ]
    }]
  })
  role = aws_iam_role.kinesis.id
}

variable "url" {
  type        = string
  description = "Opswatch URL"
}

resource "aws_kinesis_firehose_delivery_stream" "opswatch" {
  depends_on  = [aws_iam_role_policy.http_delivery]
  name        = "OpswatchMetricStream"
  destination = "http_endpoint"
  http_endpoint_configuration {
    url                = "${var.url}/metrics"
    name               = "CentralMetricProcessor"
    role_arn           = aws_iam_role.kinesis.arn
    buffering_size     = 1
    buffering_interval = 60
    retry_duration     = 100
    s3_backup_mode     = "FailedDataOnly"
    request_configuration {
      content_encoding = "GZIP"
    }
    s3_configuration {
      role_arn           = aws_iam_role.kinesis.arn
      bucket_arn         = aws_s3_bucket.opswatch_error.arn
      buffering_size     = 128
      buffering_interval = 900
      compression_format = "GZIP"
    }
  }
}

resource "aws_s3_bucket" "opswatch_error" {}

# resource "aws_s3_bucket_acl" "opswatch_error" {
#   bucket = aws_s3_bucket.opswatch_error.id
#   acl    = "private"
# }

resource "aws_s3_bucket_server_side_encryption_configuration" "opswatch_error" {
  bucket = aws_s3_bucket.opswatch_error.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "opswatch_error" {
  bucket = aws_s3_bucket.opswatch_error.id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "opswatch_error" {
  bucket = aws_s3_bucket.opswatch_error.id

  rule {
    id = "expire"

    expiration {
      days = 1
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }

    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "opswatch_error" {
  bucket                  = aws_s3_bucket.opswatch_error.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}