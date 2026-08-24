variable "name_token" {
  description = "Globally unique lowercase alphanumeric token used in data-service names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{4,16}$", var.name_token))
    error_message = "name_token must contain 4-16 lowercase letters or digits."
  }
}

variable "account_id" {
  description = "Foundry account resource ID from the successful account phase."
  type        = string
}

variable "resource_group_id" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "virtual_network_id" {
  type = string
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "project_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
