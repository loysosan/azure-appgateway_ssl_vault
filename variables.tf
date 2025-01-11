############# Subscription ID Credentials ############
variable "subscription_id" {
  description = "The subscription ID for Azure"
  type        = string
}

variable "client_id" {
  description = "Client ID for Azure"
  type        = string
}

variable "client_secret" {
  description = "Client Secret for Azure"
  type        = string
}

variable "tenant_id" {
  description = "Tenant ID for Azure"
  type        = string
}

variable "location" {
  type = string
  default = "North Central US"
}

variable "ag_vault_resource_group_name_rg" {
    type = string
  
}

variable "ssh_public_key" {
  type = string 
  default = ""
}

variable "key_vault_name" {
  type = string
  default = "platform-vault-ssl"
}