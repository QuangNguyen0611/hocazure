variable "storage_account_name" {
  type        = string
  description = "Tên của storage account"
}

variable "tenant_id" {
  type      = string
  sensitive = true
}
variable "admin_password" {
  type      = string
  sensitive = true
}

variable "subscription_id" {
  type      = string
  sensitive = true
}

variable "admin_username" {
  type      = string
  sensitive = true
}

variable "keyvault" {
  type      = string
  sensitive = true
}


