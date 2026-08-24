locals {
  request_body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    identity = {
      type = "SystemAssigned"
    }
    properties = {
      allowProjectManagement = true
      customSubDomainName    = var.account_name
      disableLocalAuth       = true
      publicNetworkAccess    = "Disabled"
      networkInjections = [{
        scenario                   = "agent"
        subnetArmId                = var.agent_subnet_id
        useMicrosoftManagedNetwork = false
      }]
    }
  }
}

resource "azapi_resource" "this" {
  type      = "Microsoft.CognitiveServices/accounts@${var.api_version}"
  name      = var.account_name
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags
  body      = local.request_body

  timeouts {
    create = "90m"
    delete = "90m"
  }
}
