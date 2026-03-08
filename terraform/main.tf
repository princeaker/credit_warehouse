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