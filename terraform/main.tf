terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    snowflake = {
      source = "snowflakedb/snowflake"
      version = "~> 2.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

locals {
  organization_name = "gkczdqx"
  account_name      = "te30202"
  private_key_path = "~/.ssh/snowflake_tf_snow_key.p8"
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-2"

}

#Configure the Snowflake Provider
provider "snowflake" {
  organization_name = local.organization_name
  account_name      = local.account_name
  user              = "TERRAFORM_SVC"
  role              = "ACCOUNTADMIN"
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = file(local.private_key_path)
  alias = "accountadmin"
  preview_features_enabled = ["snowflake_storage_integration_aws_resource"]
}

provider "snowflake" {
  organization_name = local.organization_name
  account_name      = local.account_name
  user              = "TERRAFORM_SVC"
  role              = "SYSADMIN"
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = file(local.private_key_path)
  alias = "sysadmin"
  preview_features_enabled = [
    "snowflake_stage_external_s3_resource", "snowflake_table_resource", "snowflake_pipe_resource"
  ]
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

data "aws_caller_identity" "current" {}

locals {
  snowflake_role_name = "snowflake-s3-role"
  snowflake_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/snowflake-s3-role"
}

# Unfortunately the snowflake role has a circular dependency with the snowflake storage integration
#, so we have to create the role first and then update the trust policy after the integration is created.
# This is a known issue with the Snowflake Terraform provider and there is no workaround at this time.

resource "aws_iam_role" "cw_snowflake_role" {
  name = local.snowflake_role_name
  assume_role_policy = data.aws_iam_policy_document.snowflake_trust.json
  # assume_role_policy = jsonencode({
  #   Version = "2012-10-17"
  #   Statement = [
  #     {
  #       Effect = "Allow"
  #       Principal = {
  #         Service = "ec2.amazonaws.com"
  #       }
  #       Action = "sts:AssumeRole"
  #     }
  #   ]
  # })

}

data "aws_iam_policy_document" "cw_s3_bucket_policy" {
  statement {
    actions   = ["s3:GetBucketLocation", "s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket"]
    resources = [aws_s3_bucket.cw_world_bank_data.arn, "${aws_s3_bucket.cw_world_bank_data.arn}/*"]
  }
}

resource "aws_iam_policy" "snowflake_access" {
  name        = "snowflake_access_policy"
  description = "Policy to allow Snowflake to access S3 bucket for data ingestion"
  policy      = data.aws_iam_policy_document.cw_s3_bucket_policy.json
}


# Attach the S3 bucket permissions to the IAM role
resource "aws_iam_role_policy_attachment" "cw_attach_s3_policy" {
  role       = aws_iam_role.cw_snowflake_role.name
  policy_arn = aws_iam_policy.snowflake_access.arn
}

# Create the Snowflake storage integration to allow Snowflake to access the S3 bucket
# Note: The storage integration will create an IAM user in AWS and grant it permissions to access the S3 bucket. 
# The IAM role created above will then trust this IAM user to allow Snowflake to access the bucket.
resource "snowflake_storage_integration_aws" "cw_s3_integration" {
  provider = snowflake.accountadmin
  name = "cw_snowflake_storage_integration"
  enabled          = true
  storage_provider = "S3"
  storage_allowed_locations = ["s3://${aws_s3_bucket.cw_world_bank_data.bucket}/loan-snapshots/"]
  storage_aws_role_arn = local.snowflake_role_arn
}

data "aws_iam_policy_document" "snowflake_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [snowflake_storage_integration_aws.cw_s3_integration.describe_output[0].iam_user_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [snowflake_storage_integration_aws.cw_s3_integration.describe_output[0].external_id]
    }
  }
}

# Update the SYSADMIN role to trust the IAM user created by the Snowflake storage integration
resource "snowflake_grant_privileges_to_account_role" "snowpipe_integration_grant" {
  provider = snowflake.accountadmin
  privileges = ["USAGE"]
  account_role_name  = var.snowpipe_role

  on_account_object {
    object_type = "INTEGRATION"
    object_name = snowflake_storage_integration_aws.cw_s3_integration.name
  }
}

resource "snowflake_database" "credit_data_platform" {
  provider = snowflake.sysadmin
  name         = "CREDIT_DATA_PLATFORM"
  is_transient = false
}

resource "snowflake_warehouse" "credit_data_platform_warehouse" {
  provider           = snowflake.sysadmin
  name               = "CREDIT_DATA_PLATFORM_WH"
  warehouse_size     = "XSMALL"
  warehouse_type     = "STANDARD"
  auto_suspend       = 60
  auto_resume        = true
}

resource "snowflake_grant_privileges_to_account_role" "warehouse_usage_grant" {
  provider = snowflake.sysadmin
  privileges = ["USAGE"]
  account_role_name  = var.dbt_role

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.credit_data_platform_warehouse.fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "database_usage_grant" {
  provider = snowflake.sysadmin
  all_privileges = true
  account_role_name  = var.dbt_role

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.credit_data_platform.name
  }
}

# A stage is a Snowflake object that acts a temporary storage area for data files that are being loaded into Snowflake.
resource "snowflake_stage_external_s3" "world_bank_data_stage" {
  provider = snowflake.sysadmin
  name                 = "WORLD_BANK_DATA_STAGE"
  database             = snowflake_database.credit_data_platform.name
  schema              = "PUBLIC"
  url                  = "s3://${aws_s3_bucket.cw_world_bank_data.bucket}/loan-snapshots/"
  storage_integration  = snowflake_storage_integration_aws.cw_s3_integration.name

}

resource "snowflake_schema" "raw_schema" {
  provider = snowflake.sysadmin
  name     = "RAW"
  database = snowflake_database.credit_data_platform.name
  data_retention_time_in_days = 1
}

resource "snowflake_table" "world_bank_loan_snapshots" {
  provider = snowflake.sysadmin
  name     = "snowpipe_loan_snapshots"
  database = snowflake_database.credit_data_platform.name
  schema   = snowflake_schema.raw_schema.name
  data_retention_time_in_days = snowflake_schema.raw_schema.data_retention_time_in_days
  change_tracking = true

  column {
    name    = "jsontext"
    type    = "VARIANT"
  }
}

# Create the Snowpipe to automatically ingest data from the S3 bucket into the Snowflake table
# The pipe will create an SQS queue and subscribe it to the S3 bucket notifications to trigger the pipe when new files are added to the bucket
resource "snowflake_pipe" "world_bank_data_pipe" {
  provider = snowflake.sysadmin
  name     = "WORLD_BANK_DATA_PIPE"
  database = snowflake_database.credit_data_platform.name
  schema  = snowflake_schema.raw_schema.name

  copy_statement = <<-EOT
    COPY INTO ${snowflake_table.world_bank_loan_snapshots.fully_qualified_name}
    FROM @${snowflake_stage_external_s3.world_bank_data_stage.fully_qualified_name}
    FILE_FORMAT = (TYPE = 'JSON')
    EOT

  auto_ingest = true
}

# Set up S3 bucket notification to trigger Snowpipe when new files are added to the bucket
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.cw_world_bank_data.id

  queue {
    id = "snowpipe_notification"

    events = ["s3:ObjectCreated:*"]

    filter_prefix = "loan-snapshots/"

    queue_arn = snowflake_pipe.world_bank_data_pipe.notification_channel
  }
}