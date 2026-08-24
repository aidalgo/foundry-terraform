terraform {
  required_version = ">= 1.11.4, < 2.0.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "2.12.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.81.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.13.1"
    }
  }
}

provider "azapi" {
  subscription_id = var.subscription_id
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }

    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

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

locals {
  name_prefix = "fndry-azrm-${var.run_id}"
  common_tags = merge(var.tags, {
    purpose  = "foundry-vnet-injection-diagnostic"
    scenario = "azurerm"
    run-id   = var.run_id
  })
}

# Phase 1 start: network test (test_phase = "network", "account", or "full").
module "network" {
  source = "../../modules/test-network"

  resource_group_name          = "rg-${local.name_prefix}"
  location                     = var.location
  virtual_network_name         = "vnet-${local.name_prefix}"
  virtual_network_cidr         = var.virtual_network_cidr
  agent_subnet_name            = "snet-agent-${var.run_id}"
  agent_subnet_cidr            = var.agent_subnet_cidr
  private_endpoint_subnet_name = "snet-pe-${var.run_id}"
  private_endpoint_subnet_cidr = var.private_endpoint_subnet_cidr
  tags                         = local.common_tags
}
# Phase 1 end: network test.

# Phase 2 start: Foundry account test (test_phase = "account" or "full").
module "account" {
  count  = contains(["account", "full"], var.test_phase) ? 1 : 0
  source = "../../modules/account-azurerm"

  account_name        = local.name_prefix
  resource_group_name = module.network.resource_group_name
  location            = var.location
  agent_subnet_id     = module.network.agent_subnet_id
  tags                = local.common_tags
}
# Phase 2 end: Foundry account test.

# Phase 3 start: complete Standard Agent deployment (test_phase = "full").
module "standard_agent" {
  count  = var.test_phase == "full" ? 1 : 0
  source = "../../modules/standard-agent"

  name_token                 = "azrm${var.run_id}"
  account_id                 = module.account[0].id
  resource_group_id          = module.network.resource_group_id
  resource_group_name        = module.network.resource_group_name
  location                   = var.location
  virtual_network_id         = module.network.virtual_network_id
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  project_name               = "project-${var.run_id}"
  tags                       = local.common_tags
}
# Phase 3 end: complete Standard Agent deployment.

output "test_phase" {
  value = var.test_phase
}

output "resource_group_name" {
  value = module.network.resource_group_name
}

output "virtual_network_id" {
  value = module.network.virtual_network_id
}

output "agent_subnet_id" {
  value = module.network.agent_subnet_id
}

output "private_endpoint_subnet_id" {
  value = module.network.private_endpoint_subnet_id
}

output "account_name" {
  value = local.name_prefix
}

output "account_id" {
  value = try(module.account[0].id, null)
}

output "account_principal_id" {
  value = try(module.account[0].principal_id, null)
}

output "project_id" {
  value = try(module.standard_agent[0].project_id, null)
}

output "account_capability_host_id" {
  value = try(module.standard_agent[0].account_capability_host_id, null)
}

output "project_capability_host_id" {
  value = try(module.standard_agent[0].project_capability_host_id, null)
}
