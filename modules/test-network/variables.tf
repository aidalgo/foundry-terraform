variable "resource_group_name" {
  description = "Name of the disposable resource group."
  type        = string
}

variable "location" {
  description = "Azure region used by the Foundry account and virtual network."
  type        = string
}

variable "virtual_network_name" {
  description = "Name of the disposable virtual network."
  type        = string
}

variable "virtual_network_cidr" {
  description = "RFC1918 address space for the disposable virtual network."
  type        = string
}

variable "agent_subnet_name" {
  description = "Name of the subnet dedicated to one Foundry account."
  type        = string
}

variable "agent_subnet_cidr" {
  description = "RFC1918 CIDR for the dedicated agent subnet. A /24 is recommended and /27 is the minimum."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.agent_subnet_cidr)) && tonumber(split("/", var.agent_subnet_cidr)[1]) <= 27
    error_message = "agent_subnet_cidr must be a valid CIDR with a /27 or larger address range."
  }

  validation {
    condition = anytrue([
      startswith(var.agent_subnet_cidr, "10."),
      can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", var.agent_subnet_cidr)),
      startswith(var.agent_subnet_cidr, "192.168.")
    ])
    error_message = "agent_subnet_cidr must use RFC1918 private IPv4 space."
  }
}

variable "private_endpoint_subnet_name" {
  description = "Name of the subnet used for private endpoints in the full phase."
  type        = string
}

variable "private_endpoint_subnet_cidr" {
  description = "CIDR for the private endpoint subnet."
  type        = string
}

variable "tags" {
  description = "Tags applied to diagnostic resources."
  type        = map(string)
  default     = {}
}
