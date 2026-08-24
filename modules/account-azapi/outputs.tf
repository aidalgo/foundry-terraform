output "id" {
  value = azapi_resource.this.id
}

output "name" {
  value = azapi_resource.this.name
}

output "principal_id" {
  value = try(azapi_resource.this.output.identity.principalId, null)
}

output "provisioning_state" {
  value = try(azapi_resource.this.output.properties.provisioningState, null)
}

output "request_body" {
  value = local.request_body
}

output "api_version" {
  value = var.api_version
}
