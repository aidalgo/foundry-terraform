terraform {
  required_version = ">= 1.11.4, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.81.0"
    }
  }
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
  description = "Unique lowercase identifier for this run."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{4,12}$", var.run_id))
    error_message = "run_id must contain 4-12 lowercase letters or digits."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus2"
}

variable "virtual_network_cidr" {
  description = "Address space for the test VNet."
  type        = string
  default     = "10.244.0.0/22"
}

variable "container_apps_subnet_cidr" {
  description = "Dedicated subnet for the Container Apps workload-profiles environment."
  type        = string
  default     = "10.244.0.0/23"
}

variable "private_endpoint_subnet_cidr" {
  description = "Dedicated subnet for the Foundry private endpoint."
  type        = string
  default     = "10.244.2.0/24"
}

variable "container_image" {
  description = "Public image that runs the HTTPS connectivity probe."
  type        = string
  default     = "mcr.microsoft.com/azure-cli:2.77.0"
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}

locals {
  name_prefix  = "aca-fndry-${var.run_id}"
  foundry_name = "fndry-pe-${var.run_id}"

  common_tags = merge(var.tags, {
    purpose  = "aca-private-foundry-test"
    scenario = "aca-private-endpoint"
    run-id   = var.run_id
  })

  foundry_private_dns_zones = toset([
    "privatelink.cognitiveservices.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.services.ai.azure.com"
  ])

  probe_script = <<-PY
    import ipaddress
    import json
    import os
    import socket
    import urllib.error
    import urllib.parse
    import urllib.request
    from http.server import BaseHTTPRequestHandler, HTTPServer

    endpoint = os.environ["FOUNDRY_ENDPOINT"]
    hostname = urllib.parse.urlparse(endpoint).hostname

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            result = {"endpoint": endpoint, "hostname": hostname}
            try:
                addresses = socket.gethostbyname_ex(hostname)[2]
                result["addresses"] = addresses
                result["private_dns"] = bool(addresses) and all(
                    ipaddress.ip_address(address).is_private for address in addresses
                )
            except Exception as error:
                result["dns_error"] = str(error)
                result["network_reachable"] = False
            else:
                try:
                    with urllib.request.urlopen(endpoint, timeout=10) as response:
                        result["http_status"] = response.status
                except urllib.error.HTTPError as error:
                    result["http_status"] = error.code
                    result["network_reachable"] = True
                except Exception as error:
                    result["https_error"] = str(error)
                    result["network_reachable"] = False
                else:
                    result["network_reachable"] = True

            body = json.dumps(result, indent=2).encode()
            self.send_response(200 if result.get("network_reachable") else 503)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):
            return

    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
  PY
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.virtual_network_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "container_apps" {
  name                 = "snet-aca-${var.run_id}"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.container_apps_subnet_cidr]

  delegation {
    name = "container-apps-environment"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoint" {
  name                              = "snet-pe-${var.run_id}"
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.private_endpoint_subnet_cidr]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_cognitive_account" "foundry" {
  name                          = local.foundry_name
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  kind                          = "AIServices"
  sku_name                      = "S0"
  custom_subdomain_name         = local.foundry_name
  local_auth_enabled            = false
  project_management_enabled    = true
  public_network_access_enabled = false
  tags                          = local.common_tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_private_dns_zone" "foundry" {
  for_each = local.foundry_private_dns_zones

  name                = each.value
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "foundry" {
  for_each = local.foundry_private_dns_zones

  name                  = "${replace(each.value, ".", "-")}-${var.run_id}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.foundry[each.key].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_endpoint" "foundry" {
  name                = "pe-${local.foundry_name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoint.id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-${local.foundry_name}"
    private_connection_resource_id = azurerm_cognitive_account.foundry.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "foundry"
    private_dns_zone_ids = [for zone in azurerm_private_dns_zone.foundry : zone.id]
  }
}

resource "azurerm_container_app_environment" "this" {
  name                           = "cae-${local.name_prefix}"
  location                       = azurerm_resource_group.this.location
  resource_group_name            = azurerm_resource_group.this.name
  infrastructure_subnet_id       = azurerm_subnet.container_apps.id
  internal_load_balancer_enabled = false
  tags                           = local.common_tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
    minimum_count         = 0
    maximum_count         = 10
  }
}

resource "azurerm_container_app" "probe" {
  name                         = "ca-${local.name_prefix}"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name    = "foundry-probe"
      image   = var.container_image
      cpu     = 0.25
      memory  = "0.5Gi"
      command = ["/bin/sh", "-c"]
      args = [
        "echo '${base64encode(local.probe_script)}' | base64 -d > /tmp/probe.py && python3 -u /tmp/probe.py"
      ]

      env {
        name  = "FOUNDRY_ENDPOINT"
        value = "https://${local.foundry_name}.services.ai.azure.com/"
      }
    }
  }

  depends_on = [
    azurerm_private_endpoint.foundry,
    azurerm_private_dns_zone_virtual_network_link.foundry
  ]
}

resource "azurerm_role_assignment" "foundry_user" {
  scope                            = azurerm_cognitive_account.foundry.id
  role_definition_name             = "Cognitive Services User"
  principal_id                     = azurerm_container_app.probe.identity[0].principal_id
  skip_service_principal_aad_check = true
}

output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "foundry_account_name" {
  value = azurerm_cognitive_account.foundry.name
}

output "foundry_public_network_access_enabled" {
  value = azurerm_cognitive_account.foundry.public_network_access_enabled
}

output "foundry_private_endpoint_ip" {
  value = azurerm_private_endpoint.foundry.private_service_connection[0].private_ip_address
}

output "container_app_url" {
  value = "https://${azurerm_container_app.probe.latest_revision_fqdn}"
}

output "test_command" {
  value = "curl -sS https://${azurerm_container_app.probe.latest_revision_fqdn}"
}