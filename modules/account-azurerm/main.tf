resource "azurerm_cognitive_account" "this" {
  name                          = var.account_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  kind                          = "AIServices"
  sku_name                      = "S0"
  custom_subdomain_name         = var.account_name
  local_auth_enabled            = false
  project_management_enabled    = true
  public_network_access_enabled = false
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }

  network_injection {
    scenario  = "agent"
    subnet_id = var.agent_subnet_id
  }

  timeouts {
    create = "90m"
    delete = "90m"
  }
}
