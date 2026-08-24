locals {
  storage_name = "stf${var.name_token}"
  cosmos_name  = "cosmos-${var.name_token}"
  search_name  = "search-${var.name_token}"

  private_dns_zones = {
    blob      = "privatelink.blob.core.windows.net"
    cognitive = "privatelink.cognitiveservices.azure.com"
    cosmos    = "privatelink.documents.azure.com"
    openai    = "privatelink.openai.azure.com"
    search    = "privatelink.search.windows.net"
    services  = "privatelink.services.ai.azure.com"
  }
}

resource "azurerm_storage_account" "this" {
  name                            = local.storage_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  shared_access_key_enabled       = false
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = false
  tags                            = var.tags

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

resource "azurerm_cosmosdb_account" "this" {
  name                          = local.cosmos_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  offer_type                    = "Standard"
  kind                          = "GlobalDocumentDB"
  local_authentication_enabled  = false
  public_network_access_enabled = false
  automatic_failover_enabled    = false
  tags                          = var.tags

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
    zone_redundant    = false
  }
}

resource "azapi_resource" "search" {
  type      = "Microsoft.Search/searchServices@2025-05-01"
  name      = local.search_name
  parent_id = var.resource_group_id
  location  = var.location
  tags      = var.tags

  body = {
    sku = {
      name = "standard"
    }
    identity = {
      type = "SystemAssigned"
    }
    properties = {
      replicaCount     = 1
      partitionCount   = 1
      hostingMode      = "Default"
      semanticSearch   = "disabled"
      disableLocalAuth = false
      authOptions = {
        aadOrApiKey = {
          aadAuthFailureMode = "http401WithBearerChallenge"
        }
      }
      publicNetworkAccess = "Disabled"
      networkRuleSet = {
        bypass = "None"
      }
    }
  }
}

resource "azurerm_private_dns_zone" "this" {
  for_each = local.private_dns_zones

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.private_dns_zones

  name                  = "${each.key}-${var.name_token}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.key].name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "storage" {
  name                = "pe-${local.storage_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${local.storage_name}"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.this["blob"].id]
  }
}

resource "azurerm_private_endpoint" "cosmos" {
  name                = "pe-${local.cosmos_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${local.cosmos_name}"
    private_connection_resource_id = azurerm_cosmosdb_account.this.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "cosmos"
    private_dns_zone_ids = [azurerm_private_dns_zone.this["cosmos"].id]
  }
}

resource "azurerm_private_endpoint" "search" {
  name                = "pe-${local.search_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${local.search_name}"
    private_connection_resource_id = azapi_resource.search.id
    subresource_names              = ["searchService"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "search"
    private_dns_zone_ids = [azurerm_private_dns_zone.this["search"].id]
  }
}

resource "azurerm_private_endpoint" "foundry" {
  name                = "pe-foundry-${var.name_token}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-foundry-${var.name_token}"
    private_connection_resource_id = var.account_id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "foundry"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.this["cognitive"].id,
      azurerm_private_dns_zone.this["openai"].id,
      azurerm_private_dns_zone.this["services"].id
    ]
  }
}

resource "azapi_resource" "project" {
  type                      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name                      = var.project_name
  parent_id                 = var.account_id
  location                  = var.location
  schema_validation_enabled = false

  body = {
    sku = {
      name = "S0"
    }
    identity = {
      type = "SystemAssigned"
    }
    properties = {
      displayName = var.project_name
      description = "Disposable standard-agent VNet injection diagnostic project"
    }
  }

  depends_on = [
    azurerm_private_endpoint.storage,
    azurerm_private_endpoint.cosmos,
    azurerm_private_endpoint.search,
    azurerm_private_endpoint.foundry
  ]
}

resource "time_sleep" "project_identity" {
  create_duration = "10s"
  depends_on      = [azapi_resource.project]
}

resource "azapi_resource" "connection_cosmos" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name                      = local.cosmos_name
  parent_id                 = azapi_resource.project.id
  schema_validation_enabled = false

  body = {
    name = local.cosmos_name
    properties = {
      category = "CosmosDb"
      target   = azurerm_cosmosdb_account.this.endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_cosmosdb_account.this.id
        location   = var.location
      }
    }
  }
}

