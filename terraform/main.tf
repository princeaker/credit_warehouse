terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-2"

}


resource "aws_s3_bucket" "cw_world_bank_data" {
  bucket = "cw-world-bank-data"

  tags = {
    Name        = "World Bank Data"
    Environment = "Production"
    Project     = "Credit Warehouse"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cw_world_bank_data_lifecycle" {
  bucket = aws_s3_bucket.cw_world_bank_data.id

  rule {
    id     = "Transition to Glacier after 30 days"
    status = "Enabled"

    filter {
      prefix = "loan-snapshots/"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }
  }
}

data "aws_iam_policy_document" "cw_s3_bucket_policy" {
  statement {
    actions   = ["s3:GetBucketLocation", "s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket"]
    resources = [aws_s3_bucket.cw_world_bank_data.arn, "${aws_s3_bucket.cw_world_bank_data.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "cw_s3_policy" {
  bucket = aws_s3_bucket.cw_world_bank_data.id
  policy = data.aws_iam_policy_document.cw_s3_bucket_policy.json
}

resource "aws_iam_role" "cw_snowflake_role" {
  name = "cw_snowflake_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "snowflake.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

}

# Attach the S3 bucket permissions to the IAM role
resource "aws_iam_role_policy_attachment" "cw_attach_s3_policy" {
  role       = aws_iam_role.cw_snowflake_role.name
  policy_arn = aws_iam_policy_document.cw_s3_bucket_policy.arn
}