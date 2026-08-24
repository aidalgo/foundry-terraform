locals {
  name_prefix = "fndry-azrm-${var.run_id}"
  common_tags = merge(var.tags, {
    purpose  = "foundry-vnet-injection-diagnostic"
    scenario = "azurerm"
    run-id   = var.run_id
  })
}

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

module "account" {
  count  = contains(["account", "full"], var.test_phase) ? 1 : 0
  source = "../../modules/account-azurerm"

  account_name        = local.name_prefix
  resource_group_name = module.network.resource_group_name
  location            = var.location
  agent_subnet_id     = module.network.agent_subnet_id
  tags                = local.common_tags
}

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