resource "azapi_resource" "connection_storage" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name                      = local.storage_name
  parent_id                 = azapi_resource.project.id
  schema_validation_enabled = false

  body = {
    name = local.storage_name
    properties = {
      category = "AzureStorageAccount"
      target   = azurerm_storage_account.this.primary_blob_endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_storage_account.this.id
        location   = var.location
      }
    }
  }
}

resource "azapi_resource" "connection_search" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name                      = local.search_name
  parent_id                 = azapi_resource.project.id
  schema_validation_enabled = false

  body = {
    name = local.search_name
    properties = {
      category = "CognitiveSearch"
      target   = "https://${local.search_name}.search.windows.net"
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ApiVersion = "2025-05-01-preview"
        ResourceId = azapi_resource.search.id
        location   = var.location
      }
    }
  }
}

resource "azurerm_role_assignment" "cosmos_operator" {
  scope                            = azurerm_cosmosdb_account.this.id
  role_definition_name             = "Cosmos DB Operator"
  principal_id                     = azapi_resource.project.output.identity.principalId
  skip_service_principal_aad_check = true
  depends_on                       = [time_sleep.project_identity]
}

resource "azurerm_role_assignment" "storage_blob_contributor" {
  scope                            = azurerm_storage_account.this.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azapi_resource.project.output.identity.principalId
  skip_service_principal_aad_check = true
  depends_on                       = [time_sleep.project_identity]
}

resource "azurerm_role_assignment" "search_index_contributor" {
  scope                            = azapi_resource.search.id
  role_definition_name             = "Search Index Data Contributor"
  principal_id                     = azapi_resource.project.output.identity.principalId
  skip_service_principal_aad_check = true
  depends_on                       = [time_sleep.project_identity]
}

resource "azurerm_role_assignment" "search_service_contributor" {
  scope                            = azapi_resource.search.id
  role_definition_name             = "Search Service Contributor"
  principal_id                     = azapi_resource.project.output.identity.principalId
  skip_service_principal_aad_check = true
  depends_on                       = [time_sleep.project_identity]
}

resource "time_sleep" "rbac" {
  create_duration = "60s"
  depends_on = [
    azurerm_role_assignment.cosmos_operator,
    azurerm_role_assignment.storage_blob_contributor,
    azurerm_role_assignment.search_index_contributor,
    azurerm_role_assignment.search_service_contributor
  ]
}

resource "azapi_resource" "account_capability_host" {
  type                      = "Microsoft.CognitiveServices/accounts/capabilityHosts@2025-06-01"
  name                      = "agents"
  parent_id                 = var.account_id
  schema_validation_enabled = false

  body = {
    properties = {}
  }

  timeouts {
    create = "90m"
    delete = "90m"
  }

  depends_on = [time_sleep.rbac]
}

resource "azapi_resource" "project_capability_host" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-06-01"
  name                      = "agents"
  parent_id                 = azapi_resource.project.id
  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind = "Agents"
      vectorStoreConnections = [
        azapi_resource.connection_search.name
      ]
      storageConnections = [
        azapi_resource.connection_storage.name
      ]
      threadStorageConnections = [
        azapi_resource.connection_cosmos.name
      ]
    }
  }

  timeouts {
    create = "90m"
    delete = "90m"
  }

  depends_on = [
    azapi_resource.account_capability_host,
    azapi_resource.connection_cosmos,
    azapi_resource.connection_storage,
    azapi_resource.connection_search
  ]
}

resource "azurerm_cosmosdb_sql_role_assignment" "data_contributor" {
  name                = uuidv5("dns", "${var.project_name}-${var.name_token}-cosmos-data")
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name
  scope               = azurerm_cosmosdb_account.this.id
  role_definition_id  = "${azurerm_cosmosdb_account.this.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azapi_resource.project.output.identity.principalId
  depends_on          = [azapi_resource.project_capability_host]
}

resource "azurerm_role_assignment" "storage_blob_owner" {
  scope                            = azurerm_storage_account.this.id
  role_definition_name             = "Storage Blob Data Owner"
  principal_id                     = azapi_resource.project.output.identity.principalId
  skip_service_principal_aad_check = true
  depends_on                       = [azapi_resource.project_capability_host]
}
