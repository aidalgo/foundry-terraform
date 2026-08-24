output "project_id" {
  value = azapi_resource.project.id
}

output "project_name" {
  value = azapi_resource.project.name
}

output "project_principal_id" {
  value = azapi_resource.project.output.identity.principalId
}

output "account_capability_host_id" {
  value = azapi_resource.account_capability_host.id
}

output "project_capability_host_id" {
  value = azapi_resource.project_capability_host.id
}

output "storage_account_id" {
  value = azurerm_storage_account.this.id
}

output "cosmosdb_account_id" {
  value = azurerm_cosmosdb_account.this.id
}

output "search_service_id" {
  value = azapi_resource.search.id
}