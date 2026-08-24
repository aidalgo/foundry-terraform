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
