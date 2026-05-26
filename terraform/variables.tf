variable "snowpipe_role" {
  description = "Name of the role to which Snowpipe integration privileges will be granted"
  type        = string
  default     = "SYSADMIN"
}

variable "dbt_role" {
  description = "Name of the role to which dbt integration privileges will be granted"
  type        = string
  default     = "DBT_ROLE"
}

variable "dbt_svc_password" {
  type      = string
  sensitive = true
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "credit-warehouse-dev-dump-fx-rates"
}