variable "account_name" {
  description = "Globally unique Foundry account name. Never reuse after a failed create."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the Foundry account."
  type        = string
}

variable "location" {
  description = "Foundry account region."
  type        = string
}

variable "agent_subnet_id" {
  description = "Exact resource ID of the dedicated delegated agent subnet."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
