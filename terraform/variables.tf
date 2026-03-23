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