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
# We need two Snowflake providers to manage the different roles and permissions required for the Snowflake storage integration and the Snowpipe.
# The accountadmin role is required to create the storage integration and grant privileges on it,
# while the sysadmin role is used to create the database, warehouse, and other objects, and grant privileges to the dbt role.
# This is a workaround for the fact that the Snowflake Terraform provider does not currently support granting privileges 
#on integrations to roles other than ACCOUNTADMIN, which is required for the Snowpipe integration to work properly.
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

# Create the database and warehouse for the credit data platform
resource "snowflake_database" "credit_data_platform" {
  provider = snowflake.sysadmin
  name         = "CREDIT_DATA_PLATFORM"
  is_transient = false
}

# Create a warehouse for the credit data platform with auto-suspend and auto-resume enabled to optimize costs
resource "snowflake_warehouse" "credit_data_platform_warehouse" {
  provider           = snowflake.sysadmin
  name               = "CREDIT_DATA_PLATFORM_WH"
  warehouse_size     = "XSMALL"
  warehouse_type     = "STANDARD"
  generation         = "2"
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

# When accessing tables from snowflake, the user needs USAGE privilege on 
# the database and schema, and SELECT privilege on the tables.
resource "snowflake_grant_privileges_to_account_role" "database_usage_grant" {
  provider = snowflake.sysadmin
  all_privileges = true
  account_role_name  = var.dbt_role

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.credit_data_platform.name
  }
}

# the USAGE privilege on the schema allows the user to see the schema and its objects, but not access the data.
# This is required for the dbt role to be able to see the tables in the RAW schema and query them.
resource "snowflake_grant_privileges_to_account_role" "schema_usage_grant" {
  provider = snowflake.sysadmin
  privileges = ["USAGE"]
  account_role_name  = var.dbt_role

  on_schema {
    schema_name= snowflake_schema.raw_schema.fully_qualified_name
  }
}

# the SELECT privilege on the tables allows the dbt role to query the data in the tables.
resource "snowflake_grant_privileges_to_account_role" "schema_tables" {
  provider = snowflake.sysadmin
  privileges        = ["SELECT"]
  account_role_name = var.dbt_role

  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = snowflake_schema.raw_schema.fully_qualified_name 
    }
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
    name    = "JSONTEXT"
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

resource "snowflake_user" "dbt_svc" {
  provider = snowflake.accountadmin
  name              = "DBT_SVC"
  password          = var.dbt_svc_password
  default_role      = var.dbt_role
  default_warehouse = snowflake_warehouse.credit_data_platform_warehouse.fully_qualified_name
  must_change_password = false
}

resource "snowflake_grant_account_role" "dbt_svc_role_grant" {
  provider = snowflake.accountadmin
  role_name = var.dbt_role
  user_name = snowflake_user.dbt_svc.name
}


## lambda function
## lambda function requres a deployment package and an execution role
## lambda code must be uploaded as either a zip file or a container image as the deployment package. 
# Here we use a zip file that contains the lambda function

# Typically a lambda function will automatically come with a log group and log stream.
# However with terraform we need to manually create these as well as IAM policies to allow 
# the lambda function to write logs to cloudwatch.
#lambda log group

# in the future I'd create retries for the lambda function. 
resource "aws_cloudwatch_log_group" "credit_warehouse_log_group" {
  name = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 7

  tags = {
    Environment = "dev"
    Application = "credit-warehouse"
    Function   = var.lambda_function_name
  }
}

# IAM policy document for Lambda execution assume role
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# IAM role for Lambda execution
resource "aws_iam_role" "credit_warehouse_lambda_role" {
  name               = "credit_warehouse_lambda_execution_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# the lambda execution role policy document to allow the lambda function to write logs
# get secrets from secrets manager, and put records in S3. 
resource "aws_iam_policy" "credit_warehouse_lambda_policy" {
  name        = "credit-warehouse-lambda-policy"
  description = "adds the permissions for lambda to write logs to cloudwatch"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.oer_app_id.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [aws_s3_bucket.cw_world_bank_data.arn, "${aws_s3_bucket.cw_world_bank_data.arn}/fx-rates/*"]
      }
    ]
  })
}

#attaching credit warehouse policy to lambda role
resource "aws_iam_role_policy_attachment" "credit_warehouse_lambda_policy-attach" {
  role       = aws_iam_role.credit_warehouse_lambda_role.name
  policy_arn = aws_iam_policy.credit_warehouse_lambda_policy.arn
}

# Lambda function
resource "aws_lambda_function" "credit_warehouse_fx_rates_lambda" {
  filename         = "/Users/princeaker/Projects/credit_warehouse/lambda/deployment_package.zip"
  function_name    = var.lambda_function_name
  role             = aws_iam_role.credit_warehouse_lambda_role.arn
  memory_size      = 150
  handler          = "lambda_function.lambda_handler"
  runtime = "python3.12"

  # The source_code_hash is used by Terraform to determine if the code has changed 
  # and if the Lambda function needs to be updated.
  source_code_hash = filebase64sha256("/Users/princeaker/Projects/credit_warehouse/lambda/deployment_package.zip")

  timeout = 60

  environment {
    variables = {
      SECRET_ARN           = aws_secretsmanager_secret.oer_app_id.arn
    }
  }

  # Ensure IAM role and log group are ready
  depends_on = [
    aws_iam_role_policy_attachment.credit_warehouse_lambda_policy-attach,
    aws_cloudwatch_log_group.credit_warehouse_log_group
  ]

  tags = {
    Environment = "dev"
    Application = "credit-warehouse"
  }
}

# Secrets Manager secret to store the Open Exchange Rates App ID, 
# which will be used by the Lambda function to fetch exchange rates.
# The secret value is set manually in the AWS console.
resource "aws_secretsmanager_secret" "oer_app_id" {
  name = "oer_app_id"
  description = "Open Exchange Rates App ID"
}