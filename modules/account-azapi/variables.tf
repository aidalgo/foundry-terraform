variable "account_name" {
  description = "Globally unique Foundry account name. Never reuse after a failed create."
  type        = string
}

variable "resource_group_id" {
  description = "Resource group resource ID."
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

variable "api_version" {
  description = "Cognitive Services API version used for the account request."
  type        = string
  default     = "2025-06-01"

  validation {
    condition     = contains(["2025-06-01", "2026-03-01"], var.api_version)
    error_message = "api_version must be 2025-06-01 or 2026-03-01."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
