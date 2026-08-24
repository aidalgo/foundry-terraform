output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "resource_group_id" {
  value = azurerm_resource_group.this.id
}

output "virtual_network_id" {
  value = azurerm_virtual_network.this.id
}

output "virtual_network_name" {
  value = azurerm_virtual_network.this.name
}

output "agent_subnet_id" {
  value = azurerm_subnet.agent.id
}

output "agent_subnet_name" {
  value = azurerm_subnet.agent.name
}

output "private_endpoint_subnet_id" {
  value = azurerm_subnet.private_endpoint.id
}
