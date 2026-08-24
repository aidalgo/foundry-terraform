#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  preflight.sh --subscription ID --account NAME [--tenant ID] [--subnet-id ID]

Run once before the network phase without --subnet-id, then again after the
network phase with the Terraform agent_subnet_id output.
EOF
}

subscription_id=""
tenant_id=""
account_name=""
subnet_id=""

while (($# > 0)); do
  case "$1" in
    --subscription) subscription_id="${2:-}"; shift 2 ;;
    --tenant) tenant_id="${2:-}"; shift 2 ;;
    --account) account_name="${2:-}"; shift 2 ;;
    --subnet-id) subnet_id="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$subscription_id" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "Invalid --subscription GUID." >&2; exit 2; }
[[ "$account_name" =~ ^[a-z0-9-]{2,64}$ ]] || { echo "Invalid --account name." >&2; exit 2; }
if [[ -n "$tenant_id" && ! "$tenant_id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "Invalid --tenant GUID." >&2
  exit 2
fi

for command_name in az terraform; do
  command -v "$command_name" >/dev/null || { echo "Missing required command: $command_name" >&2; exit 1; }
done

terraform_version="$(terraform version -json | sed -n 's/.*"terraform_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
IFS=. read -r terraform_major terraform_minor terraform_patch <<<"$terraform_version"
terraform_patch="${terraform_patch%%-*}"
if ((terraform_major != 1 || terraform_minor < 11 || (terraform_minor == 11 && terraform_patch < 4))); then
  echo "Terraform >=1.11.4 and <2.0.0 is required; found ${terraform_version:-unknown}." >&2
  exit 1
fi

active_subscription="$(az account show --query id -o tsv 2>/dev/null)" || {
  echo "Azure CLI is not logged in. Run az login first." >&2
  exit 1
}
active_tenant="$(az account show --query tenantId -o tsv)"

[[ "$active_subscription" == "$subscription_id" ]] || {
  echo "Active subscription is $active_subscription, expected $subscription_id." >&2
  exit 1
}
if [[ -n "$tenant_id" && "$active_tenant" != "$tenant_id" ]]; then
  echo "Active tenant is $active_tenant, expected $tenant_id." >&2
  exit 1
fi

providers=(
  Microsoft.App
  Microsoft.CognitiveServices
  Microsoft.ContainerService
  Microsoft.DocumentDB
  Microsoft.MachineLearningServices
  Microsoft.Network
  Microsoft.Search
  Microsoft.Storage
)

for namespace in "${providers[@]}"; do
  registration_state="$(az provider show --namespace "$namespace" --query registrationState -o tsv)"
  if [[ "$registration_state" != "Registered" ]]; then
    echo "$namespace is $registration_state; register it before testing." >&2
    exit 1
  fi
done

live_account_id="$(az cognitiveservices account list --query "[?name=='$account_name'].id | [0]" -o tsv)"
[[ -z "$live_account_id" ]] || {
  echo "Account name $account_name already exists: $live_account_id" >&2
  exit 1
}

deleted_account_id="$(az cognitiveservices account list-deleted --query "[?name=='$account_name'].id | [0]" -o tsv)"
[[ -z "$deleted_account_id" ]] || {
  echo "Account name $account_name is soft-deleted: $deleted_account_id" >&2
  exit 1
}

if [[ -n "$subnet_id" ]]; then
  subnet_json="$(az network vnet subnet show --ids "$subnet_id" -o json)"
  provisioning_state="$(az network vnet subnet show --ids "$subnet_id" --query provisioningState -o tsv)"
  address_prefix="$(az network vnet subnet show --ids "$subnet_id" --query addressPrefix -o tsv)"
  if [[ -z "$address_prefix" ]]; then
    address_prefix="$(az network vnet subnet show --ids "$subnet_id" --query 'addressPrefixes[0]' -o tsv)"
  fi

  [[ "$provisioning_state" == "Succeeded" ]] || { echo "Subnet provisioning state is $provisioning_state." >&2; exit 1; }

  prefix_length="${address_prefix#*/}"
  if [[ ! "$address_prefix" =~ ^10\. && ! "$address_prefix" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. && ! "$address_prefix" =~ ^192\.168\. ]]; then
    echo "Agent subnet is not in RFC1918 space: $address_prefix" >&2
    exit 1
  fi
  ((prefix_length <= 27)) || { echo "Agent subnet must be /27 or larger: $address_prefix" >&2; exit 1; }

  delegation_count="$(az network vnet subnet show --ids "$subnet_id" --query 'length(delegations || `[]`)' -o tsv)"
  delegation_name="$(az network vnet subnet show --ids "$subnet_id" --query 'delegations[0].serviceName' -o tsv)"
  [[ "$delegation_count" == "1" && "$delegation_name" == "Microsoft.App/environments" ]] || {
    echo "Expected exactly one Microsoft.App/environments delegation." >&2
    exit 1
  }

  for query_and_label in \
    'networkSecurityGroup.id|network security group' \
    'routeTable.id|route table' \
    'natGateway.id|NAT gateway'; do
    query="${query_and_label%%|*}"
    label="${query_and_label#*|}"
    value="$(az network vnet subnet show --ids "$subnet_id" --query "$query" -o tsv)"
    [[ -z "$value" ]] || { echo "Agent subnet has a $label: $value" >&2; exit 1; }
  done

  for property_and_label in \
    'serviceEndpoints|service endpoints' \
    'ipConfigurations|IP configurations' \
    'serviceAssociationLinks|service association links'; do
    property="${property_and_label%%|*}"
    label="${property_and_label#*|}"
    count="$(az network vnet subnet show --ids "$subnet_id" --query "length(${property} || \`[]\`)" -o tsv)"
    [[ "$count" == "0" ]] || { echo "Agent subnet has $count $label." >&2; exit 1; }
  done

  virtual_network_id="${subnet_id%/subnets/*}"
  custom_dns_count="$(az network vnet show --ids "$virtual_network_id" --query 'length(dhcpOptions.dnsServers || `[]`)' -o tsv)"
  [[ "$custom_dns_count" == "0" ]] || { echo "Diagnostic VNet has custom DNS servers." >&2; exit 1; }

  printf '%s\n' "$subnet_json" >/dev/null
fi

echo "Preflight passed for account $account_name in subscription $subscription_id."
