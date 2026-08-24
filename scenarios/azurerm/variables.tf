variable "subscription_id" {
  description = "Azure subscription used for this disposable test."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription GUID."
  }
}

variable "run_id" {
  description = "Unique lowercase identifier for this run. Never reuse it after an account create attempt."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{4,12}$", var.run_id))
    error_message = "run_id must contain 4-12 lowercase letters or digits."
  }
}

variable "test_phase" {
  description = "Highest diagnostic layer to create: network, account, or full."
  type        = string
  default     = "network"

  validation {
    condition     = contains(["network", "account", "full"], var.test_phase)
    error_message = "test_phase must be network, account, or full."
  }
}

variable "location" {
  description = "Region under test. Keep Foundry and the VNet in the same region."
  type        = string
  default     = "eastus2"
}

variable "virtual_network_cidr" {
  type    = string
  default = "10.242.0.0/23"
}

variable "agent_subnet_cidr" {
  type    = string
  default = "10.242.0.0/24"
}

variable "private_endpoint_subnet_cidr" {
  type    = string
  default = "10.242.1.0/24"
}

variable "tags" {
  type    = map(string)
  default = {}
}
